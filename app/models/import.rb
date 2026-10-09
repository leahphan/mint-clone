class Import < ApplicationRecord
  # How long an upload waiting for the user to confirm its columns (and its CSV) is kept.
  PENDING_TTL = 24.hours
  MAX_FAILED_ROWS = 100

  belongs_to :account
  has_many :transactions

  enum :status, { pending: "pending", completed: "completed" }, default: :completed, validate: true
  # Where the schema came from: a layout imported before, the heuristics, the AI, or the user.
  enum :schema_source, { known: "known", heuristic: "heuristic", ai: "ai", user: "user" }, prefix: :schema_from, validate: { allow_nil: true }

  # The uploaded CSV never appears in inspect output or logs.
  self.filter_attributes += [ :content ]

  validates :filename, :checksum, presence: true
  validates :content, presence: true, if: :pending?
  validates :rows_imported, :rows_skipped, :rows_failed, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :expired, -> { pending.where(created_at: ...PENDING_TTL.ago) }

  # Deletes abandoned pending imports with their uploaded CSV. Returns how many.
  def self.purge_expired
    expired.delete_all
  end

  def expired?
    pending? && created_at < PENDING_TTL.ago
  end

  def csv_schema
    CsvSchema.from_h(schema) if schema
  end

  def table
    CsvTable.new(content)
  end

  # Rows that couldn't be read: [{ "line" =>, "row" =>, "messages" => [...] }].
  def failed_rows
    super.map { |failure| failure.symbolize_keys }
  end
end
