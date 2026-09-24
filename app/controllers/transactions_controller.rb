class TransactionsController < ApplicationController
  before_action :set_account

  def new
    @transaction = @account.transactions.build(transaction_date: Date.current)
  end

  def create
    @transaction = @account.transactions.build(transaction_params)

    if @transaction.save
      redirect_to @account, notice: "Transaction added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def set_account
      @account = Account.find(params[:account_id])
    end

    def transaction_params
      params.expect(transaction: [ :transaction_date, :description, :amount ])
    end
end
