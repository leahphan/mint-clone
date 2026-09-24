class Account < ApplicationRecord
  has_many :transactions, dependent: :destroy

  enum :account_type, {
    chequing: "chequing",
    savings: "savings",
    credit_card: "credit_card"
  }, validate: true

  validates :name, presence: true
end
