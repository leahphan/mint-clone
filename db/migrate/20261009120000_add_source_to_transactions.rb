class AddSourceToTransactions < ActiveRecord::Migration[8.1]
  def change
    change_table :transactions do |t|
      # Identifies an imported row by its source data, so overlapping exports don't create duplicates.
      # NULL for transactions entered by hand or imported before this existed.
      t.string :source_fingerprint
      # The row's cells exactly as they appeared in the CSV file.
      t.jsonb :source_row
      # Imported despite matching an existing transaction, because there was no running balance to tell them apart.
      t.boolean :possible_duplicate, null: false, default: false

      t.index [ :account_id, :source_fingerprint ], unique: true
    end
  end
end
