require "test_helper"

class SaveTransactionTest < ActiveSupport::TestCase
  setup do
    @user = create(:user)
    @account = create(:account, user: @user)
    @shopping = create(:category, user: @user, name: "Shopping")
    @groceries = create(:category, user: @user, name: "Groceries")
  end

  test "a category correction is recorded as manual and learned for the merchant" do
    merchant = create(:merchant, user: @user, key: "COSTCO WHOLESALE", category: @shopping)
    transaction = create(:transaction, account: @account, description: "COSTCO WHOLESALE #123", merchant: merchant,
      category: @shopping, categorization_source: "ai")

    assert SaveTransaction.call(transaction, category_id: @groceries.id)

    transaction.reload
    assert_equal [ @groceries, "manual", merchant ], [ transaction.category, transaction.categorization_source, transaction.merchant ]
    assert_equal @groceries, merchant.reload.category
  end

  test "a category picked for a new transaction creates the merchant mapping" do
    transaction = build(:transaction, account: @account, description: "COSTCO WHOLESALE #456")

    assert_difference "Merchant.count", 1 do
      assert SaveTransaction.call(transaction, category_id: @groceries.id)
    end
    assert_equal @groceries, @user.merchants.find_by!(key: "COSTCO WHOLESALE").category
  end

  test "later imports from the merchant use the learned category" do
    SaveTransaction.call(build(:transaction, account: @account, description: "COSTCO WHOLESALE #123"), category_id: @groceries.id)
    later = create(:transaction, account: @account, description: "COSTCO WHOLESALE #999 MARKHAM")

    TransactionCategorizer.call(Transaction.where(id: later.id), user: @user, classifier: nil)

    assert_equal [ @groceries, "learned" ], [ later.reload.category, later.categorization_source ]
  end

  test "editing other fields keeps the category's source" do
    transaction = create(:transaction, account: @account, category: @groceries, categorization_source: "ai")

    assert SaveTransaction.call(transaction, description: "Renamed", category_id: @groceries.id.to_s)
    assert_equal "ai", transaction.reload.categorization_source
  end

  test "clearing the category clears its source but keeps the merchant mapping" do
    merchant = create(:merchant, user: @user, key: "COSTCO WHOLESALE", category: @groceries)
    transaction = create(:transaction, account: @account, description: "COSTCO WHOLESALE", merchant: merchant,
      category: @groceries, categorization_source: "learned")

    assert SaveTransaction.call(transaction, category_id: "")

    assert_nil transaction.reload.categorization_source
    assert_equal @groceries, merchant.reload.category
  end

  test "an invalid transaction is not saved and nothing is learned" do
    transaction = build(:transaction, account: @account, description: "")

    assert_no_difference [ "Transaction.count", "Merchant.count" ] do
      assert_not SaveTransaction.call(transaction, category_id: @groceries.id)
    end
    assert transaction.errors.added?(:description, :blank)
  end

  test "learns the category on the account owner's merchant, not another user's with the same key" do
    other_user = create(:user)
    theirs = create(:merchant, user: other_user, key: "COSTCO WHOLESALE", category: create(:category, user: other_user))
    transaction = create(:transaction, account: @account, description: "COSTCO WHOLESALE #123")

    assert SaveTransaction.call(transaction, category_id: @groceries.id)

    assert_equal [ @user, @groceries ], [ transaction.reload.merchant.user, transaction.merchant.category ]
    assert_not_equal theirs, transaction.merchant
    assert_not_equal @groceries, theirs.reload.category
  end

  test "another user's category is rejected and nothing is learned" do
    other_category = create(:category, user: create(:user))
    transaction = create(:transaction, account: @account, description: "COSTCO WHOLESALE")

    assert_no_difference "Merchant.count" do
      assert_not SaveTransaction.call(transaction, category_id: other_category.id)
    end
    assert_includes transaction.errors[:category], "must be one of your categories"
    assert_nil transaction.reload.category
  end
end
