require "test_helper"

class CsvSchemaDetectorTest < ActiveSupport::TestCase
  # Stands in for OllamaCsvSchemaDetector: returns a canned schema and counts calls.
  class FakeAi
    attr_reader :calls

    def initialize(schema = nil, &block)
      @schema = schema
      @block = block
      @calls = 0
    end

    def detect(_table, account_type:, profiles:)
      @calls += 1
      @block ? @block.call : @schema
    end
  end

  setup do
    @chequing = create(:account, account_type: "chequing")
    @visa = create(:account, name: "Visa", account_type: "credit_card")
  end

  test "recognizes the headerless TD chequing export and imports it automatically" do
    result = detect("td_chequing.csv", @chequing)

    assert_operator result.confidence, :>=, CsvSchemaDetector::AUTO_IMPORT
    assert_equal "heuristic", result.source
    assert_equal({ date_column: 0, date_format: "%Y-%m-%d", description_column: 1, amount_strategy: "debit_credit",
      debit_column: 2, credit_column: 3, balance_column: 4 }, result.schema.to_h)
  end

  test "recognizes the headerless TD Visa export: newest first, MM/DD/YYYY, balance owed" do
    result = detect("td_visa.csv", @visa)

    assert_operator result.confidence, :>=, CsvSchemaDetector::AUTO_IMPORT
    assert_equal [ "%m/%d/%Y", 2, 3, 4 ], result.schema.to_h.values_at(:date_format, :debit_column, :credit_column, :balance_column)
  end

  test "doesn't import a Visa export into a chequing account automatically, where its balances read backwards" do
    result = detect("td_visa.csv", @chequing)

    assert_operator result.confidence, :<, CsvSchemaDetector::AUTO_IMPORT
  end

  test "uses header names in any order and ignores extra columns" do
    result = detect("headed_reordered.csv", @chequing)

    assert_operator result.confidence, :>=, CsvSchemaDetector::AUTO_IMPORT
    assert_equal({ date_column: 1, date_format: "%Y-%m-%d", description_column: 0, amount_strategy: "debit_credit",
      debit_column: 3, credit_column: 4, balance_column: 5 }, result.schema.to_h)
  end

  test "imports a signed amount column for a bank account automatically, negative as money out" do
    result = detect("signed_amount.csv", @chequing)

    assert_operator result.confidence, :>=, CsvSchemaDetector::AUTO_IMPORT
    assert_equal [ "signed", 2, "money_out", nil ], result.schema.to_h.values_at(:amount_strategy, :amount_column, :negative_means, :balance_column)
  end

  test "detects a semicolon-delimited file" do
    result = CsvSchemaDetector.call(CsvTable.parse("Date;Description;Amount\n2026-09-01;Loblaws;-54.32\n2026-09-02;Payroll;2500.00\n"), account: @chequing, ai: nil)

    assert_operator result.confidence, :>=, CsvSchemaDetector::AUTO_IMPORT
    assert_equal 2, result.schema.amount_column
  end

  test "asks before importing a card's signed amounts without balances, preselecting the common sign as purchases" do
    result = detect("credit_card_signed.csv", @visa)

    assert result.confidence.between?(CsvSchemaDetector::RECOGNIZED, CsvSchemaDetector::AUTO_IMPORT - 0.01)
    assert_equal "money_in", result.schema.negative_means
  end

  test "asks before importing headerless debit and credit columns without balances" do
    result = detect("debit_credit_no_balance.csv", @chequing)

    assert result.confidence.between?(CsvSchemaDetector::RECOGNIZED, CsvSchemaDetector::AUTO_IMPORT - 0.01)
    assert_equal [ 2, 3 ], [ result.schema.debit_column, result.schema.credit_column ]
  end

  test "never decides ambiguous dates on its own, but preselects the reading that keeps rows in order" do
    result = CsvSchemaDetector.call(CsvTable.parse(ambiguous_visa_csv), account: @visa, ai: nil)

    assert_operator result.confidence, :<, CsvSchemaDetector::AUTO_IMPORT
    assert_equal "%m/%d/%Y", result.schema.date_format
  end

  test "returns no schema for a file it can't make sense of" do
    result = detect("unknown_format.csv", @chequing)

    assert_equal [ nil, 0, nil ], [ result.schema, result.confidence, result.source ]
  end

  test "reuses this account's previously imported layout without asking the AI, which settles ambiguous dates" do
    table = CsvTable.parse(ambiguous_visa_csv)
    schema = CsvSchema.new(date_column: 0, date_format: "%m/%d/%Y", description_column: 1, amount_strategy: "debit_credit", debit_column: 2, credit_column: 3, balance_column: 4)
    create(:import, account: @visa, format_fingerprint: table.fingerprint, schema: schema.to_h)
    ai = FakeAi.new { flunk "the AI shouldn't be asked about a known layout" }

    result = CsvSchemaDetector.call(table, account: @visa, ai: ai)

    assert_equal [ "known", CsvSchemaDetector::KNOWN, schema.to_h ], [ result.source, result.confidence, result.schema.to_h ]
  end

  test "doesn't reuse another account's layouts" do
    table = CsvTable.parse(ambiguous_visa_csv)
    create(:import, account: create(:account, name: "Other Visa", account_type: "credit_card"), format_fingerprint: table.fingerprint,
      schema: { date_column: 0, date_format: "%m/%d/%Y", description_column: 1, amount_strategy: "debit_credit", debit_column: 2, credit_column: 3, balance_column: 4 })

    assert_equal "heuristic", CsvSchemaDetector.call(table, account: @visa, ai: nil).source
  end

  test "ignores a remembered layout that doesn't fit the file" do
    table = CsvTable.parse(file_fixture("td_chequing.csv").read)
    create(:import, account: @chequing, format_fingerprint: table.fingerprint,
      schema: { date_column: 0, date_format: "%m/%d/%Y", description_column: 1, amount_strategy: "signed", amount_column: 4 })

    result = CsvSchemaDetector.call(table, account: @chequing, ai: nil)

    assert_equal [ "heuristic", "%Y-%m-%d" ], [ result.source, result.schema.date_format ]
  end

  test "only asks the AI when the heuristics aren't confident" do
    ai = FakeAi.new

    detect("td_chequing.csv", @chequing, ai: ai)
    assert_equal 0, ai.calls

    detect("credit_card_signed.csv", @visa, ai: ai)
    assert_equal 1, ai.calls
  end

  test "checks the AI's answer against the file: a mapping the balances contradict is rejected" do
    swapped = CsvSchema.new(date_column: 0, date_format: "%m/%d/%Y", description_column: 1, amount_strategy: "debit_credit", debit_column: 3, credit_column: 2, balance_column: 4)

    result = CsvSchemaDetector.call(CsvTable.parse(ambiguous_visa_csv), account: @visa, ai: FakeAi.new(swapped))

    assert_equal [ "heuristic", 2 ], [ result.source, result.schema.debit_column ]
  end

  test "rejects an AI answer that doesn't fit the file" do
    out_of_range = CsvSchema.new(date_column: 0, date_format: "%m/%d/%Y", description_column: 1, amount_strategy: "signed", amount_column: 9)

    assert_equal "heuristic", detect("credit_card_signed.csv", @visa, ai: FakeAi.new(out_of_range)).source
  end

  test "an AI answer that checks out improves the preselection but still needs confirming" do
    answer = CsvSchema.new(date_column: 0, date_format: "%m/%d/%Y", description_column: 1, amount_strategy: "signed", amount_column: 2, negative_means: "money_in")

    result = detect("credit_card_signed.csv", @visa, ai: FakeAi.new(answer))

    assert_equal [ "ai", CsvSchemaDetector::AI_CHOSEN ], [ result.source, result.confidence ]
  end

  test "falls back to the heuristics when the AI fails, logging only the error class" do
    ai = FakeAi.new { raise Errno::ECONNREFUSED }
    log = StringIO.new
    result = nil

    with_logger(log) { result = detect("credit_card_signed.csv", @visa, ai: ai) }

    assert_equal "heuristic", result.source
    assert_includes log.string, "AI schema detection failed (Errno::ECONNREFUSED)"
  end

  test "AI is off unless AI_CSV_SCHEMA_ENABLED is true" do
    assert_nil CsvSchemaDetector.default_ai
  end

  private
    def detect(name, account, ai: nil)
      CsvSchemaDetector.call(CsvTable.parse(file_fixture(name).read), account: account, ai: ai)
    end

    def with_logger(io)
      previous = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(io)
      yield
    ensure
      Rails.logger = previous
    end
end
