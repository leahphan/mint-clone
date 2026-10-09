require "test_helper"

class CsvSchemaTest < ActiveSupport::TestCase
  TD_CHEQUING = { date_column: 0, date_format: "%Y-%m-%d", description_column: 1, amount_strategy: "debit_credit",
    debit_column: 2, credit_column: 3, balance_column: 4 }.freeze

  test "parses the TD chequing export: debits out, credits in, balances, raw row" do
    transactions, failures = CsvSchema.new(TD_CHEQUING).parse(CsvTable.parse(file_fixture("td_chequing.csv").read))

    assert_empty failures
    assert_equal 71, transactions.size
    assert_equal BigDecimal("-981.80"), transactions.sum(&:amount)

    debit = transactions.first
    assert_equal [ Date.new(2026, 9, 9), "KAFU SEMO AND   _F", BigDecimal("-130"), BigDecimal("130"), nil, BigDecimal("2219.22") ],
      [ debit.date, debit.raw_description, debit.amount, debit.debit, debit.credit, debit.source_balance ]
    assert_equal [ "2026-09-09", "KAFU SEMO AND   _F", "130", "", "2219.22" ], debit.source_row

    deposit = transactions.find { |transaction| transaction.raw_description.start_with?("LAFA ATM DEP") }
    assert_equal [ BigDecimal("4000"), nil, BigDecimal("4000") ], [ deposit.amount, deposit.debit, deposit.credit ]
  end

  test "parses the TD Visa export: MM/DD/YYYY, purchases out, payments in" do
    schema = CsvSchema.new(TD_CHEQUING.merge(date_format: "%m/%d/%Y"))
    transactions, failures = schema.parse(CsvTable.parse(file_fixture("td_visa.csv").read))

    assert_empty failures
    assert_equal BigDecimal("1167.58"), transactions.sum(&:amount)
    purchase = transactions.find { |transaction| transaction.raw_description == "Semo.com" && transaction.debit == BigDecimal("35.58") }
    assert_equal [ Date.new(2026, 10, 4), BigDecimal("-35.58"), BigDecimal("1667.98") ], [ purchase.date, purchase.amount, purchase.source_balance ]
    payment = transactions.find { |transaction| transaction.credit == BigDecimal("1000") }
    assert_equal [ Date.new(2026, 9, 28), BigDecimal("1000") ], [ payment.date, payment.amount ]
  end

  test "a signed amount column follows negative_means" do
    table = CsvTable.parse("2026-09-01,Loblaws,-54.32\n2026-09-02,Payroll,2500.00\n")
    out = CsvSchema.new(date_column: 0, date_format: "%Y-%m-%d", description_column: 1, amount_strategy: "signed", amount_column: 2)
    inverted = CsvSchema.new(out.to_h.merge(negative_means: "money_in"))

    assert_equal [ BigDecimal("-54.32"), BigDecimal("2500") ], out.parse(table).first.map(&:amount)
    assert_equal [ BigDecimal("54.32"), BigDecimal("-2500") ], inverted.parse(table).first.map(&:amount)
  end

  test "parses money written with separators, currency symbols and parentheses" do
    {
      "1,234.56" => "1234.56", "-5" => "-5", "$20.00" => "20", "-$20.00" => "-20", "(5.00)" => "-5", "+3.1" => "3.1"
    }.each { |text, value| assert_equal BigDecimal(value), CsvSchema.parse_money(text), text }

    [ "12.345", "abc", "1,23.00", "12345678901.00", "", "5 USD" ].each { |text| assert_nil CsvSchema.parse_money(text), text }
  end

  test "parses dates strictly in the given format" do
    assert_equal Date.new(2026, 10, 4), CsvSchema.parse_date("10/04/2026", "%m/%d/%Y")
    assert_equal Date.new(2026, 4, 10), CsvSchema.parse_date("10/04/2026", "%d/%m/%Y")
    [ [ "2026-02-30", "%Y-%m-%d" ], [ "2026-09-01x", "%Y-%m-%d" ], [ "09/01/26", "%m/%d/%Y" ], [ "13/28/2026", "%m/%d/%Y" ] ].each do |value, format|
      assert_nil CsvSchema.parse_date(value, format), value
    end
    assert_equal [ "%m/%d/%Y", "%d/%m/%Y" ], CsvSchema.date_formats_for("03/04/2026")
  end

  test "reports each problem in a row with its line" do
    table = CsvTable.parse("2026-09-01,Loblaws,54.32,,100.00\nnope,,abc,,x\n2026-09-03,Both,1.00,2.00,101.00\n2026-09-04,Neither,,,101.00\n2026-09-05,Short\n")
    transactions, failures = CsvSchema.new(TD_CHEQUING).parse(table)

    assert_equal 1, transactions.size
    assert_equal [
      { line: 2, row: "nope,,abc,,x", messages: [ %(date "nope" isn't a date in YYYY-MM-DD format), "description is blank", %(debit "abc" isn't a number), %(balance "x" isn't a number) ] },
      { line: 3, row: "2026-09-03,Both,1.00,2.00,101.00", messages: [ "has both a debit and a credit" ] },
      { line: 4, row: "2026-09-04,Neither,,,101.00", messages: [ "debit and credit are both blank" ] },
      { line: 5, row: "2026-09-05,Short", messages: [ "expected 5 fields but found 2" ] }
    ], failures
  end

  test "validates the mapping" do
    assert CsvSchema.new(TD_CHEQUING).valid?
    assert_not CsvSchema.new(TD_CHEQUING.merge(date_format: "%d.%m.%Y")).valid?
    assert_not CsvSchema.new(TD_CHEQUING.merge(amount_strategy: "guess")).valid?
    assert_not CsvSchema.new(TD_CHEQUING.merge(credit_column: 2)).valid?, "the same column twice"
    assert_not CsvSchema.new(TD_CHEQUING.merge(debit_column: nil)).valid?
    assert_not CsvSchema.new(TD_CHEQUING.merge(amount_strategy: "signed")).valid?, "signed needs an amount column"
  end

  test "problems explains why a mapping can't be used for a file" do
    table = CsvTable.parse(file_fixture("td_chequing.csv").read)

    assert_empty CsvSchema.new(TD_CHEQUING).problems(table)
    assert_equal [ "The file only has 5 columns." ], CsvSchema.new(TD_CHEQUING.merge(balance_column: 5)).problems(table)
    assert_equal [ "None of the rows could be read with these columns." ], CsvSchema.new(TD_CHEQUING.merge(date_format: "%m/%d/%Y")).problems(table)
    amounts_as_descriptions = CsvSchema.new(date_column: 0, date_format: "%Y-%m-%d", description_column: 2, amount_strategy: "signed", amount_column: 3)
    assert_equal [ "Column 3 doesn't look like transaction descriptions." ],
      amounts_as_descriptions.problems(CsvTable.parse("2026-09-01,Coffee,1.00,5.00\n2026-09-02,Tea,2.00,3.00\n"))
  end

  test "round-trips through a hash for storage" do
    schema = CsvSchema.new(TD_CHEQUING)

    assert_equal schema.to_h, CsvSchema.from_h(schema.to_h.stringify_keys).to_h
    assert_equal "money_out", CsvSchema.from_h(date_column: 0).negative_means
  end
end
