require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "seeds the default categories once, keeping existing ones as they are" do
    misc = create(:category, name: "misc", category_type: "expense")
    create(:budget, category: misc, amount: "500.00")

    load_seeds
    assert_no_difference "Category.count" do
      load_seeds
    end

    assert_equal 19, Category.count
    assert_equal [ "Credit Card Payment", "Transfer" ], Category.transfer.order(:name).pluck(:name)
    assert_equal [ "Income" ], Category.income.pluck(:name)
    assert_equal [ "misc", BigDecimal("500") ], [ misc.reload.name, misc.budget.amount ]
    assert_not Category.exists?(name: "Other")
  end

  private
    def load_seeds
      load Rails.root.join("db/seeds.rb")
    end
end
