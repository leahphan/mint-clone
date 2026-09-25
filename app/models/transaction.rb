class Transaction < ApplicationRecord
  belongs_to :account
  belongs_to :category, optional: true
  belongs_to :import, optional: true

  validates :transaction_date, :description, presence: true
  validates :amount, presence: true, numericality: true

  scope :newest_first, -> { order(transaction_date: :desc, created_at: :desc) }
  scope :spending, -> { where(amount: ...0) }
  scope :in_month, ->(date) { where(transaction_date: date.all_month) }

  # Money spent in the month containing `date`, per category name, largest first:
  # [["Groceries", 120.50], ["Uncategorized", 40.00]]. Amounts are positive.
  def self.spending_by_category(date)
    spending.in_month(date)
      .left_joins(:category)
      .group("categories.name")
      .sum(:amount)
      .map { |name, total| [ name || "Uncategorized", -total ] }
      .sort_by { |name, total| [ -total, name ] }
  end
end
