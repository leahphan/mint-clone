require "test_helper"

class TransactionCsvImporterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  CHEQUING_LINES = 71

  setup do
    @chequing = create(:account, name: "TD Chequing", account_type: "chequing")
    @visa = create(:account, name: "TD Visa", account_type: "credit_card")
  end

  # --- TD exports ---

  test "imports the TD chequing export: debits as money out, credits as money in, raw data kept" do
    import = import_into(@chequing, fixture_upload("td_chequing.csv"))

    assert import.completed?, import.errors.full_messages.to_sentence
    assert_equal [ 71, 0, 0, "heuristic" ], [ import.rows_imported, import.rows_skipped, import.rows_failed, import.schema_source ]
    assert_equal BigDecimal("-981.80"), @chequing.transactions.sum(:amount)
    assert_nil import.reload.content

    first = @chequing.transactions.find_by!(transaction_date: Date.new(2026, 9, 9), amount: BigDecimal("-130"))
    assert_equal [ "KAFU SEMO AND   _F", [ "2026-09-09", "KAFU SEMO AND   _F", "130", "", "2219.22" ], import ],
      [ first.description, first.source_row, first.import ]
    assert first.source_fingerprint.present?
    assert_equal BigDecimal("4000"), @chequing.transactions.find_by!(description: "LAFA ATM DEP    361250").amount
  end

  test "imports the TD Visa export into a credit card: purchases negative, payments positive" do
    import = import_into(@visa, fixture_upload("td_visa.csv"))

    assert_equal 52, import.rows_imported
    assert_equal BigDecimal("1167.58"), @visa.transactions.sum(:amount)
    assert_equal BigDecimal("-35.58"), @visa.transactions.find_by!(description: "Semo.com", transaction_date: Date.new(2026, 10, 4), amount: -35.58).amount
    assert_equal 2, @visa.transactions.where("description LIKE ?", "PAYMENT%").where("amount > 0").count
  end

  test "still imports the original date,description,amount layout automatically" do
    import = import_into(@chequing, csv_upload("date,description,amount\n2026-09-01,Loblaws,-54.32\n2026-09-02,Payroll,2500.00\n"))

    assert import.completed?
    assert_equal [ BigDecimal("-54.32"), BigDecimal("2500") ], @chequing.transactions.order(:transaction_date).pluck(:amount)
  end

  # --- Duplicates ---

  test "rejects the same file uploaded to the same account again" do
    import_into(@chequing, fixture_upload("td_chequing.csv"))

    import = nil
    assert_no_difference [ "Import.count", "Transaction.count" ] do
      import = import_into(@chequing, fixture_upload("td_chequing.csv"))
    end
    assert_match(/\Atd_chequing\.csv was already imported into this account on /, import.errors.full_messages.sole)
  end

  test "imports only the new rows of an overlapping export" do
    import_into(@chequing, fixture_upload("td_chequing.csv", lines: 0..48))
    import = import_into(@chequing, fixture_upload("td_chequing.csv", lines: 39..70))

    assert_equal [ 22, 10 ], [ import.rows_imported, import.rows_skipped ]
    assert_equal [ CHEQUING_LINES, BigDecimal("-981.80") ], [ @chequing.transactions.count, @chequing.transactions.sum(:amount) ]
    assert_equal 22, import.transactions.count
  end

  test "recognizes rows again when the amounts are written differently (130, 130.0, 130.00)" do
    import_into(@chequing, fixture_upload("td_chequing.csv", lines: 0..19))
    reformatted = file_fixture("td_chequing.csv").readlines.first(30).map do |line|
      line.gsub(/"(\d+)(?:\.(\d{1,2}))?"/) { %("#{$1}.#{($2 || "").ljust(2, "0")}") }
    end.join

    import = import_into(@chequing, csv_upload(reformatted, filename: "reformatted.csv"))

    assert_equal [ 10, 20 ], [ import.rows_imported, import.rows_skipped ]
  end

  test "row order doesn't matter: the same rows newest first are all duplicates" do
    import_into(@chequing, fixture_upload("td_chequing.csv"))
    import = import_into(@chequing, csv_upload(file_fixture("td_chequing.csv").readlines.reverse.join, filename: "reversed.csv"))

    assert_equal [ 0, CHEQUING_LINES ], [ import.rows_imported, import.rows_skipped ]
  end

  test "keeps identical same-day purchases that have different running balances" do
    import = import_into(@chequing, fixture_upload("duplicate_purchases.csv"))

    assert_equal 5, import.rows_imported
    assert_equal 2, @chequing.transactions.where(description: "COFFEE SHOP").count
  end

  test "duplicates are scoped to the account" do
    import_into(@chequing, fixture_upload("td_chequing.csv"))
    savings = create(:account, name: "Savings", account_type: "savings")

    assert_equal CHEQUING_LINES, import_into(savings, fixture_upload("td_chequing.csv")).rows_imported
  end

  test "flags rows of a balance export that match transactions imported without balances or entered by hand" do
    import_into(@chequing, csv_upload("date,description,amount\n2026-09-09,KAFU SEMO AND _F,-130\n", filename: "old_format.csv"))
    create(:transaction, account: @chequing, transaction_date: Date.new(2026, 9, 9), description: "FISO POBI BUKI _F", amount: -24.05)

    import = import_into(@chequing, fixture_upload("td_chequing.csv"))

    assert_equal [ 71, 0 ], [ import.rows_imported, import.rows_skipped ]
    assert_equal [ "FISO POBI BUKI        _F", "KAFU SEMO AND   _F" ], import.transactions.where(possible_duplicate: true).order(:description).pluck(:description)
  end

  test "doesn't flag a repeat purchase whose balance tells it apart from one imported with a balance" do
    import_into(@chequing, fixture_upload("duplicate_purchases.csv"))
    later = file_fixture("duplicate_purchases.csv").read + %("2026-10-04","PHARMACY","10.00",,"1035.00"\n)

    import = import_into(@chequing, csv_upload(later, filename: "later.csv"))

    assert_equal [ 1, 5 ], [ import.rows_imported, import.rows_skipped ]
    assert_not import.transactions.sole.possible_duplicate
  end

  # --- Files without a running balance ---

  test "without balances, identical rows in one file are kept" do
    import = import_into(@chequing, fixture_upload("signed_amount.csv"))

    assert_equal [ 5, 0 ], [ import.rows_imported, @chequing.transactions.where(possible_duplicate: true).count ]
    assert_equal 2, @chequing.transactions.where(description: "Coffee Shop").count
  end

  test "without balances, a row matching an existing transaction is imported and flagged, never dropped" do
    import_into(@chequing, csv_upload("Date,Description,Amount\n2026-10-08,Starbucks,-6.25\n", filename: "first.csv"))

    import = import_into(@chequing, csv_upload("Date,Description,Amount\n2026-10-08,STARBUCKS ,-6.25\n2026-10-09,Payroll,2500.00\n", filename: "second.csv"))

    assert_equal [ 2, 0 ], [ import.rows_imported, import.rows_skipped ]
    assert_equal [ [ "STARBUCKS", true ], [ "Payroll", false ] ], import.transactions.order(:transaction_date).pluck(:description, :possible_duplicate)
    assert_equal 2, @chequing.transactions.where(transaction_date: Date.new(2026, 10, 8)).count
  end

  test "without balances, two coffees then an export with a repeat and a new coffee keeps all four, flagged" do
    two_coffees = "Date,Description,Amount\n2026-10-01,COFFEE SHOP,-5.00\n2026-10-01,COFFEE SHOP,-5.00\n"
    import_into(@chequing, csv_upload(two_coffees, filename: "first.csv"))

    import = import_into(@chequing, csv_upload(two_coffees + "2026-10-02,Payroll,2500.00\n", filename: "second.csv"))

    assert_equal 4, @chequing.transactions.where(description: "COFFEE SHOP").count
    assert_equal 2, import.transactions.where(possible_duplicate: true).count
  end

  # --- Rows that can't be read ---

  test "imports the rows it can read and records the ones it can't" do
    lines = file_fixture("td_chequing.csv").readlines
    lines[4] = %("2026-09-10","TOLU # 370","abc",,"2130.31"\n)
    lines[9] = %("2026-09-12","SHORT ROW","5.00"\n)

    import = import_into(@chequing, csv_upload(lines.join, filename: "with_errors.csv"))

    assert import.completed?
    assert_equal [ 69, 2 ], [ import.rows_imported, import.rows_failed ]
    assert_equal [
      { line: 5, row: %("2026-09-10","TOLU # 370","abc",,"2130.31"), messages: [ %(debit "abc" isn't a number) ] },
      { line: 10, row: %("2026-09-12","SHORT ROW","5.00"), messages: [ "expected 5 fields but found 3" ] }
    ], import.reload.failed_rows
  end

  test "a file that had failed rows can be uploaded again, and a fixed copy only adds the missing rows" do
    lines = file_fixture("td_chequing.csv").readlines
    broken = lines.dup.tap { |copy| copy[4] = %("2026-09-10","TOLU # 370","abc",,"2130.31"\n) }.join
    import_into(@chequing, csv_upload(broken, filename: "broken.csv"))

    again = import_into(@chequing, csv_upload(broken, filename: "broken.csv"))
    assert_equal [ 0, 70, 1 ], [ again.rows_imported, again.rows_skipped, again.rows_failed ]

    fixed = import_into(@chequing, csv_upload(lines.join, filename: "fixed.csv"))
    assert_equal [ 1, 70, 0 ], [ fixed.rows_imported, fixed.rows_skipped, fixed.rows_failed ]
    assert_equal BigDecimal("-981.80"), @chequing.transactions.sum(:amount)
  end

  test "asks to confirm the columns when many rows can't be read" do
    lines = file_fixture("td_chequing.csv").readlines
    (0..9).each { |index| lines[index] = lines[index].sub(/"\d+(\.\d+)?",,/, %("x",,)) }

    import = import_into(@chequing, csv_upload(lines.join, filename: "mostly_broken.csv"))

    assert import.pending?
    assert_equal 0, @chequing.transactions.count
  end

  # --- Uncertain formats ---

  test "keeps an uncertain file pending without importing anything" do
    import = nil
    assert_no_difference "Transaction.count" do
      import = import_into(@visa, fixture_upload("credit_card_signed.csv"))
    end

    assert import.pending?
    assert_equal [ "money_in", "heuristic" ], [ import.csv_schema.negative_means, import.schema_source ]
    assert_operator import.confidence, :<, CsvSchemaDetector::AUTO_IMPORT
    assert_equal file_fixture("credit_card_signed.csv").read, import.content
    assert_no_enqueued_jobs only: CategorizeImportJob
  end

  test "keeps a file it can't make sense of pending with no schema" do
    import = import_into(@chequing, fixture_upload("unknown_format.csv"))

    assert import.pending?
    assert_nil import.schema
    assert_equal 0, import.confidence
  end

  test "review: true asks to confirm even a file it recognizes" do
    import = TransactionCsvImporter.call(@chequing, fixture_upload("td_chequing.csv"), review: true, ai: nil)

    assert import.pending?
    assert_equal "heuristic", import.schema_source
  end

  test "a new upload replaces the account's earlier pending import, and expired ones are deleted" do
    earlier = import_into(@visa, fixture_upload("credit_card_signed.csv"))
    expired = create(:import, :pending, account: @chequing, created_at: 25.hours.ago)

    later = import_into(@visa, csv_upload(ambiguous_visa_csv, filename: "visa.csv"))

    assert later.pending?
    assert_not Import.exists?(earlier.id)
    assert_not Import.exists?(expired.id)
  end

  # --- Confirming ---

  test "confirming imports with the user's columns and remembers the layout for next time" do
    pending = import_into(@visa, csv_upload(ambiguous_visa_csv, filename: "visa.csv"))
    assert pending.pending?

    import = nil
    assert_enqueued_with job: CategorizeImportJob do
      import = TransactionCsvImporter.confirm(pending, visa_schema)
    end

    assert import.completed?, import.errors.full_messages.to_sentence
    assert_equal [ "user", 24, nil ], [ import.schema_source, import.rows_imported, import.reload.content ]

    next_export = import_into(@visa, csv_upload(ambiguous_visa_csv.lines.first(5).join, filename: "next.csv"))
    assert_equal [ "known", 0, 5 ], [ next_export.schema_source, next_export.rows_imported, next_export.rows_skipped ]
  end

  test "confirming twice imports once" do
    pending = import_into(@visa, csv_upload(ambiguous_visa_csv, filename: "visa.csv"))
    TransactionCsvImporter.confirm(pending, visa_schema)

    assert_no_difference [ "Transaction.count", "Import.count" ] do
      TransactionCsvImporter.confirm(Import.find(pending.id), visa_schema)
    end
    assert_equal 24, pending.reload.rows_imported
  end

  test "rejects confirmed columns that contradict a bank account's balances, or can't read the file, and keeps the import pending" do
    pending = TransactionCsvImporter.call(@chequing, fixture_upload("td_chequing.csv"), review: true, ai: nil)
    td_chequing = pending.csv_schema

    swapped = TransactionCsvImporter.confirm(pending, CsvSchema.new(td_chequing.to_h.merge(debit_column: 3, credit_column: 2)))
    assert_equal [ "The running balances show money in and money out the other way round." ], swapped.errors.full_messages

    unreadable = TransactionCsvImporter.confirm(Import.find(pending.id), CsvSchema.new(td_chequing.to_h.merge(date_format: "%m/%d/%Y")))
    assert_equal [ "None of the rows could be read with these columns." ], unreadable.errors.full_messages

    assert pending.reload.pending?
    assert_equal 0, @chequing.transactions.count
  end

  test "confirming a preview of a file that meanwhile finished importing elsewhere says it was already imported" do
    pending = TransactionCsvImporter.call(@chequing, fixture_upload("td_chequing.csv"), review: true, ai: nil)
    create(:import, account: @chequing, checksum: pending.checksum)

    import = nil
    assert_no_difference "Transaction.count" do
      import = TransactionCsvImporter.confirm(pending, pending.csv_schema)
    end

    assert import.reload.pending?
    assert_match(/was already imported into this account/, import.errors.full_messages.sole)
  end

  # --- Categorization ---

  test "categorizes only the new rows; an export of duplicates creates no work" do
    groceries = create(:category, name: "Groceries")
    create(:merchant, key: "KAFU SEMO AND _F", category: groceries)

    first = nil
    perform_enqueued_jobs { first = import_into(@chequing, fixture_upload("td_chequing.csv", lines: 0..9)) }
    transaction = @chequing.transactions.find_by!(transaction_date: Date.new(2026, 9, 9), amount: -130)
    assert_equal groceries, transaction.category
    assert_equal "KAFU SEMO AND   _F", transaction.description, "the raw description isn't changed by categorization"

    assert_no_enqueued_jobs only: CategorizeImportJob do
      assert_no_difference "Merchant.count" do
        import = import_into(@chequing, csv_upload(file_fixture("td_chequing.csv").readlines.first(10).reverse.join, filename: "again.csv"))
        assert_equal [ 0, 10 ], [ import.rows_imported, import.rows_skipped ]
      end
    end
    assert_equal 10, first.transactions.count
  end

  # --- Failures and races ---

  test "the AI being unavailable doesn't affect files it isn't needed for" do
    ai = Object.new.tap { |fake| def fake.detect(*, **) = raise(Errno::ECONNREFUSED) }

    assert TransactionCsvImporter.call(@chequing, fixture_upload("td_chequing.csv"), ai: ai).completed?
    assert TransactionCsvImporter.call(@visa, fixture_upload("credit_card_signed.csv"), ai: ai).pending?
  end

  test "saves nothing if importing fails partway" do
    importer = TransactionCsvImporter.new(@chequing)
    insert = importer.method(:insert)

    assert_no_difference [ "Import.count", "Transaction.count" ] do
      importer.stub(:insert, ->(*args) { insert.call(*args) && raise(ActiveRecord::StatementInvalid, "boom") }) do
        assert_raises(ActiveRecord::StatementInvalid) { importer.call(fixture_upload("td_chequing.csv")) }
      end
    end
  end

  test "treats a unique index violation from a concurrent upload of the same file as already imported" do
    content = file_fixture("td_chequing.csv").read
    create(:import, account: @chequing, checksum: Digest::SHA256.hexdigest(content))
    importer = TransactionCsvImporter.new(@chequing)

    import = nil
    assert_no_difference [ "Import.count", "Transaction.count" ] do
      importer.stub(:already_imported?, false) { import = importer.call(csv_upload(content, filename: "td_chequing.csv")) }
    end

    assert_not import.persisted?
    assert_match(/was already imported into this account/, import.errors.full_messages.sole)
  end

  {
    "an empty file" => [ "", "The file is empty." ],
    "only a header" => [ "date,description,amount\n", "The file has no transactions." ],
    "malformed CSV" => [ %(2026-09-01,"Loblaws,-54.32\n2026-09-02,Payroll,2500.00\n), "The file isn't valid CSV" ],
    "non-UTF-8 content" => [ "date,description,amount\n2026-09-01,Caf\xE9,-4.50\n".b, "The file must be UTF-8 text." ]
  }.each do |problem, (csv, message)|
    test "rejects a file with #{problem}" do
      import = nil
      assert_no_difference [ "Import.count", "Transaction.count" ] do
        import = import_into(@chequing, csv_upload(csv))
      end

      assert_not import.persisted?
      assert import.errors.full_messages.first.start_with?(message), import.errors.full_messages.to_sentence
    end
  end

  test "rejects a missing upload" do
    assert_equal [ "Choose a CSV file to import." ], import_into(@chequing, nil).errors.full_messages
  end

  test "rejects a file larger than 1 MB" do
    assert_equal [ "The file is larger than 1 MB." ], import_into(@chequing, csv_upload("date,description,amount\n" + "x" * 1.megabyte)).errors.full_messages
  end

  private
    def import_into(account, file)
      TransactionCsvImporter.call(account, file, ai: nil)
    end

    def visa_schema
      CsvSchema.new(date_column: 0, date_format: "%m/%d/%Y", description_column: 1, amount_strategy: "debit_credit", debit_column: 2, credit_column: 3, balance_column: 4)
    end
end
