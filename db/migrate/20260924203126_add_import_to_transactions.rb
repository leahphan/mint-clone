class AddImportToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_reference :transactions, :import, foreign_key: true
  end
end
