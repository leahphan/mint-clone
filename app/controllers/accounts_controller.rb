class AccountsController < ApplicationController
  def index
    @accounts = Current.user.accounts.with_balances.order(:name).to_a
  end

  def show
    @account = Current.user.accounts.find(params[:id])
    @transactions = @account.transactions.includes(:category).newest_first
  end

  def new
    @account = Current.user.accounts.new
  end

  def create
    @account = Current.user.accounts.new(account_params)

    if @account.save
      redirect_to @account, notice: "Account created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @account = Current.user.accounts.find(params[:id])
  end

  def update
    @account = Current.user.accounts.find(params[:id])

    if @account.update(account_params)
      redirect_to @account, notice: "Account updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def account_params
      params.expect(account: [ :name, :account_type, :opening_balance ])
    end
end
