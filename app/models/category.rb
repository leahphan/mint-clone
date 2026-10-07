class Category < ApplicationRecord
  has_many :transactions
  has_one :budget, dependent: :destroy

  enum :category_type, { expense: "expense", income: "income" }, validate: true

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true, uniqueness: { case_sensitive: false }
end
