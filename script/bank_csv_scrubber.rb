require "bigdecimal"
require "date"
require "fileutils"
require "openssl"
require "securerandom"
require "strscan"

# Development-only. Writes a copy of a real bank CSV with identifying data replaced, keeping the
# structure the importer cares about: delimiter, quoting, header, blank lines, line endings, row
# order, date and amount formats, and (by default) the dates, amounts, and balances themselves.
#
# Runs entirely locally and never modifies the input file. Replacements come from a key that is
# random per run and never saved, so they are consistent within one output file but can't be
# traced back to the original values.
#
#   bin/scrub-bank-csv [--preview] [--strict] [--randomize-amounts] [--scrub-balances] [--shift-dates] INPUT.csv
class BankCsvScrubber
  class Error < StandardError; end

  OUTPUT_DIR = File.expand_path("../tmp/scrubbed-bank-data", __dir__)
  DELIMITERS = [ ",", ";", "\t", "|" ].freeze

  DATE_FAMILIES = [
    [ "%Y-%m-%d" ],
    [ "%m/%d/%Y", "%-m/%-d/%Y" ],
    [ "%d/%m/%Y", "%-d/%-m/%Y" ],
    [ "%Y/%m/%d" ],
    [ "%m/%d/%y", "%-m/%-d/%y" ],
    [ "%d-%b-%Y", "%-d-%b-%Y" ],
    [ "%d %b %Y", "%-d %b %Y" ],
    [ "%b %d, %Y", "%b %-d, %Y" ],
    [ "%Y%m%d" ]
  ].freeze

  AMOUNT = /\A(?<lead>\s*)(?<sign>[-+(]?)(?<currency>\s*[$€£]?\s*)(?<sign2>-?)
    (?<units>\d{1,3}(?:(?<group>[,. '])\d{3})+|\d+)(?:(?<point>[.,])(?<cents>\d{1,2}))?(?<trail>\)?\s*)\z/x

  TOKEN = /
    (?<email>[\w.+-]+@[\w-]+(?:\.[\w-]+)+)
    |(?<phone>(?:\+?1[\s.-]?)?(?:\(\d{3}\)\s?|\d{3}[\s.-])\d{3}[\s.-]\d{4}\b)
    |(?<postal>\b[A-Za-z]\d[A-Za-z]\s?\d[A-Za-z]\d\b)
    |(?<masked>[*xX]{2,}[\p{L}\d]*\d[\p{L}\d]*|\d+[*xX]{3,}\d+)
    |(?<code>[\p{L}\d]*\d[\p{L}\d]*)
    |(?<word>\p{L}[\p{L}']*)
    |(?<other>.)
  /mx
  TOKEN_TYPES = %i[email phone postal masked code word other].freeze

  TRANSFER = /\b(E-?TRANSFERS?|E-?TFR|ETRNSFR|EMT|TRANSFERS?|TFR|XFER|ZELLE|VENMO)\b/i

  IDENTIFIER_HEADER = /account|acct|card|transit|branch|customer|client|member|cheque|\bcheck|chq|reference|\bref\b|
    confirmation|\bid\b|number|\bno\b|address|street|postal|zip|phone|e-?mail/ix
  NOT_IDENTIFIER_HEADER = /type|date|amount|balance|desc|memo|detail/i
  # Header cells are kept as-is, so only rows that look like column names count as a header.
  COLUMN_NAME = /\A[\p{L} $#.\/()&_'-]{0,40}\d?\z/

  # Words that describe the transaction rather than who it was with.
  BANK_WORDS = %w[
    TO FROM FOR AT OF THE AND BY VIA WITH IN ON
    E TRANSFER TRANSFERS TFR TRF XFER ETRANSFER ETFR ETRNSFR EMT INTERAC SEND SENT RECEIVED RECV RCVD REQUEST
    AUTODEPOSIT AUTO DEPOSIT DEP WITHDRAWAL WITHDRAW WD ATM ABM POS PURCHASE PUR PMT PYMT PAYMENT PAYMENTS PAY
    PAYROLL SALARY BILL BILLPAY FEE FEES CHARGE CHARGES SERVICE SVC MONTHLY ANNUAL PLAN INTEREST INT CHQ CHEQUE
    CHECK CHK DEBIT CREDIT MEMO REFUND RETURN RETURNED REVERSAL REV ADJUSTMENT ADJ CASH BACK CASHBACK ONLINE
    BANKING MOBILE MB TB WEB INTL FX FOREIGN EXCHANGE CONVERSION OVERDRAFT NSF LOAN MORTGAGE MTG VISA MASTERCARD
    MC AMEX CARD ACCOUNT ACCT CHEQUING CHECKING SAVINGS BRANCH TELLER TRANSACTION TXN PREAUTHORIZED PREAUTH PAD
    GST HST PST TAX RECURRING SUBSCRIPTION CONTACTLESS TAP CHIP CR DR OPENING CLOSING BALANCE BAL REF CONF NO NUM
    ID PENDING BONUS GOVERNMENT GOVT
  ].freeze

  # Payment processor and platform prefixes that merchant normalization depends on.
  PROCESSOR_WORDS = %w[SQ SQU TST PAYPAL PP AMZN AMAZON MKTP MKTPL MARKETPLACE SP GOOGLE APPLE UBER DD WWW COM NET ORG].freeze

  REGION_WORDS = %w[
    ON QC BC AB MB SK NS NB NL PE YT NT NU CA CAN CANADA US USA GB UK
    AL AK AZ AR CO CT DE FL GA HI ID IL IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI
    SC SD TN TX UT VT VA WA WV WI WY DC
  ].freeze

  # Kept by default, replaced with --strict.
  CITY_WORDS = %w[
    TORONTO MONTREAL VANCOUVER CALGARY EDMONTON OTTAWA WINNIPEG QUEBEC HAMILTON KITCHENER WATERLOO LONDON VICTORIA
    HALIFAX OSHAWA WINDSOR SASKATOON REGINA MISSISSAUGA BRAMPTON MARKHAM VAUGHAN BURNABY SURREY RICHMOND OAKVILLE
    BURLINGTON GATINEAU LAVAL ETOBICOKE SCARBOROUGH NORTH SOUTH EAST WEST NEW YORK SEATTLE SAN FRANCISCO LOS
    ANGELES CHICAGO BOSTON
  ].freeze

  # Kept by default, replaced with --strict.
  CATEGORY_WORDS = %w[
    CAFE COFFEE RESTAURANT RESTO PIZZA PIZZERIA BURGER GRILL BAR PUB SUSHI THAI DELI BAKERY KITCHEN DINER FOOD
    FOODS GROCERY GROCERIES MARKET SUPERMARKET FARM PHARMACY DRUG DRUGS MART GAS FUEL STATION PARKING TAXI CAB
    TRANSIT AIRLINES AIR HOTEL INN MOTEL STORE STORES SHOP SHOPPE BOOKS CINEMA THEATRE THEATER GYM FITNESS CLUB
    SALON SPA CLINIC DENTAL MEDICAL HOSPITAL INSURANCE HYDRO ENERGY ELECTRIC WATER INTERNET MOBILITY WIRELESS
    TELECOM CABLE LIQUOR BEER WINE CO INC LTD LLC CORP COMPANY LIMITED
  ].freeze

  CONSONANTS = "BDFGKLMNPRSTVZ".chars.freeze
  VOWELS = "AEIOU".chars.freeze

  Field = Struct.new(:value, :quoted)
  Column = Struct.new(:index, :name, :kind, :date_family, :role)

  def self.call(input_path, **options)
    new(input_path, **options).call
  end

  attr_reader :input_path, :output_path

  def initialize(input_path, randomize_amounts: false, shift_dates: false, scrub_balances: false, strict: false)
    @input_path = File.expand_path(input_path)
    @randomize_amounts = randomize_amounts
    @shift_dates = shift_dates
    @scrub_balances = scrub_balances
    @strict = strict

    extension = File.extname(@input_path)
    extension = ".csv" if extension.empty?
    @output_path = File.join(OUTPUT_DIR, "#{File.basename(@input_path, ".*")}-scrubbed#{extension}")

    @secret = SecureRandom.bytes(32)
    @date_shift = -SecureRandom.random_number(30..365)
    @balance_offset = BigDecimal(SecureRandom.random_number(10_000..99_999)) / 100
    @counts = Hash.new(0)
    @scrambled = {}
    @merchant_words = {}
    @people = {}
    @emails = {}
    @phones = {}
    @warnings = []
  end

  # Writes the scrubbed copy and returns its path.
  def call
    raise Error, "refusing to overwrite the input file" if output_path == input_path

    content = scrubbed_content
    FileUtils.mkdir_p(OUTPUT_DIR)
    File.binwrite(output_path, content)
    output_path
  end

  # Describes what would be written, without writing anything.
  def preview
    scrubbed_content
    report
  end

  # A summary of the file's structure and what was replaced. Never includes original values.
  def report
    scrubbed_content
    lines = [
      "Input:  #{input_path}",
      "Output: #{output_path}",
      "Structure:",
      "  encoding: #{@encoding}#{" with BOM" if @bom}, line endings: #{@eol == "\r\n" ? "CRLF" : "LF"}, " \
        "trailing newline: #{@trailing_eol ? "yes" : "no"}",
      "  delimiter: #{@delimiter.inspect}, header: #{header? ? "yes" : "no"}, columns: #{columns.size}, " \
        "data rows: #{data_records.size}, blank lines: #{@records.count { |record| blank?(record) }}",
      "  quoted fields: #{quoting_summary}",
      "Columns:"
    ]
    columns.each { |column| lines << "  #{column.index + 1}. #{column_label(column)}" }
    lines << "Balances: #{@balance_summary}" if @balance_summary
    lines << "Replaced:"
    lines << "  merchant/name words: #{@merchant_words.size} distinct, #{@counts[:word]} occurrences"
    lines << "  people in transfers: #{@people.size} distinct, #{@counts[:person]} occurrences"
    %i[email phone postal masked code].zip(
      [ "emails", "phone numbers", "postal codes", "card/masked numbers", "account/reference numbers" ]
    ).each { |type, label| lines << "  #{label}: #{@counts[type]}" }
    lines << "  amounts: #{@counts[:amount]} randomized" if @randomize_amounts
    lines << "  dates: #{@counts[:date]} shifted by a hidden number of days" if @shift_dates
    lines << "  balances: #{@counts[:balance]} rewritten" if @randomize_amounts || @scrub_balances
    @warnings.each { |warning| lines << "Warning: #{warning}" }
    lines.join("\n")
  end

  def header?
    parse
    !@header_index.nil?
  end

  def columns
    @columns ||= begin
      parse
      count = data_records.map(&:size).tally.max_by { |size, frequency| [ frequency, size ] }&.first || 0
      count = [ count, header_record.size ].max if header?
      columns = Array.new(count) { |index| classify_column(index) }
      assign_amount_roles(columns)
      columns
    end
  end

  private
    attr_reader :delimiter

    # Reading and parsing

    def parse
      return if @records

      raise Error, "#{input_path} is not a file" unless File.file?(input_path)

      raw = File.binread(input_path)
      text = raw.dup.force_encoding(Encoding::UTF_8)
      if text.valid_encoding?
        @encoding = Encoding::UTF_8
      else
        @encoding = Encoding::ISO_8859_1
        text = raw.dup.force_encoding(@encoding).encode(Encoding::UTF_8)
      end
      @bom = text.start_with?("﻿")
      text = text.delete_prefix("﻿")
      @eol = text.include?("\r\n") ? "\r\n" : "\n"
      @trailing_eol = text.end_with?("\n", "\r")

      @delimiter = detect_delimiter(text)
      @records = parse_records(text, @delimiter)
      @header_index = detect_header
    end

    def detect_delimiter(text)
      scores = DELIMITERS.filter_map do |delimiter|
        sizes = parse_records(text, delimiter).reject { |record| blank?(record) }.map(&:size)
        next if sizes.empty? || sizes.max < 2

        common_size, frequency = sizes.tally.max_by { |size, count| [ count, size ] }
        [ delimiter, frequency.fdiv(sizes.size), common_size ] if common_size > 1
      rescue Error
        nil
      end
      scores.max_by { |_, consistency, size| [ consistency, size ] }&.first || ","
    end

    # A small RFC 4180 reader that remembers which fields were quoted.
    def parse_records(text, delimiter)
      scanner = StringScanner.new(text)
      separator = Regexp.new(Regexp.escape(delimiter))
      unquoted = Regexp.new("[^#{Regexp.escape(delimiter)}\r\n]*")
      records = []

      until scanner.eos?
        record = []
        loop do
          if scanner.scan(/"/)
            value = +""
            loop do
              value << scanner.scan(/[^"]*/)
              raise Error, "unclosed quoted field on line #{records.size + 1}" unless scanner.scan(/"/)
              break unless scanner.scan(/"/)

              value << '"'
            end
            record << Field.new(value, true)
          else
            record << Field.new(scanner.scan(unquoted), false)
          end
          break unless scanner.scan(separator)
        end
        unless scanner.scan(/\r\n|\n|\r/) || scanner.eos?
          raise Error, "unexpected text after a quoted field on line #{records.size + 1}"
        end
        records << record
      end
      records
    end

    def blank?(record)
      record.size == 1 && !record.first.quoted && record.first.value.strip.empty?
    end

    # The first non-blank row is a header when it holds only column names and later rows have dates or amounts.
    def detect_header
      indexes = @records.each_index.reject { |index| blank?(@records[index]) }
      return if indexes.size < 2

      first, *rest = indexes.map { |index| @records[index].map { |field| field.value.strip } }
      looks_like_data = ->(row) { row.any? { |value| date_value?(value) || parse_amount(value) } }
      indexes.first if first.all? { |value| value.match?(COLUMN_NAME) } && rest.any?(&looks_like_data)
    end

    def header_record
      @records[@header_index] if @header_index
    end

    def data_records
      @data_records ||= @records.each_with_index.filter_map do |record, index|
        record unless index == @header_index || blank?(record)
      end
    end

    # Column detection

    def classify_column(index)
      name = header_record&.[](index)&.value.to_s.strip
      values = data_records.map { |record| record[index]&.value.to_s.strip }.reject(&:empty?)
      column = Column.new(index, name, :text)

      if values.empty?
        column.kind = :empty
      elsif name.match?(IDENTIFIER_HEADER) && !name.match?(NOT_IDENTIFIER_HEADER)
        column.kind = :identifier
      elsif (family = DATE_FAMILIES.find { |formats| values.all? { |value| parse_date(value, formats) } })
        column.kind = :date
        column.date_family = family
      elsif values.all? { |value| parse_amount(value) } && values.any? { |value| AMOUNT.match(value)[:cents] }
        column.kind = :amount
      elsif values.all? { |value| !value.include?(" ") && value.count("0-9") >= 4 }
        column.kind = :identifier
      end
      column
    end

    def assign_amount_roles(columns)
      amounts = columns.select { |column| column.kind == :amount }
      balance = amounts.find { |column| column.name.match?(/balance/i) }
      if balance.nil? && !header? && amounts.size >= 2
        last = amounts.last
        balance = last if data_records.all? { |record| !record[last.index]&.value.to_s.strip.empty? }
      end
      balance&.role = :balance

      flows = amounts - [ balance ]
      if flows.size == 2
        debit = flows.find { |column| column.name.match?(/debit|withdraw|\bout\b|charge|paid out/i) } || flows.first
        debit.role = :debit
        (flows - [ debit ]).first.role = :credit
      else
        flows.each { |column| column.role = :amount }
      end
    end

    def date_value?(value)
      DATE_FAMILIES.any? { |formats| parse_date(value, formats) }
    end

    def parse_date(value, formats)
      formats.each do |format|
        date = Date.strptime(value, format.gsub("%-", "%"))
        return [ date, format ] if date.strftime(format) == value && (1970..2100).cover?(date.year)
      rescue Date::Error
        next
      end
      nil
    end

    def parse_amount(text)
      match = AMOUNT.match(text)
      return unless match
      return if match[:group] && match[:group] == match[:point]

      value = BigDecimal("#{match[:units].delete(match[:group].to_s)}.#{match[:cents] || 0}")
      negative = match[:sign] == "-" || match[:sign] == "(" || match[:sign2] == "-"
      negative ? -value : value
    end

    # Formats value the way the original amount text was formatted (sign style, currency, grouping, decimals).
    def format_amount(original, value)
      match = AMOUNT.match(original)
      cents = match[:cents]
      units, fraction = value.abs.round(cents ? cents.size : 0).to_s("F").split(".")
      units = units.reverse.scan(/\d{1,3}/).join(match[:group]).reverse if match[:group]
      number = cents ? "#{units}#{match[:point]}#{fraction.to_s.ljust(cents.size, "0")}" : units

      sign, sign2, trail = match[:sign], match[:sign2], match[:trail]
      was_negative = parse_amount(original).negative?
      if value.negative? && !was_negative
        sign = "-"
      elsif !value.negative? && was_negative
        sign = "" if sign == "-" || sign == "("
        sign2 = ""
        trail = trail.delete(")")
      end
      "#{match[:lead]}#{sign}#{match[:currency]}#{sign2}#{number}#{trail}"
    end

    # Scrubbing

    def scrubbed_content
      @scrubbed_content ||= begin
        parse
        output = @records.map { |record| record.map(&:value) }
        data_indexes = @records.each_index.reject { |index| index == @header_index || blank?(@records[index]) }
        data_indexes.each { |index| scrub_row(@records[index], output[index]) }
        rebalance(data_indexes.map { |index| [ @records[index], output[index] ] })

        lines = @records.zip(output).map do |record, values|
          record.zip(values).map { |field, value| format_field(value, field.quoted) }.join(delimiter)
        end
        text = lines.join(@eol)
        text << @eol if @trailing_eol
        text.prepend("﻿") if @bom
        text.encode(@encoding, undef: :replace, invalid: :replace).b
      end
    end

    def scrub_row(record, values)
      record.each_with_index do |field, index|
        column = columns[index] || Column.new(index, "", :text)
        values[index] =
          case column.kind
          when :date then shifted_date(field.value, column)
          when :amount then column.role == :balance ? field.value : randomized_amount(field.value)
          when :identifier then scrub_text(field.value, identifier: true)
          when :text then scrub_text(field.value)
          else field.value
          end
      end
    end

    def format_field(value, quoted)
      if quoted || value.include?(delimiter) || value.match?(/["\r\n]/)
        %("#{value.gsub('"', '""')}")
      else
        value
      end
    end

    def around_whitespace(text)
      leading, core, trailing = text.match(/\A(\s*)(.*?)(\s*)\z/m).captures
      core.empty? ? text : "#{leading}#{yield core}#{trailing}"
    end

    def shifted_date(text, column)
      return text unless @shift_dates

      around_whitespace(text) do |value|
        date, format = parse_date(value, column.date_family)
        @counts[:date] += 1
        (date + @date_shift).strftime(format)
      end
    end

    # Scales each distinct amount by the same factor everywhere, keeping its sign, so recurring
    # charges, refunds, and duplicate rows still match each other.
    def randomized_amount(text)
      return text unless @randomize_amounts

      around_whitespace(text) do |value|
        amount = parse_amount(value)
        next value if amount.zero?

        cents = AMOUNT.match(value)[:cents]
        step = BigDecimal(1) / (10**(cents&.size || 0))
        factor = BigDecimal("0.5") + BigDecimal(random_integer("amount:#{amount.abs.to_s("F")}") % 100_001) / 100_000
        scaled = [ (amount.abs * factor).round(cents&.size || 0), step ].max
        @counts[:amount] += 1
        format_amount(value, amount.negative? ? -scaled : scaled)
      end
    end

    def scrub_text(text, identifier: false)
      tokens = []
      text.scan(TOKEN) do
        match = Regexp.last_match
        tokens << [ TOKEN_TYPES.find { |type| match[type] }, match[0] ]
      end
      transfer = !identifier && text.match?(TRANSFER)

      output = +""
      index = 0
      while index < tokens.size
        type, token = tokens[index]
        if type == :word && replaceable_word?(token)
          if transfer
            last = person_name_end(tokens, index)
            output << person_for(tokens[index..last].map(&:last).join)
            index = last + 1
            next
          end
          output << merchant_word_for(token)
        else
          output << scrub_token(type, token, identifier)
        end
        index += 1
      end
      output
    end

    # A person's name is a run of replaceable words separated by single spaces.
    def person_name_end(tokens, index)
      last = index
      while tokens[last + 1] == [ :other, " " ] && tokens[last + 2]&.first == :word && replaceable_word?(tokens[last + 2].last)
        last += 2
      end
      last
    end

    def scrub_token(type, token, identifier)
      case type
      when :email then email_for(token)
      when :phone then phone_for(token)
      when :postal, :masked
        @counts[type] += 1
        scramble(token, keep: /[^\p{L}\d]|[xX]/)
      when :code
        return token unless identifier || reference_code?(token)

        @counts[:code] += 1
        scramble(token)
      else token
      end
    end

    def reference_code?(token)
      if token.match?(/\A\d+\z/)
        token.size >= (@strict ? 3 : 5)
      else
        token.size >= (@strict ? 4 : 6)
      end
    end

    def replaceable_word?(word)
      word.size > 1 && !keep_words.include?(word.upcase)
    end

    def keep_words
      @keep_words ||= begin
        words = BANK_WORDS + PROCESSOR_WORDS + REGION_WORDS
        words += CITY_WORDS + CATEGORY_WORDS unless @strict
        words.to_h { |word| [ word, true ] }
      end
    end

    # Replacement values

    def merchant_word_for(word)
      @counts[:word] += 1
      in_case_of(word, @merchant_words[word.upcase] ||= synthetic_word(@merchant_words.size))
    end

    def person_for(name)
      @counts[:person] += 1
      in_case_of(name, @people[name.upcase] ||= "TEST PERSON #{letters(@people.size).upcase}")
    end

    def email_for(email)
      @counts[:email] += 1
      fake = @emails[email.downcase] ||= "person.#{letters(@emails.size)}@example.com"
      email == email.upcase ? fake.upcase : fake
    end

    # Uses 555-01xx style numbers, which are reserved for fiction.
    def phone_for(phone)
      @counts[:phone] += 1
      digits = phone.delete("^0-9")
      index = @phones[digits] ||= @phones.size
      fake = "555555#{format("%04d", 100 + index % 9900)}"
      fake = "1#{fake}" if digits.size == 11
      fake_digits = fake.each_char
      phone.gsub(/\d/) { fake_digits.next }
    end

    # Pronounceable made-up words (FEBA, KIRO, ...), two syllables for the first 4,900.
    def synthetic_word(index)
      count = CONSONANTS.size * VOWELS.size
      number = (index * 1361 + 1000) % (count * count) + index / (count * count) * count * count
      syllables = []
      until number.zero? && syllables.size >= 2
        syllables << CONSONANTS[number % count / VOWELS.size] + VOWELS[number % VOWELS.size]
        number /= count
      end
      syllables.join
    end

    def letters(index)
      label = +""
      loop do
        label.prepend(("a".ord + index % 26).chr)
        index = index / 26 - 1
        break if index.negative?
      end
      label
    end

    def in_case_of(original, replacement)
      if original == original.upcase
        replacement.upcase
      elsif original == original.downcase
        replacement.downcase
      else
        replacement.split(" ").map(&:capitalize).join(" ")
      end
    end

    # Replaces each digit and letter with a pseudo-random one of the same kind, the same way every
    # time the token appears in this run.
    def scramble(token, keep: /[^\p{L}\d]/)
      @scrambled[[ token, keep ]] ||= begin
        bytes = random_bytes("scramble:#{token}", token.size)
        token.each_char.with_index.map do |char, index|
          byte = bytes[index]
          if char.match?(keep) then char
          elsif char.match?(/\d/) then (byte % 10).to_s
          elsif char.match?(/[[:upper:]]/) then ("A".ord + byte % 26).chr
          elsif char.match?(/[[:lower:]]/) then ("a".ord + byte % 26).chr
          else char
          end
        end.join
      end
    end

    def random_bytes(key, count)
      (0..count / 32).flat_map { |block| OpenSSL::HMAC.digest("SHA256", @secret, "#{key}:#{block}").bytes }
    end

    def random_integer(key)
      random_bytes(key, 8).first(8).inject(0) { |number, byte| number * 256 + byte }
    end

    # Balances

    def balance_column
      columns.find { |column| column.role == :balance }
    end

    # Rewrites running balances after randomizing amounts or offsetting balances. Each balance moves by
    # the total change in amounts so far, counting only rows whose balance follows from the previous one,
    # so files that were consistent stay consistent and quirks like overlapping duplicate rows survive.
    def rebalance(rows)
      return unless balance_column && (@randomize_amounts || @scrub_balances)

      flows = columns.select { |column| %i[debit credit amount].include?(column.role) }
      recalculate = @randomize_amounts && (flows.size == 1 || flows.map(&:role).sort == %i[credit debit])
      if @randomize_amounts && !recalculate
        @warnings << "balances were not recalculated: expected one signed amount column or a debit/credit pair"
      end

      order, sign, consistent = %i[oldest_first newest_first].product([ 1, -1 ]).map do |order, sign|
        [ order, sign, consistent_count(balance_steps(rows, flows, order, sign)) ]
      end.max_by(&:last)
      steps = balance_steps(rows, flows, order, sign)
      @balance_summary = "#{consistent} of #{[ steps.size - 1, 0 ].max} rows follow from the previous balance " \
        "(#{order.to_s.tr("_", " ")})"

      offset = 0
      steps.each_with_index do |step, index|
        offset += step[:change] if recalculate && consistent?(steps, index)
        updated = step[:balance] + offset + (@scrub_balances ? @balance_offset : 0)
        next if updated == step[:balance]

        @counts[:balance] += 1
        step[:values][balance_column.index] = around_whitespace(step[:text]) { |text| format_amount(text, updated) }
      end
    end

    # The rows that have a balance, in date order, each with the flows since the previous such row:
    # the original total, and the change (new minus original) after randomizing amounts.
    def balance_steps(rows, flows, order, sign)
      pending_flow = pending_change = 0
      (order == :oldest_first ? rows : rows.reverse).filter_map do |record, values|
        original_flow = sign * flow(record.map(&:value), flows)
        pending_flow += original_flow
        pending_change += sign * flow(values, flows) - original_flow

        text = record[balance_column.index]&.value.to_s
        balance = parse_amount(text.strip)
        next unless balance

        step = { text: text, values: values, balance: balance, flow: pending_flow, change: pending_change }
        pending_flow = pending_change = 0
        step
      end
    end

    def consistent?(steps, index)
      index.zero? || steps[index][:balance] == steps[index - 1][:balance] + steps[index][:flow]
    end

    def consistent_count(steps)
      (1...steps.size).count { |index| consistent?(steps, index) }
    end

    def flow(values, flows)
      flows.sum do |column|
        amount = parse_amount(values[column.index].to_s.strip) || 0
        column.role == :debit ? -amount : amount
      end
    end

    # Report helpers

    def quoting_summary
      quoted = data_records.flat_map { |record| record.each_index.select { |index| record[index].quoted } }.uniq.sort
      total = data_records.sum(&:size)
      if quoted.empty? then "none"
      elsif data_records.all? { |record| record.all?(&:quoted) } then "all (#{total} fields)"
      else "in columns #{quoted.map { |index| index + 1 }.join(", ")}"
      end
    end

    def column_label(column)
      name = column.name.empty? ? "" : "#{column.name.inspect} "
      case column.kind
      when :date
        "#{name}date (#{column.date_family.first}) - #{@shift_dates ? "shifted" : "kept"}"
      when :amount
        changed = column.role == :balance ? (@randomize_amounts || @scrub_balances) : @randomize_amounts
        "#{name}amount (#{column.role}) - #{changed ? "rewritten" : "kept"}"
      when :identifier then "#{name}identifier - all digits and names replaced"
      when :empty then "#{name}empty - kept"
      else "#{name}text - names, numbers, and contact details replaced"
      end
    end
end
