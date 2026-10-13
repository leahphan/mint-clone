require "test_helper"

# Another user's records are invisible: their ids return 404 and nothing of theirs changes.
class UserIsolationTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
    sign_in_as @user
    @account = create(:account, user: @user, name: "My Chequing")

    @other_user = create(:user)
    @their_account = create(:account, user: @other_user, name: "Their Savings", opening_balance: "100.00")
    @their_category = create(:category, user: @other_user, name: "Their Hobbies")
    @their_transaction = create(:transaction, account: @their_account, description: "Their Purchase",
      amount: "-77.77", category: @their_category)
    @their_budget = create(:budget, category: @their_category, amount: "300.00")
  end

  test "lists, dashboard, categories and budgets leave out another user's data" do
    create(:category, user: @user, name: "My Groceries")
    create(:category, user: @other_user, name: "Their Travel")

    [ root_path, accounts_path, categories_path, budgets_path, new_budget_path, new_account_transaction_path(@account) ].each do |path|
      get path
      assert_response :success
      assert_no_match(/Their (Savings|Hobbies|Purchase|Travel)|77\.77|300\.00/, response.body, "#{path} shows another user's data")
    end
    get categories_path
    assert_select "li span", text: "My Groceries"
  end

  test "another user's account can't be seen or changed" do
    get account_path(@their_account)
    assert_response :not_found
    get edit_account_path(@their_account)
    assert_response :not_found
    patch account_path(@their_account), params: { account: { name: "Mine now", opening_balance: "0" } }
    assert_response :not_found

    assert_equal [ "Their Savings", BigDecimal("100") ], [ @their_account.reload.name, @their_account.opening_balance ]
  end

  test "another user's transactions can't be added to, seen or changed" do
    get new_account_transaction_path(@their_account)
    assert_response :not_found
    assert_no_difference "Transaction.count" do
      post account_transactions_path(@their_account), params: { transaction: { transaction_date: "2026-09-15", description: "Sneaky", amount: "-1.00" } }
    end
    assert_response :not_found

    [ @their_account, @account ].each do |account|
      get edit_account_transaction_path(account, @their_transaction)
      assert_response :not_found
      patch account_transaction_path(account, @their_transaction), params: { transaction: { description: "Changed", category_id: "" } }
      assert_response :not_found
    end

    @their_transaction.reload
    assert_equal [ "Their Purchase", @their_category, @their_account ], [ @their_transaction.description, @their_transaction.category, @their_transaction.account ]
  end

  test "another user's imports can't be started, seen, confirmed or discarded" do
    their_import = create(:import, :pending, account: @their_account)

    get new_account_import_path(@their_account)
    assert_response :not_found
    assert_no_difference "Import.count" do
      post account_imports_path(@their_account), params: { file: csv_upload("Date,Description,Amount\n2026-10-08,Sneaky,-1.00\n") }
    end
    assert_response :not_found

    [ @their_account, @account ].each do |account|
      get account_import_path(account, their_import)
      assert_response :not_found
      patch account_import_path(account, their_import), params: { schema: { date_column: 0, date_format: "%Y-%m-%d", description_column: 1, amount_strategy: "signed", amount_column: 2 } }
      assert_response :not_found
      delete account_import_path(account, their_import)
      assert_response :not_found
    end

    assert their_import.reload.pending?
    assert_equal 1, @their_account.transactions.count
  end

  test "another user's categories can't be seen or changed" do
    get edit_category_path(@their_category)
    assert_response :not_found
    patch category_path(@their_category), params: { category: { name: "Mine now", category_type: "income" } }
    assert_response :not_found

    assert_equal [ "Their Hobbies", "expense" ], [ @their_category.reload.name, @their_category.category_type ]
  end

  test "another user's budgets can't be seen, changed or removed, nor their categories budgeted" do
    get edit_budget_path(@their_budget)
    assert_response :not_found
    patch budget_path(@their_budget), params: { budget: { amount: "1.00" } }
    assert_response :not_found
    assert_no_difference "Budget.count" do
      delete budget_path(@their_budget)
    end
    assert_response :not_found
    assert_equal BigDecimal("300"), @their_budget.reload.amount

    their_unbudgeted = create(:category, user: @other_user, name: "Their Travel")
    assert_no_difference "Budget.count" do
      post budgets_path, params: { budget: { category_id: their_unbudgeted.id, amount: "50.00" } }
    end
    assert_response :unprocessable_entity
  end

  test "a transaction can't be given another user's category" do
    assert_no_difference "Transaction.count" do
      post account_transactions_path(@account), params: {
        transaction: { transaction_date: "2026-09-15", description: "Market", amount: "-42.00", category_id: @their_category.id }
      }
    end
    assert_response :unprocessable_entity

    mine = create(:transaction, account: @account, description: "Market")
    patch account_transaction_path(@account, mine), params: { transaction: { category_id: @their_category.id } }
    assert_response :unprocessable_entity
    assert_nil mine.reload.category
  end

  test "a transaction can't be attached to another user's merchant" do
    groceries = create(:category, user: @user, name: "Groceries")
    their_merchant = create(:merchant, user: @other_user, key: "LOBLAWS", category: @their_category)

    post account_transactions_path(@account), params: {
      transaction: { transaction_date: "2026-09-15", description: "LOBLAWS", amount: "-42.00", category_id: groceries.id, merchant_id: their_merchant.id }
    }
    created = @account.transactions.find_by!(description: "LOBLAWS")

    mine = create(:transaction, account: @account, description: "LOBLAWS #12")
    patch account_transaction_path(@account, mine), params: { transaction: { amount: "-5.00", merchant_id: their_merchant.id } }
    assert_redirected_to account_path(@account)
    assert_nil mine.reload.merchant

    patch account_transaction_path(@account, mine), params: { transaction: { category_id: groceries.id, merchant_id: their_merchant.id } }

    [ created, mine.reload ].each do |transaction|
      assert_equal [ @user, "LOBLAWS", groceries ], [ transaction.merchant.user, transaction.merchant.key, transaction.merchant.category ]
    end
    assert_equal [ @other_user, @their_category ], [ their_merchant.reload.user, their_merchant.category ]
    assert_empty their_merchant.transactions
  end
end
