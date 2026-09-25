class AccountsController < ApplicationController
  before_action :load_sidebar_accounts, only: %i[show]

  def index
    @accounts = Account.order(:name)
  end

  def show
    @account = Account.find(params[:id])
    @transactions = @account.transactions.includes(:category).newest_first
  end

  def new
    @account = Account.new
  end

  def create
    @account = Account.new(account_params)

    if @account.save
      redirect_to @account, notice: "Account created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def load_sidebar_accounts
      @sidebar_accounts = Account.order(:name)
    end

    def account_params
      params.expect(account: [ :name, :account_type ])
    end
end
