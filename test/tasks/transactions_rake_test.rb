require "test_helper"
require "rake"

class TransactionsRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.none?
    Rake::Task["transactions:categorize"].reenable
  end

  test "categorize fills in existing uncategorized transactions from learned merchants" do
    groceries = create(:category, name: "Groceries")
    create(:merchant, key: "LOBLAWS", category: groceries)
    existing = create(:transaction, description: "LOBLAWS")
    manual = create(:transaction, description: "LOBLAWS", category: create(:category), categorization_source: "manual")

    TransactionCategorizer.stub(:default_classifier, nil) do
      assert_output(/Categorized 1; 0 still uncategorized/) { Rake::Task["transactions:categorize"].invoke }
    end

    assert_equal [ groceries, "learned" ], [ existing.reload.category, existing.categorization_source ]
    assert_equal "manual", manual.reload.categorization_source
  end
end
