# Saves a transaction the user created or edited. A category the user picks is
# recorded as manual and remembered on the account owner's merchant, so their
# later imports from that merchant get the same category.
class SaveTransaction
  def self.call(transaction, attributes)
    new(transaction, attributes).call
  end

  def initialize(transaction, attributes)
    @transaction = transaction
    @attributes = attributes
  end

  # Returns true if saved, otherwise false with errors on the transaction.
  def call
    transaction.assign_attributes(attributes)
    return transaction.save unless transaction.category_id_changed?

    transaction.categorization_source = transaction.category ? "manual" : nil
    Transaction.transaction do
      transaction.save!
      learn_merchant_category if transaction.category
    end
    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  private
    attr_reader :transaction, :attributes

    def learn_merchant_category
      merchant = transaction.account.user.merchants.for_description(transaction.description)
      merchant.update!(category: transaction.category)
      transaction.update!(merchant: merchant)
    end
end
