module ImportsHelper
  # "Imported 27 transactions from x.csv. Skipped 11 duplicates. 2 possible duplicates to check. 1 row couldn't be imported."
  def import_summary(import)
    possible_duplicates = import.transactions.where(possible_duplicate: true).count
    [
      import.rows_imported.zero? ? "No new transactions in #{import.filename}." : "Imported #{pluralize(import.rows_imported, "transaction")} from #{import.filename}.",
      ("Skipped #{pluralize(import.rows_skipped, "duplicate")}." if import.rows_skipped.positive?),
      ("#{pluralize(possible_duplicates, "possible duplicate")} to check." if possible_duplicates.positive?),
      ("#{pluralize(import.rows_failed, "row")} couldn't be imported." if import.rows_failed.positive?)
    ].compact.join(" ")
  end

  # Options for choosing a column: its header (or position) and a sample value.
  def column_options(table)
    (0...table.column_count).map do |column|
      name = table.header&.at(column).presence || "Column #{column + 1}"
      sample = table.values(column).find { |value| !CsvSchema.blank_value?(value) }.to_s.strip.truncate(24)
      [ sample.empty? ? name : %(#{name} – "#{sample}"), column ]
    end
  end

  def date_format_options
    CsvSchema::DATE_FORMAT_LABELS.map { |format, label| [ label, format ] }
  end

  # True when every date in the column fits both MM/DD and DD/MM.
  def ambiguous_dates?(table, schema)
    return false unless schema.date_column && schema.date_column < table.column_count

    dates = table.values(schema.date_column).reject { |value| CsvSchema.blank_value?(value) }
    dates.any? && dates.all? { |value| (CsvSchema.date_formats_for(value) & %w[%m/%d/%Y %d/%m/%Y]).size == 2 }
  end
end
