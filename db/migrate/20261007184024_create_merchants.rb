class CreateMerchants < ActiveRecord::Migration[8.1]
  def change
    create_table :merchants do |t|
      t.string :key, null: false, index: { unique: true }
      t.string :name, null: false
      t.references :category, foreign_key: true

      t.timestamps
    end

    change_table :transactions do |t|
      t.references :merchant, foreign_key: true
      t.string :categorization_source
      t.check_constraint "categorization_source IN ('learned', 'ai', 'manual')", name: "transactions_categorization_source_valid"
    end
  end
end
