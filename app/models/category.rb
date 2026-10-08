class Category < ApplicationRecord
  has_many :transactions
  has_one :budget, dependent: :destroy
  has_many :merchants, dependent: :nullify

  # Transfer categories are money moving between your own accounts (including credit
  # card payments): they count as neither spending nor income and can't have a budget.
  enum :category_type, { expense: "expense", income: "income", transfer: "transfer" }, validate: true

  scope :budgetable, -> { where.not(category_type: "transfer") }

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validate :budgeted_category_is_not_a_transfer

  private
    def budgeted_category_is_not_a_transfer
      errors.add(:category_type, "can't be transfer while the category has a budget") if transfer? && budget
    end
end
