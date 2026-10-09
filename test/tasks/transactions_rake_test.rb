require "test_helper"
require "rake"

class TransactionsRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.none?
    Rake::Task["transactions:categorize"].reenable
  end

  test "categorize fills in each user's uncategorized transactions from their own learned merchants" do
    user = create(:user)
    account = create(:account, user: user)
    groceries = create(:category, user: user, name: "Groceries")
    create(:merchant, user: user, key: "LOBLAWS", category: groceries)
    existing = create(:transaction, account: account, description: "LOBLAWS")
    manual = create(:transaction, account: account, description: "LOBLAWS",
      category: create(:category, user: user), categorization_source: "manual")
    other_users = create(:transaction, description: "LOBLAWS")

    TransactionCategorizer.stub(:default_classifier, nil) do
      assert_output(/Categorized 1; 1 still uncategorized/) { Rake::Task["transactions:categorize"].invoke }
    end

    assert_equal [ groceries, "learned" ], [ existing.reload.category, existing.categorization_source ]
    assert_equal "manual", manual.reload.categorization_source
    assert_nil other_users.reload.category
  end
end
