class DashboardController < ApplicationController
  RECENT_TRANSACTIONS_LIMIT = 10

  def index
    @accounts = Current.user.accounts.with_balances.order(:name).to_a
    @account_groups = Account.grouped(@accounts)

    @cash_total = @accounts.select(&:cash?).sum(0, &:balance)
    @credit_card_debt = -@accounts.select(&:credit_card?).sum(0, &:balance)
    @net_worth = @accounts.sum(0, &:balance)

    @recent_transactions = Current.user.transactions.includes(:account, :category).newest_first.limit(RECENT_TRANSACTIONS_LIMIT).to_a
    @spending_month = Date.current
    @spending_by_category = Current.user.transactions.spending_by_category(@spending_month)
    @budget_progress = BudgetProgress.call(Current.user, @spending_month)
  end
end
