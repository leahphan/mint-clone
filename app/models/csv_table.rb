require "csv"

# An uploaded CSV file as rows of fields: its delimiter, header row (if it has
# one), and data rows with their line numbers. The fingerprint identifies the
# file's layout, never its contents, so the next export from the same bank
# matches it.
class CsvTable
  # A problem with the whole file, with a message for the user.
  class Error < StandardError; end

  Row = Data.define(:line, :fields, :text)

  DELIMITERS = [ ",", ";", "\t", "|" ].freeze
  SNIFF_RECORDS = 20
  MIN_COLUMNS = 3

  attr_reader :delimiter, :header, :rows, :column_count

  def self.parse(content)
    new(decode(content))
  end

  def self.decode(content)
    text = content.to_s.dup.force_encoding(Encoding::UTF_8).delete_prefix("﻿")
    raise Error, "The file must be UTF-8 text." unless text.valid_encoding?
    raise Error, "The file is empty." if text.strip.empty?

    text
  end

  # "Transaction Date" => "transaction date", "Amount ($)" => "amount", "CAD$" => "cad"
  def self.normalize_header(name)
    name.to_s.downcase.gsub(/\(.*?\)/, " ").gsub(/[^a-z0-9]+/, " ").squish
  end

  def initialize(text)
    @delimiter, @column_count = sniff_delimiter(text)
    records = read_records(text)
    @header = records.shift.fields.map { |name| name.to_s.strip } if starts_with_header?(records)
    @rows = records
  rescue CSV::MalformedCSVError => error
    raise Error, "The file isn't valid CSV: #{error.message}"
  end

  def header?
    header.present?
  end

  def normalized_header
    header&.map { |name| self.class.normalize_header(name) }
  end

  # The cells of one column across the data rows (nil where a row is too short).
  def values(column)
    rows.map { |row| row.fields[column] }
  end

  # The layout: delimiter, column count, header names, and each column's kind of
  # value. A money column that happens to be empty in one export counts as money,
  # so the fingerprint doesn't change when, say, there were no deposits.
  def fingerprint
    shapes = (0...column_count).map { |column| shape(values(column)) }
    Digest::SHA256.hexdigest(JSON.generate([ "v1", delimiter, column_count, normalized_header, shapes ]))
  end

  private
    # The delimiter that splits the first records into the most consistent number of fields.
    def sniff_delimiter(text)
      malformed = nil
      candidates = DELIMITERS.filter_map do |delimiter|
        counts = sample_field_counts(text, delimiter)
      rescue CSV::MalformedCSVError => error
        malformed ||= error
        next
      else
        next if counts.empty?

        count, frequency = counts.tally.max_by { |field_count, times| [ times, field_count ] }
        [ delimiter, count, frequency.fdiv(counts.size) ] if count >= MIN_COLUMNS
      end
      raise malformed if candidates.empty? && malformed
      raise Error, "We couldn't find the columns in this file. It needs at least #{MIN_COLUMNS} (date, description and amount)." if candidates.empty?

      delimiter, count, _share = candidates.max_by.with_index { |(_, _, share), index| [ share, -index ] }
      [ delimiter, count ]
    end

    def sample_field_counts(text, delimiter)
      CSV.new(text, col_sep: delimiter).lazy.reject { |fields| blank_record?(fields) }.first(SNIFF_RECORDS).map(&:size)
    end

    # Rows with their physical line numbers (a quoted field can span lines), skipping blank lines.
    def read_records(text)
      csv = CSV.new(text, col_sep: delimiter)
      line = 1
      records = []
      csv.each do |fields|
        raw = csv.line.to_s
        records << Row.new(line: line, fields: fields, text: raw.chomp) unless blank_record?(fields)
        line += [ raw.count("\n"), 1 ].max
      end
      records
    end

    # A header is a first row of names (no dates or amounts), followed by a row of data if there is one.
    def starts_with_header?(records)
      first, second = records.first(2)
      return false unless first

      first.fields.none? { |value| date_or_money?(value) } && first.fields.any? { |value| value.to_s.match?(/\p{L}/) } &&
        (second.nil? || second.fields.any? { |value| date_or_money?(value) })
    end

    def blank_record?(fields)
      fields.all? { |value| CsvSchema.blank_value?(value) }
    end

    def date_or_money?(value)
      return false if CsvSchema.blank_value?(value)

      CsvSchema.date_formats_for(value).any? || CsvSchema.parse_money(value).present?
    end

    def shape(values)
      present = values.reject { |value| CsvSchema.blank_value?(value) }
      if present.empty? || present.all? { |value| CsvSchema.parse_money(value) }
        "money"
      elsif present.all? { |value| CsvSchema.date_formats_for(value).any? }
        sample = present.first.strip
        "date:#{sample[/\D/]}:#{sample.match?(/\A\d{4}/) ? "year-first" : "year-last"}"
      else
        "text"
      end
    end
end
