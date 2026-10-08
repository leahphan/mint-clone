# A merchant identified by a normalized key from transaction descriptions. Its
# category is the learned one: future transactions from it get that category.
class Merchant < ApplicationRecord
  # Card processors that put their own name before the merchant's: "SQ *PILOT COFFEE".
  PROCESSOR_PREFIX = /\A(?:SQ|TST|PAYPAL|PP)\s*\*\s*/

  has_many :transactions
  belongs_to :category, optional: true

  # Uniqueness is enforced by the unique index on key (see for_description).
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

  def self.for_description(description)
    key = key_for(description)
    create_or_find_by!(key: key) { |merchant| merchant.name = display_name_for(key) }
  end

  # "7-ELEVEN" => "7-Eleven"
  def self.display_name_for(key)
    key.downcase.gsub(/(?<![\w'])[a-z]/, &:upcase)
  end
end
