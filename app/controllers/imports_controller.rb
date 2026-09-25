class ImportsController < ApplicationController
  before_action :set_account

  def new
    @import = @account.imports.build
  end

  def create
    @import = TransactionCsvImporter.call(@account, params[:file])

    if @import.persisted?
      redirect_to @account, notice: "Imported #{helpers.pluralize(@import.rows_imported, "transaction")} from #{@import.filename}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def set_account
      @account = Account.find(params[:account_id])
    end
end
