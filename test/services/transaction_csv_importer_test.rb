require "test_helper"

class TransactionCsvImporterTest < ActiveSupport::TestCase
  VALID_CSV = <<~CSV
    date,description,amount
    2026-09-01,Loblaws,-54.32
    2026-09-02,Payroll,2500.00
  CSV

  setup do
    @account = create(:account)
  end

  test "imports every row with signed decimal amounts" do
    import = TransactionCsvImporter.call(@account, csv_upload(VALID_CSV))

    assert import.persisted?, import.errors.full_messages.to_sentence
    assert_equal 2, import.rows_imported
    assert_equal "transactions.csv", import.filename

    loblaws, payroll = @account.transactions.order(:transaction_date).to_a
    assert_equal [ Date.new(2026, 9, 1), "Loblaws", BigDecimal("-54.32"), import ],
      [ loblaws.transaction_date, loblaws.description, loblaws.amount, loblaws.import ]
    assert_equal [ Date.new(2026, 9, 2), "Payroll", BigDecimal("2500.00") ],
      [ payroll.transaction_date, payroll.description, payroll.amount ]
  end

  test "imports identical rows as separate transactions" do
    csv = "date,description,amount\n2026-09-03,Coffee,-4.50\n2026-09-03,Coffee,-4.50\n"

    assert_difference "Transaction.count", 2 do
      assert TransactionCsvImporter.call(@account, csv_upload(csv)).persisted?
    end
  end

  test "accepts a header with different case, spacing, and a byte-order mark, and skips blank lines" do
    csv = "\uFEFF Date , DESCRIPTION,Amount\n\n2026-09-01,Loblaws,-54.32\n\n"

    import = TransactionCsvImporter.call(@account, csv_upload(csv))
    assert import.persisted?, import.errors.full_messages.to_sentence
    assert_equal 1, import.rows_imported
  end

  {
    "an impossible date" => [ "2026-02-30,Rent,-1500.00", %(date "2026-02-30" must be a real date in YYYY-MM-DD format) ],
    "a non-ISO date" => [ "09/01/2026,Rent,-1500.00", %(date "09/01/2026" must be a real date in YYYY-MM-DD format) ],
    "more than two decimal places" => [ "2026-09-01,Rent,12.345", %(amount "12.345" must be a number like -54.32 or 2500.00) ],
    "a currency symbol" => [ "2026-09-01,Rent,$5", %(amount "$5" must be a number like -54.32 or 2500.00) ],
    "a thousands separator" => [ %(2026-09-01,Rent,"1,000.00"), %(amount "1,000.00" must be a number like -54.32 or 2500.00) ],
    "an amount too large to store" => [ "2026-09-01,Rent,12345678901.00", %(amount "12345678901.00" must be a number like -54.32 or 2500.00) ],
    "a blank description" => [ "2026-09-01,  ,-5.00", "Description can't be blank" ],
    "extra fields" => [ "2026-09-01,Loblaws,-54.32,extra", "expected 3 fields (date, description, amount) but found 4" ],
    "missing fields" => [ "2026-09-01,Loblaws", "expected 3 fields (date, description, amount) but found 2" ]
  }.each do |problem, (row, message)|
    test "rejects a row with #{problem}" do
      import = nil
      assert_no_difference [ "Import.count", "Transaction.count" ] do
        import = TransactionCsvImporter.call(@account, csv_upload("date,description,amount\n#{row}\n"))
      end

      assert_not import.persisted?
      assert_equal [ "1 row has problems. Nothing was imported. Fix them and upload the file again." ], import.errors.full_messages
      assert_equal [ { line: 2, row: row, messages: [ message ] } ], import.row_errors
    end
  end

  test "lists each problem separately, grouped by line" do
    csv = "date,description,amount\nnope,,abc\n2026-09-02,Payroll,2500.00\n2026-09-03,Coffee,4.555\n"
    import = TransactionCsvImporter.call(@account, csv_upload(csv))

    assert_equal [ "2 rows have problems. Nothing was imported. Fix them and upload the file again." ], import.errors.full_messages
    assert_equal [
      { line: 2, row: "nope,,abc", messages: [
        %(date "nope" must be a real date in YYYY-MM-DD format),
        %(amount "abc" must be a number like -54.32 or 2500.00),
        "Description can't be blank"
      ] },
      { line: 4, row: "2026-09-03,Coffee,4.555", messages: [ %(amount "4.555" must be a number like -54.32 or 2500.00) ] }
    ], import.row_errors
  end

  test "persists nothing when any row is invalid" do
    csv = "date,description,amount\n2026-09-01,Loblaws,-54.32\n2026-09-02,Payroll,2500.00\n2026-09-03,Broken,not-a-number\n"

    import = nil
    assert_no_difference [ "Import.count", "Transaction.count" ] do
      import = TransactionCsvImporter.call(@account, csv_upload(csv))
    end

    assert_not import.persisted?
    assert_equal [ 4 ], import.row_errors.pluck(:line)
  end

  {
    "a wrong header" => [ "when,what,how much\n2026-09-01,Loblaws,-54.32\n", "The first line must be the header: date,description,amount" ],
    "a header in a different order" => [ "description,date,amount\nLoblaws,2026-09-01,-54.32\n", "The first line must be the header: date,description,amount" ],
    "an empty file" => [ "", "The file is empty." ],
    "only a header" => [ "date,description,amount\n", "The file has no transactions." ],
    "malformed CSV" => [ %(date,description,amount\n2026-09-01,"Loblaws,-54.32\n), "The file isn't valid CSV" ],
    "non-UTF-8 content" => [ "date,description,amount\n2026-09-01,Caf\xE9,-4.50\n".b, "The file must be UTF-8 text." ]
  }.each do |problem, (csv, message)|
    test "rejects a file with #{problem}" do
      import = nil
      assert_no_difference [ "Import.count", "Transaction.count" ] do
        import = TransactionCsvImporter.call(@account, csv_upload(csv))
      end

      assert_not import.persisted?
      assert import.errors.full_messages.first.start_with?(message), import.errors.full_messages.to_sentence
    end
  end

  test "rejects a missing upload" do
    import = TransactionCsvImporter.call(@account, nil)

    assert_not import.persisted?
    assert_equal [ "Choose a CSV file to import." ], import.errors.full_messages
  end

  test "rejects a file larger than 1 MB" do
    import = TransactionCsvImporter.call(@account, csv_upload("date,description,amount\n" + "x" * 1.megabyte))

    assert_equal [ "The file is larger than 1 MB." ], import.errors.full_messages
  end

  test "rejects the same file uploaded to the same account again" do
    TransactionCsvImporter.call(@account, csv_upload(VALID_CSV))

    import = nil
    assert_no_difference [ "Import.count", "Transaction.count" ] do
      import = TransactionCsvImporter.call(@account, csv_upload(VALID_CSV))
    end

    assert_not import.persisted?
    assert_match(/\Atransactions\.csv has already been imported into this account on /, import.errors.full_messages.sole)
  end

  test "allows the same file to be imported into a different account" do
    TransactionCsvImporter.call(@account, csv_upload(VALID_CSV))

    assert TransactionCsvImporter.call(create(:account, name: "Joint Chequing"), csv_upload(VALID_CSV)).persisted?
  end

  test "treats a unique index violation from a concurrent upload as a duplicate" do
    # Another upload of the same file saved after this one passed the early check.
    create(:import, account: @account, checksum: Digest::SHA256.hexdigest(VALID_CSV))
    importer = TransactionCsvImporter.new(@account, csv_upload(VALID_CSV))

    import = nil
    assert_no_difference [ "Import.count", "Transaction.count" ] do
      importer.stub(:already_imported?, false) do
        import = importer.call
      end
    end

    assert_not import.persisted?
    assert_match(/has already been imported into this account/, import.errors.full_messages.sole)
  end
end
