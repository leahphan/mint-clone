class Budget < ApplicationRecord
  belongs_to :category

  delegate :category_type, :income?, :expense?, to: :category

  validates :amount, numericality: { greater_than: 0 }
  validates :category_id, uniqueness: true
  validate :category_is_budgetable

  scope :by_category_name, -> { eager_load(:category).order("categories.name") }

  private
    def category_is_budgetable
      errors.add(:category, "can't be a transfer category") if category&.transfer?
    end
end
