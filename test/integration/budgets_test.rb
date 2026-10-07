require "test_helper"

class BudgetsTest < ActionDispatch::IntegrationTest
  test "lists budgets" do
    create(:budget, category: create(:category, name: "Groceries"), amount: "450.00")

    get budgets_path
    assert_response :success
    assert_select "tr", text: /Groceries.*\$450\.00/m
  end

  test "creates a budget" do
    groceries = create(:category, name: "Groceries")

    assert_difference "Budget.count", 1 do
      post budgets_path, params: { budget: { category_id: groceries.id, amount: "450.00" } }
    end
    assert_redirected_to budgets_path
    assert_equal BigDecimal("450"), groceries.reload.budget.amount
  end

  test "re-renders the form when the amount is invalid" do
    groceries = create(:category, name: "Groceries")

    assert_no_difference "Budget.count" do
      post budgets_path, params: { budget: { category_id: groceries.id, amount: "0" } }
    end
    assert_response :unprocessable_entity
    assert_select "select[name=?] option", "budget[category_id]", text: "Groceries (expense)"
  end

  test "shows an error when a budget for the category is created concurrently" do
    groceries = create(:category, name: "Groceries")
    create(:budget, category: groceries)
    create(:category, name: "Dining")
    racing =Budget.new(category: groceries, amount: "450.00")

    racing.stub(:valid?, true) do
      Budget.stub(:new, racing) do
        assert_no_difference "Budget.count" do
          post budgets_path, params: { budget: { category_id: groceries.id, amount: "450.00" } }
        end
      end
    end
    assert_response :unprocessable_entity
    assert_select "body", text: /has already been taken/
  end

  test "new budget form only offers categories without a budget" do
    create(:budget, category: create(:category, name: "Groceries"))
    create(:category, name: "Dining")

    get new_budget_path
    options = css_select("select[name='budget[category_id]'] option").map(&:text).reject(&:blank?)
    assert_equal [ "Dining (expense)" ], options
  end

  test "new budget page explains when every category has a budget" do
    create(:budget)

    get new_budget_path
    assert_select "p", text: "Every category has a budget"
    assert_select "select", count: 0
  end

  test "edits a budget's amount" do
    budget = create(:budget, amount: "100.00")

    get edit_budget_path(budget)
    assert_response :success

    patch budget_path(budget), params: { budget: { amount: "150.00" } }
    assert_redirected_to budgets_path
    assert_equal BigDecimal("150"), budget.reload.amount
  end

  test "re-renders the edit form when the amount is invalid" do
    budget = create(:budget, amount: "100.00")

    patch budget_path(budget), params: { budget: { amount: "-5" } }
    assert_response :unprocessable_entity
    assert_equal BigDecimal("100"), budget.reload.amount
  end

  test "removes a budget" do
    budget = create(:budget)

    assert_difference "Budget.count", -1 do
      delete budget_path(budget)
    end
    assert_redirected_to budgets_path
  end
end
