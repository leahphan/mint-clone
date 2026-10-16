# One user's merchant, identified by a normalized key from their transaction
# descriptions. Its category is the user's learned one: their future
# transactions from it get that category. Merchants are private to their user,
# because descriptions can hold personal details such as e-transfer names, so
# always reach them through user.merchants. The raw description stays on each
# Transaction; the key and name here are the normalized identity.
class Merchant < ApplicationRecord
  # Card processors that put their own name before the merchant's: "SQ *PILOT COFFEE".
  PROCESSOR_PREFIX = /\A(?:SQ|TST|PAYPAL|PP)\s*\*\s*/

  belongs_to :user
  has_many :transactions
  # The database requires the category to be one of the same user's.
  belongs_to :category, optional: true

  # Uniqueness per user is enforced by the unique index on [user_id, key] (see for_description).
  validates :key, :name, presence: true

  # A conservative normalized key for a description; when unsure it keeps the
  # text, so distinct merchants aren't merged.
  #   "PAYPAL *NETFLIX.COM"           => "NETFLIX"
  #   "UBER *TRIP HELP.UBER.COM"      => "UBER"
  #   "COSTCO WHOLESALE #123 TORONTO" => "COSTCO WHOLESALE"
  def self.key_for(description)
    text = description.to_s.upcase.squish
    key = text.match?(PROCESSOR_PREFIX) ? text.sub(PROCESSOR_PREFIX, "") : text.split("*").first.to_s
    key = key.sub(/\s*#\d.*\z/, "")
    key = key.sub(/\A(\S+)\.(?:COM|CA|NET)\b/, '\1')
    key.squish.presence || text
  end

  # The user's merchant for a description, created if new. Call it on a user's merchants:
  # user.merchants.for_description("SQ *PILOT COFFEE").
  def self.for_description(description)
    key = key_for(description)
    create_or_find_by!(key: key) { |merchant| merchant.name = display_name_for(key) }
  end

  # "7-ELEVEN" => "7-Eleven"
  def self.display_name_for(key)
    key.downcase.gsub(/(?<![\w'])[a-z]/, &:upcase)
  end

  # [merchant key prefix, default category name] pairs from config/starter_merchants.yml, longest
  # prefix first so "CANADIAN TIRE GAS" wins over "CANADIAN TIRE".
  STARTER_CATEGORIES = YAML.load_file(Rails.root.join("config/starter_merchants.yml"))
    .flat_map { |category_name, prefixes| prefixes.map { |prefix| [ prefix, category_name ] } }
    .sort_by { |prefix, _category_name| -prefix.length }
    .freeze

  # The usual category name for a common merchant's key, from the starter list, or nil:
  # "STARBUCKS COFFEE 1234" => "Restaurants & Dining".
  def self.starter_category_name(key)
    STARTER_CATEGORIES.find { |prefix, _category_name| key == prefix || key.start_with?("#{prefix} ") }&.last
  end
end
