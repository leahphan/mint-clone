class Account < ApplicationRecord
  has_many :transactions, dependent: :destroy
  has_many :imports, dependent: :destroy

  enum :account_type, {
    chequing: "chequing",
    savings: "savings",
    credit_card: "credit_card"
  }, validate: true

  GROUPS = {
    "Cash" => %w[chequing savings],
    "Credit Cards" => %w[credit_card]
  }.freeze

  validates :name, presence: true
  validates :opening_balance, numericality: true

  # Each account with a `balance` attribute (opening balance plus its transactions), in one query.
  scope :with_balances, -> {
    left_joins(:transactions)
      .group(:id)
      .select("accounts.*, accounts.opening_balance + COALESCE(SUM(transactions.amount), 0) AS balance")
  }

  # Groups already-loaded accounts for display, in GROUPS order: [["Cash", [...]], ["Credit Cards", [...]]].
  def self.grouped(accounts)
    accounts.group_by(&:group_name).sort_by { |group, _accounts| GROUPS.keys.index(group) }
  end

  def group_name
    GROUPS.find { |_name, types| types.include?(account_type) }&.first
  end

  def cash?
    group_name == "Cash"
  end

  # The opening balance plus the account's transactions. Uses the value from .with_balances when it was loaded.
  def balance
    has_attribute?(:balance) ? self[:balance] : opening_balance + transactions.sum(:amount)
  end
end
