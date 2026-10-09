require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "email addresses are unique" do
    create(:user, email_address: "leah@example.com")

    assert_not build(:user, email_address: "LEAH@example.com").valid?
  end

  test "add_default_categories adds the defaults once, keeping the user's existing ones as they are" do
    user = create(:user)
    misc = create(:category, user: user, name: "misc", category_type: "expense")
    create(:budget, category: misc, amount: "500.00")

    user.add_default_categories
    assert_no_difference "Category.count" do
      user.add_default_categories
    end

    assert_equal 19, user.categories.count
    assert_equal [ "Credit Card Payment", "Transfer" ], user.categories.transfer.order(:name).pluck(:name)
    assert_equal [ "Income" ], user.categories.income.pluck(:name)
    assert_equal [ "misc", BigDecimal("500") ], [ misc.reload.name, misc.budget.amount ]
    assert_not user.categories.exists?(name: "Other")
  end

  test "add_default_categories ignores other users' categories" do
    create(:category, name: "Groceries")
    user = create(:user)

    user.add_default_categories

    assert user.categories.exists?(name: "Groceries")
  end
end
