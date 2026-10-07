class CreateBudgets < ActiveRecord::Migration[8.1]
  def change
    create_table :budgets do |t|
      t.references :category, null: false, foreign_key: true, index: { unique: true }
      t.decimal :amount, precision: 12, scale: 2, null: false

      t.timestamps
    end
  end
end
