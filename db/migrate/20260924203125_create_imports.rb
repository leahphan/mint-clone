class CreateImports < ActiveRecord::Migration[8.1]
  def change
    create_table :imports do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.string :filename, null: false
      t.string :checksum, null: false
      t.integer :rows_imported, null: false

      t.timestamps
    end
    add_index :imports, [ :account_id, :checksum ], unique: true
  end
end
