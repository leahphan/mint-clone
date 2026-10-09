# Imports a bank's CSV export into an account. The file's layout is worked out
# once (CsvSchemaDetector), then every row is parsed in Ruby (CsvSchema). When
# the layout is certain the file is imported straight away; otherwise it's saved
# as a pending Import for the user to check the columns, and .confirm imports it.
#
# Rows that were imported before are skipped (see ImportedTransaction.fingerprints).
# Rows without a running balance that match an existing transaction are imported
# but flagged as possible duplicates, so a real repeat purchase is never dropped.
# Rows that can't be read are recorded on the import; the rest still import.
# Only new transactions are categorized.
class TransactionCsvImporter
  MAX_FILE_SIZE = 1.megabyte
  CHECKSUM_INDEX = "index_imports_on_account_id_and_checksum_completed"
  INSERT_BATCH_SIZE = 1_000

  def self.call(account, file, review: false, ai: CsvSchemaDetector.default_ai)
    new(account).call(file, review: review, ai: ai)
  end

  # Imports a pending import with the columns the user confirmed. Returns it completed, or with errors.
  def self.confirm(import, schema)
    new(import.account).confirm(import, schema)
  end

  def initialize(account)
    @account = account
  end

  # Returns the Import: completed, pending (columns to confirm), or unsaved with errors.
  # review: true always asks the user to confirm the columns first.
  def call(file, review: false, ai: nil)
    Import.purge_expired
    import = account.imports.build
    text = read_upload(import, file)
    return import if import.errors.any?

    import.checksum = Digest::SHA256.hexdigest(text)
    return add_already_imported_error(import) if already_imported?(import)

    table = parse_table(import, text)
    return import if import.errors.any?

    detection = CsvSchemaDetector.call(table, account: account, ai: ai)
    if detection.confidence >= CsvSchemaDetector::AUTO_IMPORT && !review
      import_rows(import) { complete(import, table, detection.schema, source: detection.source, confidence: detection.confidence) }
    else
      account.with_lock { save_pending(import, table, text, detection) }
    end
    import
  end

  def confirm(import, schema)
    import_rows(import) do
      import.lock!
      next false unless import.pending? # already confirmed, e.g. by a double submit

      table = import.table
      detector = CsvSchemaDetector.new(table, account)
      problems = schema.problems(table).presence || [ detector.contradiction(schema) ].compact
      if problems.any?
        problems.each { |problem| import.errors.add(:base, problem) }
        next false
      end

      complete(import, table, schema, source: "user", confidence: detector.confidence(schema))
    end
    import
  end

  private
    attr_reader :account

    def read_upload(import, file)
      if !file.respond_to?(:read)
        import.errors.add(:base, "Choose a CSV file to import.")
      elsif file.size > MAX_FILE_SIZE
        import.errors.add(:base, "The file is larger than 1 MB.")
      else
        import.filename = file.original_filename
        CsvTable.decode(file.read)
      end
    rescue CsvTable::Error => error
      import.errors.add(:base, error.message)
    end

    def parse_table(import, text)
      table = CsvTable.new(text)
      table.rows.empty? ? import.errors.add(:base, "The file has no transactions.") : table
    rescue CsvTable::Error => error
      import.errors.add(:base, error.message)
    end

    # A fast, friendly check for the common case. The partial unique index on
    # [account_id, checksum] is what actually prevents importing a file twice.
    # A file that had rows that couldn't be read can be imported again.
    def already_imported?(import)
      completed_imports_of(import).exists?
    end

    def completed_imports_of(import)
      account.imports.completed.where(checksum: import.checksum, rows_failed: 0)
    end

    def add_already_imported_error(import)
      previous = completed_imports_of(import).order(:created_at).first
      imported_on = " on #{previous.created_at.to_date.to_fs(:long)}" if previous
      import.errors.add(:base, "#{import.filename} was already imported into this account#{imported_on}.")
      import
    end

    # A new upload replaces any earlier preview, so at most one uploaded CSV waits per account.
    def save_pending(import, table, text, detection)
      account.imports.pending.delete_all
      import.update!(status: :pending, content: text, schema: detection.schema&.to_h, schema_source: detection.source,
        confidence: detection.confidence, format_fingerprint: table.fingerprint, rows_imported: 0)
    end

    # Runs the block holding the account's lock (so imports into one account don't interleave), then
    # categorizes the new transactions. The block returns whether it imported.
    def import_rows(import)
      imported = account.with_lock { yield }
      CategorizeImportJob.perform_later(import) if imported && import.rows_imported.positive?
    rescue ActiveRecord::RecordNotUnique => error
      raise unless error.message.include?(CHECKSUM_INDEX)

      # The same file finished importing in another request meanwhile.
      import.reload if import.persisted?
      add_already_imported_error(import)
    end

    def complete(import, table, schema, source:, confidence:)
      transactions, failures = schema.parse(table)
      import.update!(status: :completed, content: nil, schema: schema.to_h, schema_source: source, confidence: confidence,
        format_fingerprint: table.fingerprint, rows_failed: failures.size, failed_rows: failures.first(Import::MAX_FAILED_ROWS),
        rows_imported: 0, rows_skipped: 0)

      inserted = insert(import, transactions)
      import.update!(rows_imported: inserted, rows_skipped: transactions.size - inserted)
      true
    end

    # Inserts the transactions oldest first, skipping any whose source fingerprint this account already has.
    # Returns how many were inserted.
    def insert(import, transactions)
      fingerprints = ImportedTransaction.fingerprints(transactions, checksum: import.checksum)
      existing = existing_match_keys(transactions)

      rows = chronological(transactions.zip(fingerprints)).map do |transaction, fingerprint|
        {
          account_id: account.id, import_id: import.id, transaction_date: transaction.date, description: transaction.raw_description,
          amount: transaction.amount, source_fingerprint: fingerprint, source_row: transaction.source_row,
          possible_duplicate: transaction.source_balance.nil? && existing.include?(transaction.match_key)
        }
      end
      rows.each_slice(INSERT_BATCH_SIZE).sum do |batch|
        Transaction.insert_all(batch, unique_by: %i[account_id source_fingerprint], returning: %w[id]).length
      end
    end

    # Without a running balance, a row can't be told apart from an identical transaction already in the account,
    # so those get flagged. Returns the match keys of the account's transactions on the dates of such rows.
    def existing_match_keys(transactions)
      dates = transactions.reject(&:source_balance).map(&:date).uniq
      return Set.new if dates.empty?

      account.transactions.where(transaction_date: dates).pluck(:transaction_date, :amount, :description)
        .to_set { |date, amount, description| ImportedTransaction.match_key(date, amount, description) }
    end

    # [transaction, fingerprint] pairs oldest first, keeping the bank's order within a day.
    def chronological(pairs)
      newest_first = pairs.map { |transaction, _| transaction.date }.each_cons(2).all? { |a, b| a >= b }
      ordered = newest_first ? pairs.reverse : pairs
      ordered.sort_by.with_index { |(transaction, _), index| [ transaction.date, index ] }
    end
end
