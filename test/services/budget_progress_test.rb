require "test_helper"

class BudgetProgressTest < ActiveSupport::TestCase
  setup do
    @user = create(:user)
    @account = create(:account, user: @user)
  end

  test "nets purchases and refunds in each budget's category for the month" do
    travel_to Date.new(2026, 9, 25) do
      groceries = create(:category, user: @user, name: "Groceries")
      dining = create(:category, user: @user, name: "Dining")
      rent = create(:category, user: @user, name: "Rent")
      other = create(:category, user: @user, name: "Other")
      create(:budget, category: groceries, amount: "100.00")
      create(:budget, category: dining, amount: "40.00")
      create(:budget, category: rent, amount: "1500.00")

      create(:transaction, account: @account, category: groceries, transaction_date: Date.new(2026, 9, 1), amount: "-100.00")
      create(:transaction, account: @account, category: groceries, transaction_date: Date.new(2026, 9, 30), amount: "25.00") # refund
      create(:transaction, account: @account, category: groceries, transaction_date: Date.new(2026, 8, 31), amount: "-999.00") # last month
      create(:transaction, account: @account, category: groceries, transaction_date: Date.new(2026, 10, 1), amount: "-999.00") # next month
      create(:transaction, account: @account, category: other, transaction_date: Date.new(2026, 9, 5), amount: "-999.00")
      create(:transaction, account: @account, category: nil, transaction_date: Date.new(2026, 9, 5), amount: "-999.00")
      create(:transaction, account: @account, category: dining, transaction_date: Date.new(2026, 9, 12), amount: "-52.00")

      progress = BudgetProgress.call(@user, Date.current)

      assert_equal [ "Dining", "Groceries", "Rent" ], progress.map { |row| row.category.name }
      dining_row, groceries_row, rent_row = progress

      assert_equal BigDecimal("75"), groceries_row.actual
      assert_equal BigDecimal("25"), groceries_row.remaining
      assert_equal 75, groceries_row.percent_used
      assert_equal :on_track, groceries_row.status

      assert_equal BigDecimal("52"), dining_row.actual
      assert_equal BigDecimal("-12"), dining_row.remaining
      assert_equal 130, dining_row.percent_used
      assert_equal 100, dining_row.bar_percent
      assert_equal :over_budget, dining_row.status

      assert_equal BigDecimal("0"), rent_row.actual
      assert_equal BigDecimal("1500"), rent_row.remaining
      assert_equal 0, rent_row.percent_used
    end
  end

  test "clamps expense spending at zero when refunds exceed purchases" do
    travel_to Date.new(2026, 9, 25) do
      budget = create(:budget, category: create(:category, user: @user), amount: "100.00")
      create(:transaction, account: @account, category: budget.category, amount: "-20.00")
      create(:transaction, account: @account, category: budget.category, amount: "50.00")

      progress = BudgetProgress.call(@user, Date.current).sole

      assert_equal BigDecimal("0"), progress.actual
      assert_equal BigDecimal("100"), progress.remaining
      assert_equal 0, progress.percent_used
    end
  end

  test "income budgets count net money in, with reversals reducing it" do
    travel_to Date.new(2026, 9, 25) do
      budget = create(:budget, category: create(:category, :income, user: @user, name: "Paycheque"), amount: "3000.00")
      create(:transaction, account: @account, category: budget.category, amount: "3000.00")
      create(:transaction, account: @account, category: budget.category, amount: "-200.00") # reversal
      create(:transaction, account: @account, category: budget.category, transaction_date: Date.new(2026, 8, 31), amount: "5000.00") # last month

      progress = BudgetProgress.call(@user, Date.current).sole

      assert_equal BigDecimal("2800"), progress.actual
      assert_equal BigDecimal("200"), progress.remaining
      assert_equal 93, progress.percent_used
      assert_equal :on_track, progress.status
    end
  end

  test "an income goal is met when reached or exceeded, which is not an error state" do
    travel_to Date.new(2026, 9, 25) do
      reached = create(:budget, category: create(:category, :income, user: @user, name: "Freelance"), amount: "500.00")
      exceeded = create(:budget, category: create(:category, :income, user: @user, name: "Paycheque"), amount: "3000.00")
      create(:transaction, account: @account, category: reached.category, amount: "500.00")
      create(:transaction, account: @account, category: exceeded.category, amount: "3600.00")

      reached_row, exceeded_row = BudgetProgress.call(@user, Date.current)

      assert_equal :goal_met, reached_row.status
      assert_equal BigDecimal("0"), reached_row.remaining
      assert_equal :goal_met, exceeded_row.status
      assert_equal BigDecimal("-600"), exceeded_row.remaining
      assert_equal 120, exceeded_row.percent_used
      assert_equal 100, exceeded_row.bar_percent
    end
  end

  test "clamps income at zero when reversals exceed money in" do
    travel_to Date.new(2026, 9, 25) do
      budget = create(:budget, category: create(:category, :income, user: @user), amount: "1000.00")
      create(:transaction, account: @account, category: budget.category, amount: "100.00")
      create(:transaction, account: @account, category: budget.category, amount: "-300.00")

      progress = BudgetProgress.call(@user, Date.current).sole

      assert_equal BigDecimal("0"), progress.actual
      assert_equal BigDecimal("1000"), progress.remaining
    end
  end

  test "direction follows the category type" do
    travel_to Date.new(2026, 9, 25) do
      income = create(:budget, category: create(:category, :income, user: @user, name: "Income"), amount: "100.00")
      expense = create(:budget, category: create(:category, user: @user, name: "Expense"), amount: "100.00")
      create(:transaction, account: @account, category: income.category, amount: "-40.00") # spending in an income category
      create(:transaction, account: @account, category: expense.category, amount: "40.00") # refund in an expense category

      progress = BudgetProgress.call(@user, Date.current)

      assert_equal [ BigDecimal("0"), BigDecimal("0") ], progress.map(&:actual)
    end
  end

  test "uses two queries for any mix of expense and income budgets" do
    3.times do |n|
      create(:budget, category: create(:category, user: @user, name: "Expense #{n}"))
      create(:budget, category: create(:category, :income, user: @user, name: "Income #{n}"))
    end
    @user.categories.find_each { |category| create(:transaction, account: @account, category: category) }

    assert_queries_count(2) { BudgetProgress.call(@user, Date.current).each(&:status) }
  end

  test "only includes the user's own budgets and transactions" do
    travel_to Date.new(2026, 9, 25) do
      budget = create(:budget, category: create(:category, user: @user, name: "Groceries"), amount: "100.00")
      create(:transaction, account: @account, category: budget.category, amount: "-30.00")
      other = create(:user)
      other_groceries = create(:category, user: other, name: "Groceries")
      create(:budget, category: other_groceries, amount: "999.00")
      create(:transaction, account: create(:account, user: other), category: other_groceries, amount: "-500.00")

      progress = BudgetProgress.call(@user, Date.current)

      assert_equal [ [ budget, BigDecimal("30") ] ], progress.map { |row| [ row.budget, row.actual ] }
    end
  end

  test "is empty without budgets" do
    assert_equal [], BudgetProgress.call(@user, Date.current)
  end
end
