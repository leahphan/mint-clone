# Asks an Ollama Cloud model which columns of a CSV export hold what, when
# CsvSchemaDetector's heuristics aren't sure. The model never sees the file's
# contents: only the column count, the account type, header names made of
# ordinary banking words, per-column statistics, and sample rows in which every
# cell is replaced by its kind, e.g. ["DATE(%m/%d/%Y)", "TEXT", "MONEY(+)", "BLANK"].
#
# Returns a CsvSchema built only from in-range column indexes and allowed values,
# or nil. CsvSchemaDetector then checks it against the file like any other schema.
class OllamaCsvSchemaDetector
  SAMPLE_ROWS = 10
  MAX_HEADER_WORDS = 4
  REDACTED = "[redacted]"

  # Header names are only sent when every word is one of these; anything else
  # (an account number, a person's name) is replaced with REDACTED.
  HEADER_WORDS = %w[
    1 2 3 account amount amounts balance cad card category check cheque closing code credit credits currency date debit debits
    deposit deposits description details id in memo merchant money name narrative no notes number out paid payee post posted
    posting ref reference running status time trans transaction type usd value withdrawal withdrawals
  ].to_set.freeze

  SYSTEM_PROMPT = <<~PROMPT
    You identify the columns of a bank account or credit card transaction export (CSV). You are not shown the data, only its structure: per-column statistics and sample rows where each cell is replaced by its kind: DATE(formats it fits), MONEY(+) or MONEY(-) for a positive or negative amount, TEXT, BLANK or OTHER. Header names are given when there is a header row; "#{REDACTED}" hides a name.
    Answer with 0-based column indexes:
    - date_column: the transaction date; date_format: the format of that column, from the formats it fits.
    - description_column: the transaction description.
    - amount_strategy: "signed" when one column holds both positive and negative amounts; "debit_credit" when one column holds money out and another money in, with the other one blank on each row.
    - For "signed": amount_column, and negative_means: "money_out" if negative amounts are money leaving the account holder, else "money_in". Otherwise null for both.
    - For "debit_credit": debit_column (money out of the account holder's pocket: purchases, withdrawals) and credit_column (money in: deposits, refunds, card payments). Otherwise null for both.
    - balance_column: the running balance, or null if there isn't one.
    Use each column at most once.
  PROMPT

  def initialize(client: OllamaClient.new(log_as: "OllamaCsvSchemaDetector"))
    @client = client
  end

  # profiles: CsvSchemaDetector::Profile for each column.
  def detect(table, account_type:, profiles:)
    answer = client.chat(system: SYSTEM_PROMPT, content: description(table, account_type, profiles).to_json, schema: response_schema(table.column_count))
    schema_from(answer, table.column_count)
  end

  # What the model is told about the file: its structure, never its values.
  def description(table, account_type, profiles)
    {
      column_count: table.column_count,
      account_type: account_type,
      header: table.header&.map { |name| redact_header(name) },
      columns: profiles.map do |profile|
        { index: profile.column, filled: profile.fill.round(2), date_formats: profile.date_formats, money: profile.money,
          text: profile.text, has_negative_amounts: profile.negatives.positive?, distinct_values: profile.distinct.round(2) }
      end,
      sample_rows: sample_rows(table).map { |row| row.fields.map { |value| kind(value) } }
    }
  end

  private
    attr_reader :client

    def redact_header(name)
      words = CsvTable.normalize_header(name).split
      words.any? && words.size <= MAX_HEADER_WORDS && words.all? { |word| HEADER_WORDS.include?(word) } ? words.join(" ") : REDACTED
    end

    def kind(value)
      return "BLANK" if CsvSchema.blank_value?(value)

      formats = CsvSchema.date_formats_for(value)
      return "DATE(#{formats.join("|")})" if formats.any?

      amount = CsvSchema.parse_money(value)
      return amount.negative? ? "MONEY(-)" : "MONEY(+)" if amount

      value.match?(/\p{L}/) ? "TEXT" : "OTHER"
    end

    # Up to SAMPLE_ROWS rows, including one with a value in each column if there is one.
    def sample_rows(table)
      with_each_column = (0...table.column_count).filter_map do |column|
        table.rows.find { |row| !CsvSchema.blank_value?(row.fields[column]) }
      end
      (with_each_column + table.rows.first(SAMPLE_ROWS)).uniq.first(SAMPLE_ROWS).sort_by(&:line)
    end

    def response_schema(column_count)
      index = { type: "integer", minimum: 0, maximum: column_count - 1 }
      optional_index = { type: [ "integer", "null" ], minimum: 0, maximum: column_count - 1 }
      {
        type: "object",
        properties: {
          date_column: index,
          date_format: { type: "string", enum: CsvSchema::DATE_FORMATS.keys },
          description_column: index,
          amount_strategy: { type: "string", enum: CsvSchema::AMOUNT_STRATEGIES },
          amount_column: optional_index,
          negative_means: { type: [ "string", "null" ], enum: [ *CsvSchema::NEGATIVE_MEANS, nil ] },
          debit_column: optional_index,
          credit_column: optional_index,
          balance_column: optional_index
        },
        required: CsvSchema::ATTRIBUTES.map(&:to_s)
      }
    end

    # Accepts only integer indexes within the file and the allowed values; anything else rejects the whole answer.
    def schema_from(answer, column_count)
      return unless answer.is_a?(Hash)

      columns = CsvSchema::COLUMNS.index_with { |column| answer[column.to_s] }
      return unless columns.values.all? { |index| index.nil? || (index.is_a?(Integer) && index.between?(0, column_count - 1)) }

      date_format, amount_strategy, negative_means = answer.values_at("date_format", "amount_strategy", "negative_means")
      return unless CsvSchema::DATE_FORMATS.key?(date_format) && CsvSchema::AMOUNT_STRATEGIES.include?(amount_strategy)
      return unless negative_means.nil? || CsvSchema::NEGATIVE_MEANS.include?(negative_means)

      schema = CsvSchema.new(**columns, date_format: date_format, amount_strategy: amount_strategy, negative_means: negative_means || "money_out")
      schema if schema.valid?
    end
end
