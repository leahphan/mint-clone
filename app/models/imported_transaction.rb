# One CSV row, parsed with a CsvSchema. amount uses the app's sign convention
# (negative is money out); debit and credit are the positive money out and in;
# source_balance is the running balance as the bank printed it; source_row is
# the row's cells as they appeared in the file.
ImportedTransaction = Data.define(:line, :date, :raw_description, :amount, :debit, :credit, :source_balance, :source_row) do
  # Source fingerprints for a file's transactions, in the same order. They identify each
  # row by its source data so that importing it again is recognized as a duplicate:
  #
  # - With a running balance: date, amount and balance identify a row in any export of
  #   the account, so overlapping exports dedupe.
  # - Without one: date, amount and description can't tell a repeat purchase from the
  #   same purchase in another export, so the fingerprint includes the file's checksum
  #   and only dedupes re-imports of the same file.
  #
  # Identical rows in one file are numbered, so they stay separate transactions.
  def self.fingerprints(transactions, checksum:)
    occurrences = Hash.new(0)

    transactions.map do |transaction|
      key = transaction.source_key(checksum)
      occurrences[key] += 1
      Digest::SHA256.hexdigest(JSON.generate([ "v1", *key, occurrences[key] ]))
    end
  end

  # Amounts in cents, so 20, 20.0 and 20.00 are the same.
  def self.cents(amount)
    (amount * 100).to_i.to_s
  end

  # What another transaction must share to possibly be the same one: date, amount and description.
  def self.match_key(date, amount, description)
    [ date.iso8601, cents(amount), description.to_s.squish.upcase ]
  end

  def source_key(checksum)
    if source_balance
      [ "balance", date.iso8601, self.class.cents(amount), self.class.cents(source_balance) ]
    else
      [ "file", checksum, *match_key ]
    end
  end

  def match_key
    self.class.match_key(date, amount, raw_description)
  end
end
