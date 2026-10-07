class Budget < ApplicationRecord
  belongs_to :category

  delegate :category_type, :income?, :expense?, to: :category

  validates :amount, numericality: { greater_than: 0 }
  validates :category_id, uniqueness: true

  scope :by_category_name, -> { eager_load(:category).order("categories.name") }
end
