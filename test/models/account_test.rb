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
end
