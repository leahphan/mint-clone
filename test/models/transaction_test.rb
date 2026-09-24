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
end
