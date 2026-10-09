require "test_helper"

class ImportsTest < ActionDispatch::IntegrationTest
  setup do
    @chequing = create(:account, name: "TD Chequing", account_type: "chequing")
    @visa = create(:account, name: "TD Visa", account_type: "credit_card")
  end

  test "imports a recognized export straight away and shows its transactions" do
    get new_account_import_path(@chequing)
    assert_response :success

    assert_difference "@chequing.transactions.count", 71 do
      post account_imports_path(@chequing), params: { file: fixture_upload("td_chequing.csv") }
    end

    assert_redirected_to account_path(@chequing)
    follow_redirect!
    assert_select "p", text: "Imported 71 transactions from td_chequing.csv."
    assert_select "td", text: /SOVU\/FUFU-PAY/
  end

  test "says when the same file was already imported" do
    post account_imports_path(@chequing), params: { file: fixture_upload("td_chequing.csv") }

    assert_no_difference "Transaction.count" do
      post account_imports_path(@chequing), params: { file: fixture_upload("td_chequing.csv") }
    end

    assert_response :unprocessable_entity
    assert_select "li", text: /\Atd_chequing\.csv was already imported into this account on /
  end

  test "reports skipped duplicates for an overlapping export" do
    post account_imports_path(@chequing), params: { file: fixture_upload("td_chequing.csv", lines: 0..48) }
    post account_imports_path(@chequing), params: { file: fixture_upload("td_chequing.csv", lines: 39..70) }

    follow_redirect!
    assert_select "p", text: "Imported 22 transactions from td_chequing.csv. Skipped 10 duplicates."
  end

  test "shows a summary with the rows that couldn't be imported" do
    lines = file_fixture("td_chequing.csv").readlines
    lines[4] = %("2026-09-10","TOLU # 370","abc",,"2130.31"\n)
    post account_imports_path(@chequing), params: { file: csv_upload(lines.join, filename: "with_errors.csv") }

    import = Import.last
    assert_redirected_to account_import_path(@chequing, import)
    follow_redirect!
    assert_select "h1", text: "Import summary"
    assert_select ".stat-strip", text: /Imported\s*70.*Skipped duplicates\s*0.*Possible duplicates\s*0.*Failed rows\s*1/m
    assert_select "tbody tr", text: /5.*"2026-09-10","TOLU # 370","abc",,"2130.31".*debit "abc" isn't a number/m
  end

  test "lists possible duplicates from a file without balances" do
    post account_imports_path(@chequing), params: { file: csv_upload("Date,Description,Amount\n2026-10-08,Starbucks,-6.25\n", filename: "first.csv") }
    post account_imports_path(@chequing), params: { file: csv_upload("Date,Description,Amount\n2026-10-08,Starbucks,-6.25\n2026-10-09,Payroll,2500.00\n", filename: "second.csv") }

    follow_redirect!
    assert_select ".stat-strip", text: /Possible duplicates\s*1/
    assert_select "td", text: "Starbucks"
    assert_equal 2, @chequing.transactions.where(description: "Starbucks").count

    get account_path(@chequing)
    assert_select "td", text: "StarbucksPossible duplicate", count: 1
  end

  test "previews an uncertain file, lets the user adjust the columns, and imports what they confirm" do
    assert_no_difference "Transaction.count" do
      post account_imports_path(@visa), params: { file: fixture_upload("credit_card_signed.csv") }
    end
    import = Import.last
    assert_redirected_to account_import_path(@visa, import)

    follow_redirect!
    assert_select "h1", text: "Check the columns"
    assert_select "select[name='schema[negative_means]'] option[selected]", text: /Money in/
    assert_select "td", text: "-$35.58"
    assert_select "td", text: "$500.00"

    get account_import_path(@visa, import), params: { schema: import.schema.merge("negative_means" => "money_out") }
    assert_select "td", text: "$35.58"
    assert_select "td", text: "-$500.00"

    assert_difference "@visa.transactions.count", 4 do
      patch account_import_path(@visa, import), params: { schema: import.schema }
    end
    assert_redirected_to account_path(@visa)
    assert_equal [ "user", nil ], [ import.reload.schema_source, import.content ]
    assert_equal BigDecimal("-35.58"), @visa.transactions.find_by!(description: "Online Store").amount

    post account_imports_path(@visa), params: { file: csv_upload("Date,Description,Amount\n09/30/2026,Bookstore,12.00\n", filename: "october.csv") }
    assert_redirected_to account_path(@visa)
    assert_equal BigDecimal("-12"), @visa.transactions.find_by!(description: "Bookstore").amount
  end

  test "points out dates that fit both MM/DD and DD/MM" do
    post account_imports_path(@visa), params: { file: csv_upload(ambiguous_visa_csv, filename: "visa.csv") }
    follow_redirect!

    assert_select "p", text: /fits both MM\/DD\/YYYY and DD\/MM\/YYYY/
    assert_select "select[name='schema[date_format]'] option[selected]", text: "MM/DD/YYYY"
  end

  test "asks for the columns of an unrecognized file and rejects a mapping that doesn't work" do
    post account_imports_path(@chequing), params: { file: fixture_upload("unknown_format.csv") }
    import = Import.last
    follow_redirect!

    assert_select "p", text: /We couldn't recognize this file's layout/
    assert_select "li", text: "Date column can't be blank"
    assert_select "button", text: /Import/, count: 0

    patch account_import_path(@chequing, import), params: { schema: { date_column: 0, date_format: "%Y-%m-%d", description_column: 1, amount_strategy: "signed", amount_column: 2 } }
    assert_response :unprocessable_entity
    assert_select "li", text: "None of the rows could be read with these columns."
    assert import.reload.pending?
  end

  test "the review checkbox shows the preview even for a recognized file" do
    post account_imports_path(@chequing), params: { file: fixture_upload("td_chequing.csv"), review: "1" }

    assert_redirected_to account_import_path(@chequing, Import.last)
    follow_redirect!
    assert_select "button", text: "Import 71 transactions"
  end

  test "discards a pending import" do
    post account_imports_path(@visa), params: { file: fixture_upload("credit_card_signed.csv") }
    import = Import.last

    delete account_import_path(@visa, import)

    assert_redirected_to account_path(@visa)
    assert_not Import.exists?(import.id)
  end

  test "an expired preview is deleted" do
    import = create(:import, :pending, account: @chequing, created_at: 25.hours.ago)

    get account_import_path(@chequing, import)

    assert_redirected_to new_account_import_path(@chequing)
    assert_not Import.exists?(import.id)
  end

  test "confirming an import that's already completed changes nothing" do
    import = create(:import, account: @chequing)

    assert_no_difference "Transaction.count" do
      patch account_import_path(@chequing, import), params: { schema: { date_column: 0 } }
    end
    assert_redirected_to account_import_path(@chequing, import)
  end

  test "shows an error when no file is chosen" do
    post account_imports_path(@chequing)

    assert_response :unprocessable_entity
    assert_select "li", text: "Choose a CSV file to import."
  end
end
