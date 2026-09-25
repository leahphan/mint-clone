require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "valid with a name and account type" do
    assert Account.new(name: "Savings", account_type: "savings").valid?
  end

  test "requires a name" do
    account = Account.new(account_type: "savings")
    assert_not account.valid?
    assert_includes account.errors[:name], "can't be blank"
  end

  test "requires a known account type" do
    assert_not Account.new(name: "Savings").valid?
    assert_not Account.new(name: "Savings", account_type: "brokerage").valid?
  end

  test "group_name puts chequing and savings under Cash and credit cards under Credit Cards" do
    assert_equal "Cash", build(:account, account_type: "chequing").group_name
    assert_equal "Cash", build(:account, account_type: "savings").group_name
    assert_equal "Credit Cards", build(:account, account_type: "credit_card").group_name
  end

  test "grouped returns groups in display order" do
    visa = create(:account, name: "Visa", account_type: "credit_card")
    chequing = create(:account, name: "Chequing", account_type: "chequing")
    savings = create(:account, name: "Savings", account_type: "savings")

    assert_equal [ [ "Cash", [ chequing, savings ] ], [ "Credit Cards", [ visa ] ] ], Account.grouped(Account.order(:name).to_a)
  end

  test "with_balances sums each account's transactions, including accounts with none" do
    chequing = create(:account, name: "Chequing")
    create(:transaction, account: chequing, amount: "2500.00")
    create(:transaction, account: chequing, amount: "-54.32")
    create(:account, name: "Empty")

    balances = Account.with_balances.order(:name).to_h { |account| [ account.name, account.balance ] }

    assert_equal({ "Chequing" => BigDecimal("2445.68"), "Empty" => BigDecimal("0") }, balances)
    assert_kind_of BigDecimal, balances["Empty"]
  end

  test "balance sums transactions when not loaded with_balances" do
    account = create(:account)
    create(:transaction, account: account, amount: "-10.25")
    create(:transaction, account: account, amount: "-0.75")

    assert_equal BigDecimal("-11.00"), Account.find(account.id).balance
  end

  test "opening_balance defaults to zero and must be a number" do
    assert_equal BigDecimal("0"), Account.new.opening_balance
    assert_not build(:account, opening_balance: "lots").valid?
    assert_not build(:account, opening_balance: nil).valid?
  end

  test "balance is the opening balance plus transactions, with and without with_balances" do
    create(:account, name: "Empty")
    create(:account, name: "Opening only", opening_balance: "1000.00")
    savings = create(:account, name: "Savings", account_type: "savings", opening_balance: "1000.00")
    create(:transaction, account: savings, amount: "-250.00")
    create(:transaction, account: savings, amount: "50.00")
    visa = create(:account, name: "Visa", account_type: "credit_card", opening_balance: "-500.00")
    create(:transaction, account: visa, amount: "-120.50")

    expected = {
      "Empty" => BigDecimal("0"),
      "Opening only" => BigDecimal("1000"),
      "Savings" => BigDecimal("800"),
      "Visa" => BigDecimal("-620.50")
    }
    assert_equal expected, Account.with_balances.order(:name).to_h { |account| [ account.name, account.balance ] }
    assert_equal expected, Account.order(:name).to_h { |account| [ account.name, account.balance ] }
  end

  test "cash? is true for chequing and savings only" do
    assert build(:account, account_type: "chequing").cash?
    assert build(:account, account_type: "savings").cash?
    assert_not build(:account, account_type: "credit_card").cash?
  end
end
