require "test_helper"

class AccountsFlowTest < ActionDispatch::IntegrationTest
  test "lists accounts" do
    create(:account, name: "Everyday Chequing")
    create(:account, name: "Visa", account_type: "credit_card")

    get accounts_path
    assert_response :success
    assert_select "a", text: "Everyday Chequing"
    assert_select "a", text: "Visa"
  end

  test "shows each account's balance, including its opening balance, and a subtotal per group" do
    chequing = create(:account, name: "Everyday Chequing")
    create(:transaction, account: chequing, amount: "1000.00")
    create(:transaction, account: chequing, amount: "-250.00")
    create(:account, name: "Rainy Day", account_type: "savings", opening_balance: "200.00")
    visa = create(:account, name: "Visa", account_type: "credit_card", opening_balance: "-300.00")
    create(:transaction, account: visa, amount: "-120.50")

    get accounts_path

    assert_select "tr", text: /Everyday Chequing.*\$750\.00/m
    assert_select "tr", text: /Rainy Day.*\$200\.00/m
    assert_select "tr", text: /Visa.*-\$420\.50/m
    assert_select ".panel-header", text: /Cash.*\$950\.00/m
    assert_select ".panel-header", text: /Credit Cards.*-\$420\.50/m
  end

  test "lists accounts in a fixed number of queries" do
    2.times do |n|
      account = create(:account, name: "Account #{n}")
      3.times { create(:transaction, account: account) }
    end

    # Accounts with their balances, in one query.
    assert_queries_count(1) { get accounts_path }
  end

  test "creates an account" do
    assert_difference "Account.count", 1 do
      post accounts_path, params: { account: { name: "Rainy Day", account_type: "savings", opening_balance: "1500.00" } }
    end

    account = Account.last
    assert_redirected_to account_path(account)
    assert account.savings?
    assert_equal BigDecimal("1500"), account.opening_balance
  end

  test "account page lists the opening balance after the newest-first transactions" do
    account = create(:account, opening_balance: "500.00")
    create(:transaction, account: account, description: "Older", transaction_date: 2.days.ago)
    create(:transaction, account: account, description: "Newer", transaction_date: 1.day.ago)

    get account_path(account)

    assert_equal [ "Newer", "Older", "Opening balance" ], css_select("tbody tr td:nth-child(2)").map { |cell| cell.text.strip }
    assert_select "tbody tr:last-child", text: /\$500\.00/
  end

  test "account page shows the opening balance even when it's zero and there are no transactions" do
    account = create(:account, name: "Empty")

    get account_path(account)

    assert_select "tbody tr", count: 1, text: /Opening balance.*\$0\.00/m
  end

  test "edits an account's opening balance" do
    account = create(:account, name: "Visa", account_type: "credit_card")

    get edit_account_path(account)
    assert_response :success
    assert_select "input[name=?]", "account[opening_balance]"

    patch account_path(account), params: { account: { opening_balance: "-500.00" } }
    assert_redirected_to account_path(account)
    assert_equal BigDecimal("-500"), account.reload.opening_balance
  end

  test "re-renders the edit form when an update is invalid" do
    account = create(:account, name: "Visa", opening_balance: "10.00")

    patch account_path(account), params: { account: { name: "", opening_balance: "" } }
    assert_response :unprocessable_entity
    assert_equal BigDecimal("10"), account.reload.opening_balance
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
    assert_equal [ "Groceries", "Paycheque", "Opening balance" ], css_select("tbody tr td:nth-child(2)").map(&:text)
    assert_select "td", text: "-$84.37"
  end

  test "shows the account's real balance" do
    account = create(:account)
    create(:transaction, account: account, amount: "2500.00")
    create(:transaction, account: account, amount: "-84.37")

    get account_path(account)
    assert_select "span", text: "$2,415.63"
  end
end
