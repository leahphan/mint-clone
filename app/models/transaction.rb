class Transaction < ApplicationRecord
  belongs_to :account
  belongs_to :category, optional: true
  belongs_to :import, optional: true
  belongs_to :merchant, optional: true

  # How the category was set. Nil when uncategorized or set before this was tracked.
  enum :categorization_source, { learned: "learned", ai: "ai", manual: "manual" }, prefix: :categorized_by

  validates :transaction_date, :description, presence: true
  validates :amount, presence: true, numericality: true
  validate :category_and_merchant_belong_to_account_owner

  # Imported rows share a created_at, so id breaks the tie (rows are inserted oldest first).
  scope :newest_first, -> { order(transaction_date: :desc, created_at: :desc, id: :desc) }
  scope :spending, -> { where(amount: ...0) }
  scope :in_month, ->(date) { where(transaction_date: date.all_month) }

  # Money spent in the month containing `date`, per category name, largest first:
  # [["Groceries", 120.50], ["Uncategorized", 40.00]]. Amounts are positive.
  # Transfers between accounts aren't spending; uncategorized money out is.
  def self.spending_by_category(date)
    spending.in_month(date)
      .left_joins(:category)
      .where("categories.category_type IS DISTINCT FROM ?", "transfer")
      .group("categories.name")
      .sum(:amount)
      .map { |name, total| [ name || "Uncategorized", -total ] }
      .sort_by { |name, total| [ -total, name ] }
  end

  private
    def category_and_merchant_belong_to_account_owner
      return unless account

      errors.add(:category, "must be one of your categories") if category && category.user_id != account.user_id
      errors.add(:merchant, "must be one of your merchants") if merchant && merchant.user_id != account.user_id
    end
end
