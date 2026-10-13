require "test_helper"

class DashboardTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
    sign_in_as @user
  end

  test "is the home page" do
    get root_path
    assert_response :success
    assert_select "p", text: "Let's get you set up"
  end

  test "shows accounts with balances, totals, recent transactions and this month's spending" do
    travel_to Date.new(2026, 9, 25) do
      chequing = create(:account, user: @user, name: "Everyday Chequing", account_type: "chequing")
      savings = create(:account, user: @user, name: "Rainy Day", account_type: "savings")
      visa = create(:account, user: @user, name: "Visa", account_type: "credit_card")
      groceries = create(:category, user: @user, name: "Groceries")

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
    account = create(:account, user: @user)
    12.times { |day| create(:transaction, account: account, transaction_date: Date.current - day) }

    get root_path
    assert_equal 10, css_select("tbody tr").size
  end

  test "totals include opening balances" do
    create(:account, user: @user, name: "Chequing", opening_balance: "1000.00")
    visa = create(:account, user: @user, name: "Visa", account_type: "credit_card", opening_balance: "-500.00")
    create(:transaction, account: visa, amount: "-120.50")

    get root_path

    summary = css_select("[aria-label='Financial summary']").first.text.squish
    assert_includes summary, "Credit card debt $620.50"
    assert_includes summary, "Net worth $379.50"
  end

  test "shows this month's progress for income and expense budgets" do
    travel_to Date.new(2026, 9, 25) do
      groceries = create(:category, user: @user, name: "Groceries")
      dining = create(:category, user: @user, name: "Dining")
      paycheque = create(:category, :income, user: @user, name: "Paycheque")
      freelance = create(:category, :income, user: @user, name: "Freelance")
      create(:budget, category: groceries, amount: "100.00")
      create(:budget, category: dining, amount: "40.00")
      create(:budget, category: paycheque, amount: "3000.00")
      create(:budget, category: freelance, amount: "500.00")
      account = create(:account, user: @user)
      create(:transaction, account: account, category: groceries, amount: "-100.00")
      create(:transaction, account: account, category: groceries, amount: "25.00") # refund
      create(:transaction, account: account, category: dining, amount: "-52.00")
      create(:transaction, account: account, category: paycheque, amount: "1200.00")
      create(:transaction, account: account, category: freelance, amount: "650.00")

      get root_path

      panel = css_select("section").find { |section| section.at_css("h2")&.text == "Budgets" }
      text = panel.text.squish
      assert_match(/Income .*Freelance.*Paycheque.* Expenses .*Dining.*Groceries/, text)
      assert_includes text, "Paycheque 40% $1,200.00 earned of $3,000.00 goal $1,800.00 to goal"
      assert_includes text, "Freelance 130% $650.00 earned of $500.00 goal Goal met"
      assert_includes text, "Groceries 75% $75.00 spent of $100.00 $25.00 remaining"
      assert_includes text, "Dining 130% $52.00 spent of $40.00 $12.00 over budget"

      assert_select "[role=progressbar][aria-valuetext='130% of goal'] .bg-mint-blue"
      assert_select "[role=progressbar][aria-valuetext='130% spent'] .bg-mint-negative"
      goal_met = panel.css("span").find { |span| span.text == "Goal met" }
      assert_includes goal_met["class"], "text-mint-green"
      assert_empty panel.css("li").select { |row| row.text.include?("Freelance") }.flat_map { |row| row.css(".text-mint-negative, .bg-mint-negative") }
    end
  end

  test "suggests creating a budget when there are none" do
    create(:account, user: @user)

    get root_path
    assert_select "a[href=?]", new_budget_path, text: "Create a budget"
  end

  test "loads in a fixed number of queries regardless of how many records exist" do
    2.times do |n|
      account = create(:account, user: @user, name: "Account #{n}", account_type: n.even? ? "chequing" : "credit_card")
      category = create(:category, user: @user)
      create(:budget, category: category)
      3.times { create(:transaction, account: account, category: category) }
    end
    # The signed-in session and its user, accounts with balances, spending by category, recent transactions
    # + their accounts and categories, budgets with their categories, and spending for all budgets.
    assert_queries_count(9) { get root_path }
  end
end
