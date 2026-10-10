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
    other_user = create(:user)
    food = create(:category, user: other_user, name: "Food")
    create(:merchant, user: other_user, key: "LOBLAWS", category: food)
    other_users = create(:transaction, account: create(:account, user: other_user), description: "LOBLAWS")
    unknown = create(:transaction, account: account, description: "NEW PLACE")

    TransactionCategorizer.stub(:default_classifier, nil) do
      assert_output(/Categorized 2; 1 still uncategorized/) { Rake::Task["transactions:categorize"].invoke }
    end

    assert_equal [ groceries, "learned" ], [ existing.reload.category, existing.categorization_source ]
    assert_equal [ food, "learned" ], [ other_users.reload.category, other_users.categorization_source ]
    assert_equal "manual", manual.reload.categorization_source
    assert_nil unknown.reload.category
  end
end
