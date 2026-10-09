# Works out which columns of an uploaded CSV hold what, once per file:
#
# 1. A layout this account imported before (same CsvTable#fingerprint) is reused.
# 2. Otherwise candidate schemas are built from header names and the shape of
#    each column's values, and the best-scoring one wins.
# 3. If that isn't confident enough and AI is enabled, the AI is asked using
#    only a redacted description of the file (OllamaCsvSchemaDetector), and its
#    answer is scored the same way.
#
# Confidence is the lowest of the levels below, one per decision (date column,
# date format, description, amount columns, direction). The importer imports
# automatically at AUTO_IMPORT and above; otherwise the user confirms the columns.
class CsvSchemaDetector
  AUTO_IMPORT = 0.9
  RECOGNIZED = 0.6

  KNOWN = 0.95
  VERIFIED = 0.97     # checked on every row, e.g. the running balances add up in file order
  UNIQUE = 0.95       # the only column that could be it
  HEADER = 0.92       # the header says so, the only structure that fits, or the sign convention for bank accounts
  SUPPORTED = 0.89    # the balances agree only when rows are matched out of order: never enough on its own
  AI_CHOSEN = 0.8
  PRIOR = 0.75
  WEAK = 0.6
  GUESS = 0.5
  CONTRADICTED = 0.1

  SUSPECT = 0.85          # more than SUSPECT_FAILED_SHARE of rows can't be read
  SUSPECT_FAILED_SHARE = 0.1
  MOSTLY = 0.9            # share of values that must agree for a column to count as dates, money or text
  DENSE = 0.95            # fill rate of a column that has a value on (nearly) every row
  RECONCILED = 0.9
  MAX_CANDIDATES = 50

  # Normalized header names (see CsvTable.normalize_header) for each role, most specific first.
  HEADER_SYNONYMS = {
    date: [ "transaction date", "date", "trans date", "date posted", "posted date", "posting date", "post date", "value date" ],
    description: [ "description", "transaction description", "description 1", "details", "transaction details", "merchant",
      "merchant name", "payee", "name", "memo", "narrative" ],
    debit: [ "debit", "debits", "debit amount", "withdrawal", "withdrawals", "withdrawal amount", "money out", "paid out" ],
    credit: [ "credit", "credits", "credit amount", "deposit", "deposits", "deposit amount", "money in", "paid in" ],
    amount: [ "amount", "transaction amount", "cad", "amount cad", "cad amount" ],
    balance: [ "balance", "running balance", "account balance", "closing balance" ]
  }.freeze

  Result = Data.define(:schema, :confidence, :source)
  Profile = Data.define(:column, :fill, :date_formats, :money, :dense_money, :text, :negatives, :distinct)

  def self.call(table, account:, ai: default_ai)
    new(table, account).call(ai)
  end

  def self.default_ai
    OllamaCsvSchemaDetector.new if ENV["AI_CSV_SCHEMA_ENABLED"] == "true"
  end

  def initialize(table, account)
    @table = table
    @account = account
  end

  def call(ai = nil)
    known_result || detected_result(ai)
  end

  # The confidence in a schema for this file, or nil if it can't be used at all.
  # A contradicted schema (e.g. the balances show money in and out are swapped) scores CONTRADICTED.
  def confidence(schema, chosen_by_ai: false)
    transactions, failures = usable_parse(schema)
    return unless transactions

    levels = [
      date_column_level(schema), date_format_level(schema), description_level(schema),
      amount_columns_level(schema, transactions), direction_level(schema, transactions)
    ]
    levels.map! { |level| level.between?(CONTRADICTED + 0.01, AI_CHOSEN) ? AI_CHOSEN : level } if chosen_by_ai
    suspect?(failures) ? [ levels.min, SUSPECT ].min : levels.min
  end

  # Why the balances contradict this schema, or nil.
  def contradiction(schema)
    transactions, = usable_parse(schema)
    "The running balances show money in and money out the other way round." if transactions && direction_level(schema, transactions) == CONTRADICTED
  end

  def profiles
    @profiles ||= (0...table.column_count).map { |column| profile(column) }
  end

  private
    attr_reader :table, :account

    # A layout this account imported before settles what the heuristics can't (e.g. ambiguous dates),
    # as long as it still reads the file and the balances don't contradict it.
    def known_result
      previous = account.imports.completed.where(format_fingerprint: table.fingerprint).where.not(schema: nil).order(created_at: :desc).first
      return unless previous

      schema = CsvSchema.from_h(previous.schema)
      transactions, failures = usable_parse(schema)
      return if transactions.nil? || direction_level(schema, transactions) == CONTRADICTED

      Result.new(schema, suspect?(failures) ? SUSPECT : KNOWN, "known")
    end

    # [transactions, failures] when the schema can read this file, otherwise nil.
    def usable_parse(schema)
      return unless schema.valid? && schema.used_columns.all? { |column| column < table.column_count }

      parsed = schema.parse(table)
      parsed if schema.problems(table, parsed: parsed).empty?
    end

    def suspect?(failures)
      failures.size > table.rows.size * SUSPECT_FAILED_SHARE
    end

    def detected_result(ai)
      scored = candidates.filter_map do |schema|
        score = confidence(schema)
        Result.new(schema, score, "heuristic") if score
      end
      best = scored.max_by.with_index { |result, index| [ result.confidence, -index ] }
      return best if best && best.confidence >= AUTO_IMPORT

      ai_result = ask_ai(ai)
      [ best, ai_result ].compact.max_by(&:confidence) || Result.new(nil, 0, nil)
    end

    def ask_ai(ai)
      return unless ai

      schema = ai.detect(table, account_type: account.account_type, profiles: profiles)
      score = schema && confidence(schema, chosen_by_ai: true)
      Result.new(schema, score, "ai") if score && score > CONTRADICTED
    rescue StandardError => error
      Rails.logger.warn("CsvSchemaDetector: AI schema detection failed (#{error.class})")
      nil
    end

    # Candidate schemas, most trusted first: from the header, then debit/credit pairs, then signed amounts.
    def candidates
      date_column = header_role(:date) || date_like_columns.first
      description_column = header_role(:description) || text_columns.max_by { |column| profiles[column].distinct }
      return [] unless date_column && description_column

      base = { date_column: date_column, date_format: likely_date_format(date_column), description_column: description_column }
      schemas = [ header_candidate(base), *pair_candidates(base), *signed_candidates(base) ].compact
      schemas.uniq(&:to_h).first(MAX_CANDIDATES)
    end

    def header_candidate(base)
      balance = header_role(:balance)
      if header_role(:debit) && header_role(:credit)
        CsvSchema.new(**base, amount_strategy: "debit_credit", debit_column: header_role(:debit), credit_column: header_role(:credit), balance_column: balance)
      elsif header_role(:amount)
        CsvSchema.new(**base, amount_strategy: "signed", amount_column: header_role(:amount), balance_column: balance)
      end
    end

    def pair_candidates(base)
      exclusive_pairs.flat_map do |pair|
        balance = single(dense_money_columns - pair - base.values)
        pair.permutation.map { |debit, credit| CsvSchema.new(**base, amount_strategy: "debit_credit", debit_column: debit, credit_column: credit, balance_column: balance) }
      end
    end

    def signed_candidates(base)
      dense_money_columns.flat_map do |amount|
        balance = single(dense_money_columns - [ amount ])
        CsvSchema::NEGATIVE_MEANS.map do |negative_means|
          CsvSchema.new(**base, amount_strategy: "signed", amount_column: amount, negative_means: negative_means, balance_column: balance)
        end
      end
    end

    # --- Levels for each decision ---

    def date_column_level(schema)
      return HEADER if header_role(:date) == schema.date_column

      level_for(date_like_columns, schema.date_column)
    end

    def date_format_level(schema)
      formats = profiles[schema.date_column].date_formats
      return GUESS unless formats.include?(schema.date_format)
      return VERIFIED if formats == [ schema.date_format ]

      # Both MM/DD and DD/MM fit every date. Row order can hint, but never decides.
      monotonic_formats(schema.date_column) == [ schema.date_format ] ? PRIOR : GUESS
    end

    def description_level(schema)
      return HEADER if header_role(:description) == schema.description_column

      level_for(text_columns, schema.description_column)
    end

    def amount_columns_level(schema, transactions)
      return VERIFIED if schema.balance_column && [ 1, -1 ].filter_map { |sign| sequential_ratio(transactions, sign) }.max.to_f >= RECONCILED
      return HEADER if header_amounts?(schema)

      # Without balances or headers, only an unambiguous structure is trusted: a single debit/credit pair or a single amount column.
      exclusive_pairs.size + dense_money_columns.size == 1 ? HEADER : GUESS
    end

    def direction_level(schema, transactions)
      base = direction_prior(schema, transactions)
      return base if base == CONTRADICTED

      level = balance_direction_level(transactions, base)
      level = PRIOR if level >= AUTO_IMPORT && transactions.count { |t| t.amount.positive? } > transactions.count { |t| t.amount.negative? }
      level
    end

    # Running balances can confirm or contradict which way the amounts go. Sequential matching in file
    # order verifies; matching out of order only supports, because balances can repeat by coincidence.
    def balance_direction_level(transactions, base)
      view = balance_view(transactions)
      return base unless view

      matched, flipped = sequential_ratio(transactions, view), sequential_ratio(transactions, -view)
      return VERIFIED if matched.to_f >= RECONCILED && flipped.to_f < 0.5
      return CONTRADICTED if flipped.to_f >= RECONCILED && matched.to_f < 0.5

      matched, flipped = order_free_ratio(transactions, view), order_free_ratio(transactions, -view)
      return [ base, SUPPORTED ].max if matched.to_f >= DENSE && flipped.to_f < 0.5
      return CONTRADICTED if flipped.to_f >= DENSE && matched.to_f < 0.5

      base
    end

    def direction_prior(schema, transactions)
      if schema.debit_credit?
        return HEADER if header_role(:debit) == schema.debit_column && header_role(:credit) == schema.credit_column
        return CONTRADICTED if header_role(:debit) == schema.credit_column && header_role(:credit) == schema.debit_column

        # Money usually goes out more often than it comes in.
        transactions.count(&:debit) > transactions.count(&:credit) ? WEAK : GUESS
      elsif account.cash?
        schema.negative_means == "money_out" ? HEADER : GUESS
      else
        # Card exports differ: the more common sign is probably purchases.
        negatives = transactions.count { |t| t.amount.negative? }
        negatives > transactions.size - negatives ? PRIOR : GUESS
      end
    end

    # +1 when balances move with the holder's money (bank accounts, cards shown as negative),
    # -1 when they show the amount owed (most card exports), nil when it's unclear.
    def balance_view(transactions)
      return 1 if account.cash?

      balances = transactions.filter_map(&:source_balance).reject(&:zero?)
      return if balances.empty?

      positive_share = balances.count(&:positive?).fdiv(balances.size)
      if positive_share >= MOSTLY then -1
      elsif positive_share <= 1 - MOSTLY then 1
      end
    end

    # Share of consecutive rows whose balances step by their amounts, in file order (oldest or newest first).
    def sequential_ratio(transactions, sign)
      rows = transactions.select(&:source_balance)
      return if rows.size < 4

      file_orders(rows).map do |order|
        rows.each_cons(2).count do |previous, current|
          if order == :ascending
            current.source_balance == previous.source_balance + sign * current.amount
          else
            previous.source_balance == current.source_balance + sign * previous.amount
          end
        end.fdiv(rows.size - 1)
      end.max
    end

    # Share of rows whose previous balance appears somewhere in the file. Only meaningful when balances rarely repeat.
    def order_free_ratio(transactions, sign)
      rows = transactions.select(&:source_balance)
      balances = rows.map(&:source_balance)
      return if rows.size < 4 || balances.uniq.size < balances.size * MOSTLY

      present = balances.to_set
      [ rows.count { |row| row.amount.nonzero? && present.include?(row.source_balance - sign * row.amount) }.fdiv(rows.size - 1), 1.0 ].min
    end

    def file_orders(rows)
      dates = rows.map(&:date)
      orders = []
      orders << :ascending if dates.each_cons(2).all? { |a, b| a <= b }
      orders << :descending if dates.each_cons(2).all? { |a, b| a >= b }
      orders
    end

    # --- Columns ---

    def profile(column)
      values = table.values(column)
      present = values.reject { |value| CsvSchema.blank_value?(value) }
      dates = present.select { |value| CsvSchema.date_formats_for(value).any? }
      amounts = present.filter_map { |value| CsvSchema.parse_money(value) }
      fill = present.size.fdiv([ values.size, 1 ].max)

      Profile.new(
        column: column,
        fill: fill,
        date_formats: mostly?(dates, present) ? CsvSchema::DATE_FORMATS.keys.select { |format| dates.all? { |value| CsvSchema.parse_date(value, format) } } : [],
        money: present.empty? || mostly?(amounts, present),
        dense_money: fill >= DENSE && mostly?(amounts, present),
        text: present.any? && mostly?(present.select { |value| value.match?(/\p{L}/) && !CsvSchema.parse_money(value) }, present),
        negatives: amounts.count(&:negative?),
        distinct: present.uniq.size.fdiv([ present.size, 1 ].max)
      )
    end

    def mostly?(matching, all)
      all.any? && matching.size >= all.size * MOSTLY
    end

    def date_like_columns
      @date_like_columns ||= profiles.select { |profile| profile.date_formats.any? && profile.fill >= MOSTLY }.map(&:column)
    end

    def text_columns
      @text_columns ||= profiles.select { |profile| profile.text && profile.fill >= MOSTLY }.map(&:column) - date_like_columns
    end

    def money_columns
      @money_columns ||= profiles.select(&:money).map(&:column) - date_like_columns - text_columns
    end

    def dense_money_columns
      @dense_money_columns ||= profiles.select(&:dense_money).map(&:column) - date_like_columns - text_columns
    end

    # Pairs of money columns that are never both filled in, have no negative values, and together cover nearly every row.
    def exclusive_pairs
      @exclusive_pairs ||= money_columns.combination(2).select do |pair|
        next false if pair.any? { |column| profiles[column].negatives.positive? }

        cells = table.rows.map { |row| pair.map { |column| CsvSchema.parse_money(row.fields[column]).to_d.nonzero? } }
        cells.none?(&:all?) && cells.count(&:any?) >= table.rows.size * DENSE
      end
    end

    def likely_date_format(column)
      formats = profiles[column].date_formats
      return formats.first if formats.size <= 1

      single(monotonic_formats(column) & formats) || (formats.include?("%m/%d/%Y") ? "%m/%d/%Y" : formats.first)
    end

    def monotonic_formats(column)
      profiles[column].date_formats.select do |format|
        dates = table.values(column).filter_map { |value| CsvSchema.parse_date(value, format) }
        dates.each_cons(2).all? { |a, b| a <= b } || dates.each_cons(2).all? { |a, b| a >= b }
      end
    end

    def header_amounts?(schema)
      if schema.signed?
        header_role(:amount) == schema.amount_column
      else
        [ header_role(:debit), header_role(:credit) ].sort == [ schema.debit_column, schema.credit_column ].sort
      end
    end

    # The column whose header names this role, if the header has one.
    def header_role(role)
      return unless table.header?

      @header_roles ||= {}
      return @header_roles[role] if @header_roles.key?(role)

      @header_roles[role] = HEADER_SYNONYMS.fetch(role).lazy.filter_map { |name| table.normalized_header.index(name) }.first
    end

    def level_for(columns, column)
      if columns == [ column ] then UNIQUE
      elsif columns.include?(column) then WEAK
      else GUESS
      end
    end

    def single(values)
      values.first if values.size == 1
    end
end
