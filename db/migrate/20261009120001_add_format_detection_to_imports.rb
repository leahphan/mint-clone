class AddFormatDetectionToImports < ActiveRecord::Migration[8.1]
  def change
    change_table :imports do |t|
      t.string :status, null: false, default: "completed" # every existing import completed
      # The uploaded CSV, kept only while the import waits for the user to confirm its columns.
      t.text :content
      t.jsonb :schema
      t.string :schema_source
      t.decimal :confidence, precision: 3, scale: 2
      t.string :format_fingerprint
      t.integer :rows_skipped, null: false, default: 0
      t.integer :rows_failed, null: false, default: 0
      t.jsonb :failed_rows, null: false, default: []

      t.check_constraint "status IN ('pending', 'completed')", name: "imports_status_valid"
      t.check_constraint "(status = 'pending') = (content IS NOT NULL)", name: "imports_content_only_while_pending"
      t.check_constraint "schema_source IN ('known', 'heuristic', 'ai', 'user')", name: "imports_schema_source_valid"
      t.check_constraint "confidence BETWEEN 0 AND 1", name: "imports_confidence_range"
      t.check_constraint "rows_imported >= 0 AND rows_skipped >= 0 AND rows_failed >= 0", name: "imports_counts_not_negative"
    end
    change_column_default :imports, :status, from: "completed", to: nil

    # Only a file that imported completely blocks uploading it again; a file with failed rows can be retried.
    remove_index :imports, [ :account_id, :checksum ], unique: true
    add_index :imports, [ :account_id, :checksum ], unique: true, where: "status = 'completed' AND rows_failed = 0",
      name: "index_imports_on_account_id_and_checksum_completed"
    add_index :imports, [ :account_id, :format_fingerprint ]
  end
end
