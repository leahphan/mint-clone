require "test_helper"

class DashboardTest < ActionDispatch::IntegrationTest
  test "is the home page" do
    get root_path
    assert_response :success
    assert_select "p", text: "Let's get you set up"
  end

  test "shows accounts with balances, totals, recent transactions and this month's spending" do
    travel_to Date.new(2026, 9, 25) do
      chequing = create(:account, name: "Everyday Chequing", account_type: "chequing")
      savings = create(:account, name: "Rainy Day", account_type: "savings")
      visa = create(:account, name: "Visa", account_type: "credit_card")
      groceries = create(:category, name: "Groceries")

      create(:transaction, account: chequing, transaction_date: Date.new(2026, 9, 1), description: "Payroll", amount: "2500.00")
      create(:transaction, account: chequing, transaction_date: Date.new(2026, 9, 20), description: "Loblaws", amount: "-54.32", category: groceries)
      create(:transaction, account: savings, transaction_date: Date.new(2026, 9, 2), description: "Transfer in", amount: "1000.00")
      create(:transaction, account: visa, transaction_date: Date.new(2026, 9, 22), description: "Amazon", amount: "-450.00")

      get root_path

      sidebar = css_select("aside").first
      assert_includes sidebar.text, "Everyday Chequing"
      assert_includes sidebar.text, "$2,445.68"
      assert_includes sidebar.text, "$3,445.68" # Cash subtotal
      assert_includes sidebar.text, "-$450.00" # Credit Cards subtotal
      assert_select "aside a[href=?]", account_path(visa)

      summary = css_select("[aria-label='Financial summary']").first.text.squish
      assert_includes summary, "Cash $3,445.68"
      assert_includes summary, "Credit card debt $450.00"
      assert_includes summary, "Net worth $2,995.68"

      assert_equal [ "Amazon", "Loblaws", "Transfer in", "Payroll" ], css_select("tbody tr td:nth-child(2)").map(&:text)
      assert_select "tbody td a[href=?]", account_path(visa), text: "Visa"
      assert_select "tbody td", text: "Uncategorized"

      spending = css_select("section").find { |section| section.text.include?("Spending") }.text.squish
      assert_includes spending, "September 2026"
      assert_includes spending, "Uncategorized $450.00"
      assert_includes spending, "Groceries $54.32"
      assert_includes spending, "Total $504.32"
    end
  end

  test "shows at most 10 recent transactions" do
    account = create(:account)
    12.times { |day| create(:transaction, account: account, transaction_date: Date.current - day) }

    get root_path
    assert_equal 10, css_select("tbody tr").size
  end

  test "totals include opening balances" do
    create(:account, name: "Chequing", opening_balance: "1000.00")
    visa = create(:account, name: "Visa", account_type: "credit_card", opening_balance: "-500.00")
    create(:transaction, account: visa, amount: "-120.50")

    get root_path

    summary = css_select("[aria-label='Financial summary']").first.text.squish
    assert_includes summary, "Credit card debt $620.50"
    assert_includes summary, "Net worth $379.50"
  end

  test "loads in a fixed number of queries regardless of how many records exist" do
    2.times do |n|
      account = create(:account, name: "Account #{n}", account_type: n.even? ? "chequing" : "credit_card")
      category = create(:category)
      3.times { create(:transaction, account: account, category: category) }
    end
    # Accounts with balances, spending by category, recent transactions + their accounts and categories.
    assert_queries_count(5) { get root_path }
  end
end
