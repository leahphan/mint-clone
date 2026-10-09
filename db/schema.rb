# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_09_120001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.string "name", null: false
    t.string "account_type", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "opening_balance", precision: 12, scale: 2, default: "0.0", null: false
  end

  create_table "budgets", force: :cascade do |t|
    t.bigint "category_id", null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_budgets_on_category_id", unique: true
    t.check_constraint "amount > 0::numeric", name: "budgets_amount_positive"
  end

  create_table "categories", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "category_type", null: false
    t.index "lower((name)::text)", name: "index_categories_on_lower_name", unique: true
  end

  create_table "imports", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "filename", null: false
    t.string "checksum", null: false
    t.integer "rows_imported", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", null: false
    t.text "content"
    t.jsonb "schema"
    t.string "schema_source"
    t.decimal "confidence", precision: 3, scale: 2
    t.string "format_fingerprint"
    t.integer "rows_skipped", default: 0, null: false
    t.integer "rows_failed", default: 0, null: false
    t.jsonb "failed_rows", default: [], null: false
    t.index ["account_id", "checksum"], name: "index_imports_on_account_id_and_checksum_completed", unique: true, where: "(((status)::text = 'completed'::text) AND (rows_failed = 0))"
    t.index ["account_id", "format_fingerprint"], name: "index_imports_on_account_id_and_format_fingerprint"
    t.check_constraint "(status::text = 'pending'::text) = (content IS NOT NULL)", name: "imports_content_only_while_pending"
    t.check_constraint "confidence >= 0::numeric AND confidence <= 1::numeric", name: "imports_confidence_range"
    t.check_constraint "rows_imported >= 0 AND rows_skipped >= 0 AND rows_failed >= 0", name: "imports_counts_not_negative"
    t.check_constraint "schema_source::text = ANY (ARRAY['known'::character varying, 'heuristic'::character varying, 'ai'::character varying, 'user'::character varying]::text[])", name: "imports_schema_source_valid"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'completed'::character varying]::text[])", name: "imports_status_valid"
  end

  create_table "merchants", force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.bigint "category_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_merchants_on_category_id"
    t.index ["key"], name: "index_merchants_on_key", unique: true
  end

  create_table "transactions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.date "transaction_date", null: false
    t.string "description", null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "category_id"
    t.bigint "import_id"
    t.bigint "merchant_id"
    t.string "categorization_source"
    t.string "source_fingerprint"
    t.jsonb "source_row"
    t.boolean "possible_duplicate", default: false, null: false
    t.index ["account_id", "source_fingerprint"], name: "index_transactions_on_account_id_and_source_fingerprint", unique: true
    t.index ["account_id", "transaction_date"], name: "index_transactions_on_account_id_and_transaction_date"
    t.index ["category_id"], name: "index_transactions_on_category_id"
    t.index ["import_id"], name: "index_transactions_on_import_id"
    t.index ["merchant_id"], name: "index_transactions_on_merchant_id"
    t.check_constraint "categorization_source::text = ANY (ARRAY['learned'::character varying, 'ai'::character varying, 'manual'::character varying]::text[])", name: "transactions_categorization_source_valid"
  end

  add_foreign_key "budgets", "categories"
  add_foreign_key "imports", "accounts"
  add_foreign_key "merchants", "categories"
  add_foreign_key "transactions", "accounts"
  add_foreign_key "transactions", "categories"
  add_foreign_key "transactions", "imports"
  add_foreign_key "transactions", "merchants"
end
