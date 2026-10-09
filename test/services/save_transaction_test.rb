require "test_helper"

class SaveTransactionTest < ActiveSupport::TestCase
  setup do
    @shopping = create(:category, name: "Shopping")
    @groceries = create(:category, name: "Groceries")
  end

  test "a category correction is recorded as manual and learned for the merchant" do
    merchant = create(:merchant, key: "COSTCO WHOLESALE", category: @shopping)
    transaction = create(:transaction, description: "COSTCO WHOLESALE #123", merchant: merchant,
      category: @shopping, categorization_source: "ai")

    assert SaveTransaction.call(transaction, category_id: @groceries.id)

    transaction.reload
    assert_equal [ @groceries, "manual", merchant ], [ transaction.category, transaction.categorization_source, transaction.merchant ]
    assert_equal @groceries, merchant.reload.category
  end

  test "a category picked for a new transaction creates the merchant mapping" do
    transaction = build(:transaction, description: "COSTCO WHOLESALE #456")

    assert_difference "Merchant.count", 1 do
      assert SaveTransaction.call(transaction, category_id: @groceries.id)
    end
    assert_equal @groceries, Merchant.find_by!(key: "COSTCO WHOLESALE").category
  end

  test "later imports from the merchant use the learned category" do
    SaveTransaction.call(build(:transaction, description: "COSTCO WHOLESALE #123"), category_id: @groceries.id)
    later = create(:transaction, description: "COSTCO WHOLESALE #999 MARKHAM")

    TransactionCategorizer.call(Transaction.where(id: later.id), classifier: nil)

    assert_equal [ @groceries, "learned" ], [ later.reload.category, later.categorization_source ]
  end

  test "editing other fields keeps the category's source" do
    transaction = create(:transaction, category: @groceries, categorization_source: "ai")

    assert SaveTransaction.call(transaction, description: "Renamed", category_id: @groceries.id.to_s)
    assert_equal "ai", transaction.reload.categorization_source
  end

  test "clearing the category clears its source but keeps the merchant mapping" do
    merchant = create(:merchant, key: "COSTCO WHOLESALE", category: @groceries)
    transaction = create(:transaction, description: "COSTCO WHOLESALE", merchant: merchant,
      category: @groceries, categorization_source: "learned")

    assert SaveTransaction.call(transaction, category_id: "")

    assert_nil transaction.reload.categorization_source
    assert_equal @groceries, merchant.reload.category
  end

  test "an invalid transaction is not saved and nothing is learned" do
    transaction = build(:transaction, description: "")

    assert_no_difference [ "Transaction.count", "Merchant.count" ] do
      assert_not SaveTransaction.call(transaction, category_id: @groceries.id)
    end
    assert transaction.errors.added?(:description, :blank)
  end
end
