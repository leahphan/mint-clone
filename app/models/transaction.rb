class Transaction < ApplicationRecord
  belongs_to :account
  belongs_to :category, optional: true

  validates :transaction_date, :description, presence: true
  validates :amount, presence: true, numericality: true

  scope :newest_first, -> { order(transaction_date: :desc, created_at: :desc) }
end
