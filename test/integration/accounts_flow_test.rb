require "test_helper"

class AccountsFlowTest < ActionDispatch::IntegrationTest
  test "lists accounts" do
    create(:account, name: "Everyday Chequing")
    create(:account, name: "Visa", account_type: "credit_card")

    get root_path
    assert_response :success
    assert_select "a", text: "Everyday Chequing"
    assert_select "a", text: "Visa"
  end

  test "creates an account" do
    assert_difference "Account.count", 1 do
      post accounts_path, params: { account: { name: "Rainy Day", account_type: "savings" } }
    end

    account = Account.last
    assert_redirected_to account_path(account)
    assert account.savings?
  end

  test "re-renders the form when an account is invalid" do
    assert_no_difference "Account.count" do
      post accounts_path, params: { account: { name: "", account_type: "savings" } }
    end
    assert_response :unprocessable_entity
  end

  test "adds a transaction to an account" do
    account = create(:account)

    assert_difference "account.transactions.count", 1 do
      post account_transactions_path(account), params: {
        transaction: { transaction_date: "2026-09-15", description: "Rent", amount: "-1500.00" }
      }
    end

    assert_redirected_to account_path(account)
    assert_equal BigDecimal("-1500.00"), account.transactions.find_by!(description: "Rent").amount
  end

  test "re-renders the form when a transaction is invalid" do
    account = create(:account)

    assert_no_difference "Transaction.count" do
      post account_transactions_path(account), params: {
        transaction: { transaction_date: "", description: "", amount: "" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "shows an account's transactions newest first" do
    account = create(:account)
    create(:transaction, account: account, transaction_date: Date.new(2026, 9, 1), description: "Paycheque", amount: "2500.00")
    create(:transaction, account: account, transaction_date: Date.new(2026, 9, 10), description: "Groceries", amount: "-84.37")

    get account_path(account)
    assert_response :success
    assert_equal [ "Groceries", "Paycheque" ], css_select("tbody tr td:nth-child(2)").map(&:text)
    assert_select "td", text: "-$84.37"
  end
end
