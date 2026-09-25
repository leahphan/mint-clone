require "csv"

# Imports a CSV of date,description,amount rows into an account, all or nothing.
class TransactionCsvImporter
  HEADERS = %w[date description amount].freeze
  MAX_FILE_SIZE = 1.megabyte
  DATE_FORMAT = /\A\d{4}-\d{2}-\d{2}\z/
  # At most 10 digits before the decimal point, so values fit the numeric(12,2) column.
  AMOUNT_FORMAT = /\A-?\d{1,10}(\.\d{1,2})?\z/
  CHECKSUM_INDEX = "index_imports_on_account_id_and_checksum"

  def self.call(account, file)
    new(account, file).call
  end

  def initialize(account, file)
    @account = account
    @file = file
    @import = account.imports.build
  end

  # Returns the Import: persisted on success, otherwise carrying errors and row_errors.
  def call
    content = read_upload
    return import if errors.any?

    import.checksum = Digest::SHA256.hexdigest(content)
    if already_imported?
      add_already_imported_error
      return import
    end

    build_transactions(content)
    return import if errors.any?

    import.rows_imported = transactions.size
    save_import
    import
  end

  private
    attr_reader :account, :file, :import

    delegate :errors, :row_errors, :transactions, to: :import

    def read_upload
      if !file.respond_to?(:read)
        errors.add(:base, "Choose a CSV file to import.")
      elsif file.size > MAX_FILE_SIZE
        errors.add(:base, "The file is larger than 1 MB.")
      else
        import.filename = file.original_filename
        file.read
      end
    end

    # A fast, friendly check for the common case. The unique index on
    # [account_id, checksum] is what actually prevents duplicates.
    def already_imported?
      account.imports.exists?(checksum: import.checksum)
    end

    def build_transactions(content)
      text = content.dup.force_encoding(Encoding::UTF_8).delete_prefix("﻿")
      return errors.add(:base, "The file must be UTF-8 text.") unless text.valid_encoding?
      return errors.add(:base, "The file is empty.") if text.strip.empty?

      csv = CSV.new(text, skip_blanks: true)
      header = csv.shift.to_a.map { |name| name.to_s.strip.downcase }
      return errors.add(:base, "The first line must be the header: date,description,amount") unless header == HEADERS

      csv.each { |fields| build_transaction(fields, csv.lineno, csv.line.chomp) }

      if row_errors.any?
        errors.add(:base, "#{row_errors.size == 1 ? "1 row has" : "#{row_errors.size} rows have"} problems. " \
          "Nothing was imported. Fix them and upload the file again.")
      elsif transactions.empty?
        errors.add(:base, "The file has no transactions.")
      end
    rescue CSV::MalformedCSVError => error
      errors.add(:base, "The file isn't valid CSV: #{error.message}")
    end

    def build_transaction(fields, line, row)
      unless fields.size == HEADERS.size
        return add_row_error(line, row, [ "expected 3 fields (date, description, amount) but found #{fields.size}" ])
      end

      date, description, amount = fields.map { |field| field.to_s.strip }
      transaction_date = parse_date(date)
      valid_amount = amount.match?(AMOUNT_FORMAT)

      transaction = transactions.build(
        account: account,
        transaction_date: transaction_date,
        description: description,
        amount: (BigDecimal(amount) if valid_amount)
      )
      transaction.validate

      messages = []
      messages << %(date "#{date}" must be a real date in YYYY-MM-DD format) unless transaction_date
      messages << %(amount "#{amount}" must be a number like -54.32 or 2500.00) unless valid_amount
      messages += transaction.errors.reject { |error| error.attribute.in?(%i[transaction_date amount]) }.map(&:full_message)

      add_row_error(line, row, messages) if messages.any?
    end

    def add_row_error(line, row, messages)
      row_errors << { line: line, row: row, messages: messages }
    end

    def parse_date(value)
      Date.strptime(value, "%Y-%m-%d") if value.match?(DATE_FORMAT)
    rescue Date::Error
      nil
    end

    # Saves the import and its transactions in one database transaction.
    def save_import
      Import.transaction { import.save! }
    rescue ActiveRecord::RecordNotUnique => error
      raise unless error.message.include?(CHECKSUM_INDEX)

      add_already_imported_error
    end

    def add_already_imported_error
      previous = account.imports.find_by(checksum: import.checksum)
      imported_on = " on #{previous.created_at.to_date.to_fs(:long)}" if previous
      errors.add(:base, "#{import.filename} has already been imported into this account#{imported_on}.")
    end
end
