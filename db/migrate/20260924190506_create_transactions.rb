class CreateTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :transactions do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.date :transaction_date, null: false
      t.string :description, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false

      t.timestamps
    end
    add_index :transactions, [ :account_id, :transaction_date ]
  end
end
