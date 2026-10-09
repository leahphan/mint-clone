class AddCategoryTypeToCategories < ActiveRecord::Migration[8.1]
  def change
    # Existing categories (and their budgets) were all treated as expenses, so backfill that,
    # then drop the default so every new category has to choose.
    add_column :categories, :category_type, :string, null: false, default: "expense"
    change_column_default :categories, :category_type, from: "expense", to: nil
  end
end
