class Import < ApplicationRecord
  belongs_to :account
  has_many :transactions

  validates :filename, :checksum, presence: true
  validates :rows_imported, numericality: { only_integer: true, greater_than: 0 }

  # Problems found in individual CSV rows: [{ line:, row:, messages: [...] }].
  # Filled in by TransactionCsvImporter; not stored.
  def row_errors
    @row_errors ||= []
  end
end
