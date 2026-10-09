require "test_helper"

class ImportedTransactionTest < ActiveSupport::TestCase
  test "with a balance, the fingerprint ignores formatting, description and file" do
    a = build_imported(amount: "-20", balance: "100", description: "COFFEE   SHOP")
    b = build_imported(amount: "-20.00", balance: "100.0", description: "Coffee Shop #2")

    assert_equal ImportedTransaction.fingerprints([ a ], checksum: "file-a"), ImportedTransaction.fingerprints([ b ], checksum: "file-b")
  end

  test "with a balance, the same date and amount with a different balance is a different transaction" do
    first, second = ImportedTransaction.fingerprints([ build_imported(balance: "100"), build_imported(balance: "95.50") ], checksum: "file")

    assert_not_equal first, second
  end

  test "without a balance, the fingerprint only matches the same file" do
    row = build_imported(description: "COFFEE   shop")

    assert_equal ImportedTransaction.fingerprints([ row ], checksum: "file-a"), ImportedTransaction.fingerprints([ build_imported(description: "Coffee Shop") ], checksum: "file-a")
    assert_not_equal ImportedTransaction.fingerprints([ row ], checksum: "file-a"), ImportedTransaction.fingerprints([ row ], checksum: "file-b")
  end

  test "identical rows in one file get different fingerprints, whatever their order" do
    coffee = build_imported
    payroll = build_imported(amount: "2500", description: "Payroll")

    fingerprints = ImportedTransaction.fingerprints([ coffee, payroll, coffee ], checksum: "file")
    assert_equal 3, fingerprints.uniq.size
    assert_equal fingerprints.sort, ImportedTransaction.fingerprints([ coffee, coffee, payroll ], checksum: "file").sort
  end

  test "match_key ignores case, spacing and decimal formatting" do
    assert_equal build_imported(amount: "-5", description: "coffee  shop").match_key, ImportedTransaction.match_key(Date.new(2026, 10, 1), BigDecimal("-5.00"), "COFFEE SHOP")
  end

  private
    def build_imported(amount: "-4.50", balance: nil, description: "COFFEE SHOP")
      ImportedTransaction.new(line: 1, date: Date.new(2026, 10, 1), raw_description: description, amount: BigDecimal(amount),
        debit: nil, credit: nil, source_balance: balance && BigDecimal(balance), source_row: [])
    end
end
