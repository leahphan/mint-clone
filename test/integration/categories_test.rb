require "test_helper"

class CategoriesTest < ActionDispatch::IntegrationTest
  test "lists categories" do
    create(:category, name: "Groceries")

    get categories_path
    assert_response :success
    assert_select "li", text: "Groceries"
  end

  test "creates a category" do
    assert_difference "Category.count", 1 do
      post categories_path, params: { category: { name: "Dining Out" } }
    end
    assert_redirected_to categories_path
  end

  test "re-renders the page when the name is a duplicate" do
    create(:category, name: "Groceries")

    assert_no_difference "Category.count" do
      post categories_path, params: { category: { name: "groceries" } }
    end
    assert_response :unprocessable_entity
    assert_select "li", text: "Name has already been taken"
  end
end
