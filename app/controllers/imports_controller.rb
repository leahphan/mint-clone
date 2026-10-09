class ImportsController < ApplicationController
  PREVIEW_ROWS = 10
  MAX_FAILED_ROWS_SHOWN = 50

  before_action :set_account
  before_action :set_import, only: %i[show update destroy]

  def new
    @import = @account.imports.build
  end

  def create
    @import = TransactionCsvImporter.call(@account, params[:file], review: params[:review] == "1")

    if @import.persisted?
      redirect_after_import
    else
      render :new, status: :unprocessable_entity
    end
  end

  # The summary of a completed import, or the column preview of a pending one.
  # The preview's "Update preview" form submits here with schema params.
  def show
    if @import.pending?
      load_preview(params.key?(:schema) ? CsvSchema.new(schema_params) : @import.csv_schema || CsvSchema.new)
    else
      @possible_duplicates = @import.transactions.where(possible_duplicate: true).newest_first.to_a
    end
  end

  def update
    return redirect_to account_import_path(@account, @import) unless @import.pending?

    schema = CsvSchema.new(schema_params)
    @import = TransactionCsvImporter.confirm(@import, schema)

    if @import.completed?
      redirect_after_import
    else
      load_preview(schema)
      render :show, status: :unprocessable_entity
    end
  end

  def destroy
    @import.destroy! if @import.pending?
    redirect_to @account, notice: "Import discarded. Nothing was imported."
  end

  private
    def set_account
      @account = Account.find(params[:account_id])
    end

    def set_import
      @import = @account.imports.find(params[:id])
      return unless @import.expired?

      @import.destroy!
      redirect_to new_account_import_path(@account), alert: "That preview expired, so its file was deleted. Upload the file again."
    end

    def schema_params
      params.expect(schema: CsvSchema::ATTRIBUTES)
    end

    # Straight to the account when there's nothing to look at; otherwise to the import's summary.
    def redirect_after_import
      if @import.completed? && @import.rows_failed.zero? && !@import.transactions.exists?(possible_duplicate: true)
        redirect_to @account, notice: helpers.import_summary(@import)
      else
        redirect_to account_import_path(@account, @import)
      end
    end

    def load_preview(schema)
      @schema = schema
      @table = @import.table
      @problems = @schema.problems(@table)
      @transactions, @failures = @problems.empty? ? @schema.parse(@table) : [ [], [] ]
    end
end
