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
    account = create(:account)
    category = create(:category, user: account.user)
    assert_equal category, create(:transaction, account: account, category: category).reload.category
  end

  test "its category and merchant must belong to the account's user" do
    account = create(:account)
    transaction = build(:transaction, account: account, category: create(:category), merchant: create(:merchant))

    assert_not transaction.valid?
    assert_includes transaction.errors[:category], "must be one of your categories"
    assert_includes transaction.errors[:merchant], "must be one of your merchants"

    transaction.category = create(:category, user: account.user)
    transaction.merchant = create(:merchant, user: account.user)
    assert transaction.valid?
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
      user = create(:user)
      account = create(:account, user: user)
      groceries = create(:category, user: user, name: "Groceries")
      dining = create(:category, user: user, name: "Dining")
      create(:transaction, account: account, category: groceries, transaction_date: Date.new(2026, 9, 1), amount: "-54.32")
      create(:transaction, account: account, category: groceries, transaction_date: Date.new(2026, 9, 30), amount: "-45.68")
      create(:transaction, account: account, category: dining, transaction_date: Date.new(2026, 9, 10), amount: "-30.00")
      create(:transaction, account: account, category: nil, transaction_date: Date.new(2026, 9, 12), amount: "-12.50")
      card_payment = create(:category, user: user, name: "Credit Card Payment", category_type: "transfer")
      create(:transaction, account: account, category: card_payment, transaction_date: Date.new(2026, 9, 20), amount: "-500.00") # transfer: not spending

      create(:transaction, account: account, category: groceries, transaction_date: Date.new(2026, 9, 15), amount: "20.00") # refund: not spending
      create(:transaction, account: account, category: groceries, transaction_date: Date.new(2026, 8, 31), amount: "-999.00") # last month
      create(:transaction, account: account, category: groceries, transaction_date: Date.new(2026, 10, 1), amount: "-999.00") # next month

      assert_equal [
        [ "Groceries", BigDecimal("100.00") ],
        [ "Dining", BigDecimal("30.00") ],
        [ "Uncategorized", BigDecimal("12.50") ]
      ], Transaction.spending_by_category(Date.current)
    end
  end

  test "a source fingerprint is unique within an account but not across accounts, and may be blank" do
    account = create(:account)
    create(:transaction, account: account, source_fingerprint: "abc")

    assert_raises(ActiveRecord::RecordNotUnique) { create(:transaction, account: account, source_fingerprint: "abc") }
    assert create(:transaction, account: create(:account, name: "Visa"), source_fingerprint: "abc").persisted?
    assert_difference("Transaction.count", 2) { 2.times { create(:transaction, account: account, source_fingerprint: nil) } }
  end
end
