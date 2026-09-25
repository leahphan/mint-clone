class AddOpeningBalanceToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :opening_balance, :decimal, precision: 12, scale: 2, null: false, default: 0
  end
end
