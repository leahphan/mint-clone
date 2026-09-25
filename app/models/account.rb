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

  # Accounts grouped for display, in GROUPS order: [["Cash", [...]], ["Credit Cards", [...]]].
  def self.grouped
    all.group_by(&:group_name).sort_by { |group, _accounts| GROUPS.keys.index(group) }
  end

  def group_name
    GROUPS.find { |_name, types| types.include?(account_type) }&.first
  end
end
