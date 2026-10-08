require "test_helper"

class BudgetTest < ActiveSupport::TestCase
  test "amount must be positive" do
    assert build(:budget, amount: "0.01").valid?
    assert_not build(:budget, amount: "0").valid?
    assert_not build(:budget, amount: "-10").valid?
    assert_not build(:budget, amount: nil).valid?
  end

  test "database rejects a non-positive amount" do
    budget = create(:budget)
    assert_raises(ActiveRecord::CheckViolation) { budget.update_column(:amount, 0) }
  end

  test "a transfer category can't have a budget" do
    budget = build(:budget, category: create(:category, category_type: "transfer"))

    assert_not budget.valid?
    assert_includes budget.errors[:category], "can't be a transfer category"
  end

  test "one budget per category" do
    budget = create(:budget)
    duplicate = build(:budget, category: budget.category)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:category_id], "has already been taken"
  end

  test "is removed with its category" do
    budget = create(:budget)
    assert_difference "Budget.count", -1 do
      budget.category.destroy
    end
  end
end
