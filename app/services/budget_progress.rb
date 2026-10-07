# This month's progress for every budget, in two queries however many budgets there are.
# `actual` is the category's net activity for the month in the budget's direction, never below zero:
# money spent for an expense budget (refunds reduce it), money earned for an income budget (reversals reduce it).
class BudgetProgress
  Row = Data.define(:budget, :actual) do
    delegate :category, :amount, :income?, :expense?, to: :budget

    def remaining
      amount - actual
    end

    # :over_budget for an expense budget that's exceeded, :goal_met for an income goal that's reached, else :on_track.
    def status
      if income?
        actual >= amount ? :goal_met : :on_track
      else
        actual > amount ? :over_budget : :on_track
      end
    end

    # Not capped: 130 when 30% over.
    def percent_used
      (actual / amount * 100).round
    end

    # Width of the progress bar, which stops at full.
    def bar_percent
      [ percent_used, 100 ].min
    end
  end

  def self.call(month)
    new(month).call
  end

  def initialize(month)
    @month = month
  end

  def call
    budgets = Budget.by_category_name.to_a
    return [] if budgets.empty?

    net_by_category = Transaction.in_month(@month)
      .where(category_id: budgets.map(&:category_id))
      .group(:category_id)
      .sum(:amount)

    budgets.map do |budget|
      net = net_by_category.fetch(budget.category_id, 0)
      Row.new(budget: budget, actual: [ budget.income? ? net : -net, 0 ].max)
    end
  end
end
