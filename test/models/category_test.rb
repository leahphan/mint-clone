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

  test "names are unique regardless of case and surrounding whitespace" do
    create(:category, name: "Groceries")

    duplicate = build(:category, name: " groceries ")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "requires an expense or income category_type" do
    assert build(:category, category_type: "expense").valid?
    assert build(:category, :income).income?
    assert_not build(:category, category_type: nil).valid?
    assert_not build(:category, category_type: "transfer").valid?
  end
end
