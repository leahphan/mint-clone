require "test_helper"

class TransactionTest < ActiveSupport::TestCase
  test "requires a date, description, and amount" do
    transaction = build(:transaction, transaction_date: nil, description: nil, amount: nil)
    assert_not transaction.valid?
    assert_includes transaction.errors[:transaction_date], "can't be blank"
    assert_includes transaction.errors[:description], "can't be blank"
    assert_includes transaction.errors[:amount], "can't be blank"
  end

  test "is valid without a category" do
    assert build(:transaction, category: nil).valid?
  end

  test "can belong to a category" do
    category = create(:category)
    assert_equal category, create(:transaction, category: category).reload.category
  end

  test "rejects a non-numeric amount" do
    transaction = build(:transaction, amount: "abc")
    assert_not transaction.valid?
    assert_includes transaction.errors[:amount], "is not a number"
  end

  test "stores amounts exactly as decimals" do
    account = create(:account)
    [ "0.10", "0.20", "-1234.56" ].each { |amount| create(:transaction, account: account, amount: amount) }

    amounts = account.transactions.reload.order(:id).map(&:amount)
    assert amounts.all? { |amount| amount.is_a?(BigDecimal) }
    assert_equal [ BigDecimal("0.10"), BigDecimal("0.20"), BigDecimal("-1234.56") ], amounts
    assert_equal BigDecimal("0.30"), account.transactions.where(amount: BigDecimal("0")..).sum(:amount)
  end

  test "newest_first orders by transaction date descending" do
    account = create(:account)
    older = create(:transaction, account: account, transaction_date: Date.new(2026, 9, 1))
    newer = create(:transaction, account: account, transaction_date: Date.new(2026, 9, 10))

    assert_equal [ newer, older ], account.transactions.newest_first.to_a
  end

  test "spending_by_category totals this month's money out per category, largest first" do
    travel_to Date.new(2026, 9, 25) do
      groceries = create(:category, name: "Groceries")
      dining = create(:category, name: "Dining")
      create(:transaction, category: groceries, transaction_date: Date.new(2026, 9, 1), amount: "-54.32")
      create(:transaction, category: groceries, transaction_date: Date.new(2026, 9, 30), amount: "-45.68")
      create(:transaction, category: dining, transaction_date: Date.new(2026, 9, 10), amount: "-30.00")
      create(:transaction, category: nil, transaction_date: Date.new(2026, 9, 12), amount: "-12.50")

      create(:transaction, category: groceries, transaction_date: Date.new(2026, 9, 15), amount: "20.00") # refund: not spending
      create(:transaction, category: groceries, transaction_date: Date.new(2026, 8, 31), amount: "-999.00") # last month
      create(:transaction, category: groceries, transaction_date: Date.new(2026, 10, 1), amount: "-999.00") # next month

      assert_equal [
        [ "Groceries", BigDecimal("100.00") ],
        [ "Dining", BigDecimal("30.00") ],
        [ "Uncategorized", BigDecimal("12.50") ]
      ], Transaction.spending_by_category(Date.current)
    end
  end
end
