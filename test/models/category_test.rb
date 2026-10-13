require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  test "requires a name" do
    category = build(:category, name: "  ")
    assert_not category.valid?
    assert_includes category.errors[:name], "can't be blank"
  end

  test "strips surrounding whitespace from the name" do
    assert_equal "Groceries", create(:category, name: "  Groceries ").name
  end

  test "names are unique per user regardless of case and surrounding whitespace" do
    user = create(:user)
    create(:category, user: user, name: "Groceries")

    duplicate = build(:category, user: user, name: " groceries ")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save(validate: false) }
  end

  test "different users can each have a category with the same name" do
    create(:category, name: "Groceries")

    assert build(:category, user: create(:user), name: "groceries").valid?
  end

  test "requires an expense, income, or transfer category_type" do
    assert build(:category, category_type: "expense").valid?
    assert build(:category, :income).income?
    assert build(:category, category_type: "transfer").valid?
    assert_not build(:category, category_type: nil).valid?
    assert_not build(:category, category_type: "savings").valid?
  end

  test "a budgeted category can't become a transfer" do
    category = create(:budget).category

    assert_not category.update(category_type: "transfer")
    assert_includes category.errors[:category_type], "can't be transfer while the category has a budget"
  end
end
