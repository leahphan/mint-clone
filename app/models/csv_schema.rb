# Which columns of a bank's CSV export hold what, independent of the bank:
#
#   CsvSchema.new(date_column: 0, date_format: "%m/%d/%Y", description_column: 1,
#                 amount_strategy: "debit_credit", debit_column: 2, credit_column: 3, balance_column: 4)
#
# Debit is money out and credit money in, from the account holder's side. For a
# signed amount column, negative_means says which way negative numbers go.
# Parses every row into an ImportedTransaction with the app's sign convention:
# negative is money out.
class CsvSchema
  include ActiveModel::Model
  include ActiveModel::Attributes

  # Each format is checked against its pattern first: Date.strptime alone accepts "2026-09-01x".
  DATE_FORMATS = {
    "%Y-%m-%d" => /\A\d{4}-\d{1,2}-\d{1,2}\z/,
    "%Y/%m/%d" => %r{\A\d{4}/\d{1,2}/\d{1,2}\z},
    "%m/%d/%Y" => %r{\A\d{1,2}/\d{1,2}/\d{4}\z},
    "%d/%m/%Y" => %r{\A\d{1,2}/\d{1,2}/\d{4}\z}
  }.freeze
  DATE_FORMAT_LABELS = { "%Y-%m-%d" => "YYYY-MM-DD", "%Y/%m/%d" => "YYYY/MM/DD", "%m/%d/%Y" => "MM/DD/YYYY", "%d/%m/%Y" => "DD/MM/YYYY" }.freeze
  AMOUNT_STRATEGIES = %w[signed debit_credit].freeze
  NEGATIVE_MEANS = %w[money_out money_in].freeze
  COLUMNS = %i[date_column description_column amount_column debit_column credit_column balance_column].freeze
  ATTRIBUTES = %i[date_column date_format description_column amount_strategy amount_column negative_means debit_column credit_column balance_column].freeze

  # Digits with optional thousands separators and up to 2 decimals; at most 10 integer digits so it fits numeric(12, 2).
  MONEY = /\A(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{1,2})?\z/
  MAX_INTEGER_DIGITS = 10

  # Most rows must read cleanly for a mapping to be usable at all.
  MAX_FAILED_SHARE = 0.5

  attribute :date_column, :integer
  attribute :date_format, :string
  attribute :description_column, :integer
  attribute :amount_strategy, :string
  attribute :amount_column, :integer
  attribute :negative_means, :string, default: "money_out"
  attribute :debit_column, :integer
  attribute :credit_column, :integer
  attribute :balance_column, :integer

  validates :date_column, :description_column, presence: true
  validates :date_format, inclusion: { in: DATE_FORMATS.keys, message: "must be one of the supported date formats" }
  validates :amount_strategy, inclusion: { in: AMOUNT_STRATEGIES, message: "must be a signed amount or debit and credit columns" }
  validates :amount_column, presence: true, if: :signed?
  validates :negative_means, inclusion: { in: NEGATIVE_MEANS }, if: :signed?
  validates :debit_column, :credit_column, presence: true, if: :debit_credit?
  validate :columns_are_distinct

  def self.from_h(hash)
    new(hash.to_h.symbolize_keys.slice(*ATTRIBUTES))
  end

  # A Date, or nil unless the value is a real date written in the format.
  def self.parse_date(value, format)
    value = value.to_s.strip
    Date.strptime(value, format) if value.match?(DATE_FORMATS.fetch(format))
  rescue Date::Error
    nil
  end

  # The formats the value is a valid date in, e.g. ["%m/%d/%Y", "%d/%m/%Y"] for "03/04/2026".
  def self.date_formats_for(value)
    DATE_FORMATS.keys.select { |format| parse_date(value, format) }
  end

  # A BigDecimal for "1,234.56", "-5", "$20.00" or "(5.00)" (negative), or nil if it isn't money.
  def self.parse_money(value)
    text = value.to_s.strip
    negative = false
    if text.start_with?("(") && text.end_with?(")")
      negative = true
      text = text[1..-2].strip
    end
    if text.start_with?("-")
      negative = !negative
      text = text.delete_prefix("-").strip
    end
    text = text.delete_prefix("+").delete_prefix("$").strip
    return unless text.match?(MONEY) && text.split(".").first.delete(",").length <= MAX_INTEGER_DIGITS

    amount = BigDecimal(text.delete(","))
    negative ? -amount : amount
  end

  def self.blank_value?(value)
    value.nil? || value.strip.empty?
  end

  def signed?
    amount_strategy == "signed"
  end

  def debit_credit?
    amount_strategy == "debit_credit"
  end

  # The column indexes this schema reads.
  def used_columns
    columns = [ date_column, description_column, balance_column ]
    columns += signed? ? [ amount_column ] : [ debit_column, credit_column ]
    columns.compact
  end

  def to_h
    hash = attributes.symbolize_keys.slice(*ATTRIBUTES).compact
    signed? ? hash : hash.except(:negative_means)
  end

  # Why this schema can't be used to import the table, as user-facing sentences; empty when it can.
  # Pass parsed: (the result of #parse) to avoid parsing the table again.
  def problems(table, parsed: nil)
    return errors.full_messages unless valid?

    out_of_range = used_columns.reject { |column| column.between?(0, table.column_count - 1) }
    return [ "The file only has #{table.column_count} columns." ] if out_of_range.any?

    transactions, failures = parsed || parse(table)
    if transactions.empty?
      [ "None of the rows could be read with these columns." ]
    elsif failures.size > table.rows.size * MAX_FAILED_SHARE
      [ "#{failures.size} of #{table.rows.size} rows couldn't be read with these columns." ]
    elsif transactions.count { |transaction| transaction.raw_description.match?(/\p{L}/) } < transactions.size / 2
      [ "Column #{description_column + 1} doesn't look like transaction descriptions." ]
    else
      []
    end
  end

  # Parses every data row: [transactions, failures], where each failure is { line:, row:, messages: }.
  def parse(table)
    transactions = []
    failures = []

    table.rows.each do |row|
      messages = row_problems(row, table.column_count)
      if messages.any?
        failures << { line: row.line, row: row.text, messages: messages }
      else
        transactions << build_transaction(row)
      end
    end

    [ transactions, failures ]
  end

  private
    def columns_are_distinct
      errors.add(:base, "Each column can only be used once.") if used_columns.uniq.size != used_columns.size
    end

    def row_problems(row, column_count)
      return [ "expected #{column_count} fields but found #{row.fields.size}" ] if row.fields.size != column_count

      messages = []
      date = row.fields[date_column]
      messages << %(date "#{date.to_s.strip}" isn't a date in #{DATE_FORMAT_LABELS[date_format]} format) unless self.class.parse_date(date, date_format)
      messages << "description is blank" if self.class.blank_value?(row.fields[description_column])
      messages += amount_problems(row.fields)

      balance = row.fields[balance_column] if balance_column
      messages << %(balance "#{balance.strip}" isn't a number) if balance && !self.class.blank_value?(balance) && !self.class.parse_money(balance)
      messages
    end

    def amount_problems(fields)
      if signed?
        value = fields[amount_column]
        self.class.parse_money(value) ? [] : [ %(amount "#{value.to_s.strip}" isn't a number) ]
      else
        debit, credit = fields.values_at(debit_column, credit_column)
        return [ "debit and credit are both blank" ] if self.class.blank_value?(debit) && self.class.blank_value?(credit)

        messages = { "debit" => debit, "credit" => credit }.filter_map do |name, value|
          %(#{name} "#{value.strip}" isn't a number) unless self.class.blank_value?(value) || self.class.parse_money(value)
        end
        return messages if messages.any?

        [ debit, credit ].all? { |value| self.class.parse_money(value).to_d.nonzero? } ? [ "has both a debit and a credit" ] : []
      end
    end

    def build_transaction(row)
      fields = row.fields
      if signed?
        value = self.class.parse_money(fields[amount_column])
        amount = negative_means == "money_out" ? value : -value
        debit, credit = amount.negative? ? [ -amount, nil ] : [ nil, amount ]
      else
        debit = self.class.parse_money(fields[debit_column])&.abs
        credit = self.class.parse_money(fields[credit_column])&.abs
        amount = credit.to_d - debit.to_d
      end

      ImportedTransaction.new(
        line: row.line,
        date: self.class.parse_date(fields[date_column], date_format),
        raw_description: fields[description_column].strip,
        amount: amount,
        debit: debit,
        credit: credit,
        source_balance: (self.class.parse_money(fields[balance_column]) if balance_column),
        source_row: fields.map { |field| field.to_s }
      )
    end
end
