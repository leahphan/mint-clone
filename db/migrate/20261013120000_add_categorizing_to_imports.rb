class AddCategorizingToImports < ActiveRecord::Migration[8.1]
  def change
    # Set while the import's remaining transactions wait for the AI classifier in the background.
    add_column :imports, :categorizing_since, :datetime

    # Transactions can now be categorized from the starter list of common merchants.
    remove_check_constraint :transactions, "categorization_source IN ('learned', 'ai', 'manual')", name: "transactions_categorization_source_valid"
    add_check_constraint :transactions, "categorization_source IN ('learned', 'starter_list', 'ai', 'manual')", name: "transactions_categorization_source_valid"
  end
end
