# Accounts, categories and merchants belong to a user. Transactions and imports belong to
# one through their account, and budgets through their category.
class AddUserOwnership < ActiveRecord::Migration[8.1]
  def up
    if select_value("SELECT 1 FROM accounts UNION ALL SELECT 1 FROM categories UNION ALL SELECT 1 FROM merchants LIMIT 1")
      raise "Existing accounts, categories or merchants have no owner, and this migration doesn't assign them to anyone. " \
        "Reset the database (bin/rails db:reset), then create your user: bin/rails users:set_password EMAIL=you@example.com"
    end

    add_reference :accounts, :user, null: false, foreign_key: true
    add_reference :categories, :user, null: false, foreign_key: true, index: false
    add_reference :merchants, :user, null: false, foreign_key: true, index: false

    remove_index :categories, name: "index_categories_on_lower_name"
    add_index :categories, "user_id, lower((name)::text)", unique: true, name: "index_categories_on_user_id_and_lower_name"
    # The target of merchants' composite foreign key below.
    add_index :categories, [ :id, :user_id ], unique: true

    remove_index :merchants, :key, unique: true
    add_index :merchants, [ :user_id, :key ], unique: true

    # A merchant's learned category must be one of its own user's categories.
    remove_foreign_key :merchants, :categories
    add_foreign_key :merchants, :categories, column: [ :category_id, :user_id ], primary_key: [ :id, :user_id ]
  end

  def down
    owners = select_value("SELECT COUNT(DISTINCT user_id) FROM (SELECT user_id FROM accounts UNION SELECT user_id FROM categories UNION SELECT user_id FROM merchants) owners")
    raise ActiveRecord::IrreversibleMigration, "More than one user owns data; names and merchant keys can't be made globally unique again." if owners.to_i > 1

    remove_foreign_key :merchants, :categories, column: [ :category_id, :user_id ]
    add_foreign_key :merchants, :categories

    remove_index :merchants, [ :user_id, :key ]
    add_index :merchants, :key, unique: true

    remove_index :categories, [ :id, :user_id ]
    remove_index :categories, name: "index_categories_on_user_id_and_lower_name"
    add_index :categories, "lower((name)::text)", unique: true, name: "index_categories_on_lower_name"

    remove_reference :merchants, :user, foreign_key: true, index: false
    remove_reference :categories, :user, foreign_key: true, index: false
    remove_reference :accounts, :user, foreign_key: true
  end
end
