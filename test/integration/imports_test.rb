require "test_helper"

class ImportsTest < ActionDispatch::IntegrationTest
  setup do
    @account = create(:account)
  end

  test "imports a CSV and shows the imported transactions" do
    get new_account_import_path(@account)
    assert_response :success

    csv = "date,description,amount\n2026-09-01,Loblaws,-54.32\n2026-09-02,Payroll,2500.00\n"
    assert_difference "@account.transactions.count", 2 do
      post account_imports_path(@account), params: { file: csv_upload(csv, filename: "september.csv") }
    end

    assert_redirected_to account_path(@account)
    follow_redirect!
    assert_select "p", text: "Imported 2 transactions from september.csv."
    assert_equal [ "Payroll", "Loblaws" ], css_select("tbody tr td:nth-child(2)").map(&:text)
    assert_select "td", text: "-$54.32"
  end

  test "shows the errors and imports nothing when a row is invalid" do
    csv = "date,description,amount\n2026-09-01,Loblaws,-54.32\n2026-09-02,,2500.00\nnope,Coffee,abc\n"

    assert_no_difference [ "Import.count", "Transaction.count" ] do
      post account_imports_path(@account), params: { file: csv_upload(csv) }
    end

    assert_response :unprocessable_entity
    assert_select "li", text: "2 rows have problems. Nothing was imported. Fix them and upload the file again."

    rows = css_select("table tbody tr")
    assert_equal [ "3", "4" ], rows.map { |row| row.at_css("td:nth-child(1)").text }
    assert_equal [ "2026-09-02,,2500.00", "nope,Coffee,abc" ], rows.map { |row| row.at_css("td:nth-child(2)").text }
    assert_equal [ "Description can't be blank" ], rows[0].css("td:nth-child(3) li").map(&:text)
    assert_equal [ %(date "nope" must be a real date in YYYY-MM-DD format), %(amount "abc" must be a number like -54.32 or 2500.00) ],
      rows[1].css("td:nth-child(3) li").map(&:text)
  end

  test "shows an error when no file is chosen" do
    post account_imports_path(@account)

    assert_response :unprocessable_entity
    assert_select "li", text: "Choose a CSV file to import."
  end
end
