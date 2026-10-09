require "test_helper"

class CategoriesTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
    sign_in_as @user
  end

  test "lists categories" do
    create(:category, user: @user, name: "Groceries")

    get categories_path
    assert_response :success
    assert_select "li", text: /Groceries\s+Expense\s+Edit/
  end

  test "creates a category" do
    assert_difference "Category.count", 1 do
      post categories_path, params: { category: { name: "Paycheque", category_type: "income" } }
    end
    assert_redirected_to categories_path
    assert Category.find_by!(name: "Paycheque").income?
  end

  test "requires choosing a category type" do
    assert_no_difference "Category.count" do
      post categories_path, params: { category: { name: "Dining Out", category_type: "" } }
    end
    assert_response :unprocessable_entity
    assert_select "li", text: /Category type/
  end

  test "edits a category's name and type" do
    category = create(:category, user: @user, name: "Paycheck")

    get edit_category_path(category)
    assert_response :success

    patch category_path(category), params: { category: { name: "Paycheque", category_type: "income" } }
    assert_redirected_to categories_path
    category.reload
    assert_equal "Paycheque", category.name
    assert category.income?
  end

  test "re-renders the edit form when an update is invalid" do
    category = create(:category, user: @user, name: "Groceries")

    patch category_path(category), params: { category: { name: "", category_type: "income" } }
    assert_response :unprocessable_entity
    assert category.reload.expense?
  end

  test "re-renders the page when the name is a duplicate" do
    create(:category, user: @user, name: "Groceries")

    assert_no_difference "Category.count" do
      post categories_path, params: { category: { name: "groceries", category_type: "expense" } }
    end
    assert_response :unprocessable_entity
    assert_select "li", text: "Name has already been taken"
  end
end
