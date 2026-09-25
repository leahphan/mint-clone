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

    assert_equal [ [ "Cash", [ chequing, savings ] ], [ "Credit Cards", [ visa ] ] ], Account.order(:name).grouped
  end
end
