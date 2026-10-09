require "test_helper"

class OllamaCsvSchemaDetectorTest < ActiveSupport::TestCase
  # Stands in for OllamaClient: records the request and returns a canned answer.
  class FakeClient
    attr_reader :requests

    def initialize(answer)
      @answer = answer
      @requests = []
    end

    def chat(system:, content:, schema:)
      requests << { system: system, content: JSON.parse(content), schema: schema }
      @answer
    end
  end

  VISA_ANSWER = { "date_column" => 0, "date_format" => "%m/%d/%Y", "description_column" => 1, "amount_strategy" => "debit_credit",
    "amount_column" => nil, "negative_means" => nil, "debit_column" => 2, "credit_column" => 3, "balance_column" => 4 }.freeze

  setup do
    @table = CsvTable.parse(ambiguous_visa_csv)
  end

  test "sends the file's structure and returns the schema from a valid answer" do
    client = FakeClient.new(VISA_ANSWER)

    schema = detect(client)

    assert_equal({ date_column: 0, date_format: "%m/%d/%Y", description_column: 1, amount_strategy: "debit_credit",
      debit_column: 2, credit_column: 3, balance_column: 4 }, schema.to_h)
    request = client.requests.sole
    assert_equal [ 5, "credit_card", nil ], request[:content].values_at("column_count", "account_type", "header")
    assert_equal [ "DATE(%m/%d/%Y|%d/%m/%Y)", "TEXT", "MONEY(+)", "BLANK", "MONEY(+)" ], request[:content]["sample_rows"].first
    assert_equal 4, request[:schema].dig(:properties, :balance_column, :maximum)
  end

  test "never sends descriptions, amounts, balances or dates from the file" do
    client = FakeClient.new(VISA_ANSWER)
    detect(client)

    sent = client.requests.sole[:content].to_json
    @table.rows.flat_map(&:fields).compact.reject(&:empty?).each do |value|
      assert_not_includes sent, value, "sent a value from the file"
    end
    assert_operator client.requests.sole[:content]["sample_rows"].size, :<=, OllamaCsvSchemaDetector::SAMPLE_ROWS
  end

  test "sends ordinary header names but redacts ones that could identify the account holder" do
    table = CsvTable.parse("Transaction Date,Description,Acct 4512 0000 1234,Leah Phan,Amount (CAD)\n2026-09-01,Loblaws,x,y,-54.32\n")
    client = FakeClient.new(nil)

    OllamaCsvSchemaDetector.new(client: client).detect(table, account_type: "chequing", profiles: profiles(table))

    assert_equal [ "transaction date", "description", "[redacted]", "[redacted]", "amount" ], client.requests.sole[:content]["header"]
  end

  {
    "not a JSON object" => [ "nope" ],
    "a column outside the file" => VISA_ANSWER.merge("balance_column" => 5),
    "a column given as text" => VISA_ANSWER.merge("debit_column" => "2"),
    "a negative column" => VISA_ANSWER.merge("credit_column" => -1),
    "an unknown date format" => VISA_ANSWER.merge("date_format" => "%d.%m.%Y"),
    "an unknown amount strategy" => VISA_ANSWER.merge("amount_strategy" => "split"),
    "an unknown sign" => VISA_ANSWER.merge("negative_means" => "sometimes"),
    "the same column twice" => VISA_ANSWER.merge("credit_column" => 2),
    "a debit/credit answer without a credit column" => VISA_ANSWER.merge("credit_column" => nil)
  }.each do |problem, answer|
    test "rejects an answer with #{problem}" do
      assert_nil detect(FakeClient.new(answer))
    end
  end

  test "returns nil when Ollama is unavailable" do
    assert_nil detect(FakeClient.new(nil))
  end

  private
    def detect(client)
      OllamaCsvSchemaDetector.new(client: client).detect(@table, account_type: "credit_card", profiles: profiles(@table))
    end

    def profiles(table)
      CsvSchemaDetector.new(table, Account.new(account_type: "credit_card")).profiles
    end
end
