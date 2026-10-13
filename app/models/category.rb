class Category < ApplicationRecord
  # Every user starts with these (User#add_default_categories). Uncategorized is a transaction
  # with no category, not a record. Misc is the catch-all for known expenses that don't fit another.
  DEFAULTS = {
    "income" => [ "Income" ],
    "expense" => [
      "Housing", "Groceries", "Restaurants & Dining", "Transportation", "Utilities", "Shopping",
      "Entertainment", "Health & Medical", "Personal Care", "Kids & Family", "Travel", "Education",
      "Gifts & Donations", "Fees & Charges", "Taxes", "Misc"
    ],
    "transfer" => [ "Transfer", "Credit Card Payment" ]
  }.freeze

  belongs_to :user
  has_many :transactions
  has_one :budget, dependent: :destroy
  has_many :merchants, dependent: :nullify

  # Transfer categories are money moving between your own accounts (including credit
  # card payments): they count as neither spending nor income and can't have a budget.
  enum :category_type, { expense: "expense", income: "income", transfer: "transfer" }, validate: true

  scope :budgetable, -> { where.not(category_type: "transfer") }

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true, uniqueness: { scope: :user_id, case_sensitive: false }
  validate :budgeted_category_is_not_a_transfer

  private
    def budgeted_category_is_not_a_transfer
      errors.add(:category_type, "can't be transfer while the category has a budget") if transfer? && budget
    end
end
