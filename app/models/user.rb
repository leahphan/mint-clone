class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  # A user's financial data. Reach records through these associations so one
  # user can never load another's (Current.user.accounts.find, not Account.find).
  has_many :accounts
  has_many :categories
  has_many :merchants
  has_many :transactions, through: :accounts
  has_many :budgets, through: :categories

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true

  # Adds the default categories this user doesn't have yet (matched by name, ignoring case).
  def add_default_categories
    Category::DEFAULTS.each do |category_type, names|
      names.each do |name|
        categories.where("LOWER(name) = LOWER(?)", name).first_or_create!(name: name, category_type: category_type)
      end
    end
  end
end
