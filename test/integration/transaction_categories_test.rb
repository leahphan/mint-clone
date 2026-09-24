require "test_helper"

class TransactionCategoriesTest < ActionDispatch::IntegrationTest
  setup do
    @account = create(:account)
    @groceries = create(:category, name: "Groceries")
  end

  test "creates a transaction with a category" do
    post account_transactions_path(@account), params: {
      transaction: { transaction_date: "2026-09-15", description: "Market", amount: "-42.00", category_id: @groceries.id }
    }

    assert_redirected_to account_path(@account)
    assert_equal @groceries, @account.transactions.find_by!(description: "Market").category
  end

  test "creates an uncategorized transaction" do
    post account_transactions_path(@account), params: {
      transaction: { transaction_date: "2026-09-15", description: "Cash", amount: "-20.00", category_id: "" }
    }

    assert_redirected_to account_path(@account)
    assert_nil @account.transactions.find_by!(description: "Cash").category
  end

  test "changes a transaction's category" do
    transaction = create(:transaction, account: @account)
    get edit_account_transaction_path(@account, transaction)
    assert_response :success

    patch account_transaction_path(@account, transaction), params: { transaction: { category_id: @groceries.id } }
    assert_redirected_to account_path(@account)
    assert_equal @groceries, transaction.reload.category

    patch account_transaction_path(@account, transaction), params: { transaction: { category_id: "" } }
    assert_nil transaction.reload.category
  end

  test "re-renders the edit form when the update is invalid" do
    transaction = create(:transaction, account: @account)

    patch account_transaction_path(@account, transaction), params: { transaction: { description: "" } }
    assert_response :unprocessable_entity
  end

  test "does not edit a transaction from another account" do
    other_transaction = create(:transaction)

    get edit_account_transaction_path(@account, other_transaction)
    assert_response :not_found
  end

  test "account page shows the category or Uncategorized" do
    create(:transaction, account: @account, description: "Market", category: @groceries)
    create(:transaction, account: @account, description: "Cash")

    get account_path(@account)
    assert_select "tr", text: /Market.*Groceries/m
    assert_select "tr", text: /Cash.*Uncategorized/m
  end
end
