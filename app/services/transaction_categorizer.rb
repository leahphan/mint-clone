# Categorizes a batch of one user's transactions that have no category. Each of
# the user's merchants' learned category is used first. For merchants without
# one, the classifier (if AI categorization is enabled) is asked once per
# merchant, offered only this user's categories, and a valid, confident answer
# is learned on the user's merchant so it isn't sent to the classifier again.
class TransactionCategorizer
  MIN_CONFIDENCE = 0.8

  # transactions is a relation; only its uncategorized rows in the user's accounts are changed.
  def self.call(transactions, user:, classifier: default_classifier)
    new(transactions, user, classifier).call
  end

  def self.default_classifier
    OllamaClassifier.new if ENV["AI_CATEGORIZATION_ENABLED"] == "true"
  end

  def initialize(transactions, user, classifier)
    # update_all below skips validations, so only the user's own transactions are touched.
    @transactions = transactions.where(category_id: nil, account: user.accounts).to_a
    @user = user
    @classifier = classifier
  end

  def call
    by_merchant_key = transactions.group_by { |transaction| Merchant.key_for(transaction.description) }
    known_merchants = user.merchants.where(key: by_merchant_key.keys).index_by(&:key)

    by_merchant_key.each do |key, group|
      merchant = known_merchants[key] || user.merchants.for_description(group.first.description)
      category_id, source = learned_category(merchant) || classify(merchant, group.first)

      # Still uncategorized: the user may have picked a category while this batch was running.
      Transaction.where(id: group.map(&:id), category_id: nil).update_all(
        merchant_id: merchant.id, category_id: category_id, categorization_source: source, updated_at: Time.current
      )
    end
  end

  private
    attr_reader :transactions, :user, :classifier

    def learned_category(merchant)
      [ merchant.category_id, "learned" ] if merchant.category_id
    end

    def classify(merchant, transaction)
      return unless classifier

      answer = valid_answer(ask_classifier(transaction))
      return unless answer

      # Only if nothing was learned meanwhile, e.g. from the user's own pick while the classifier was answering.
      user.merchants.where(id: merchant.id, category_id: nil)
        .update_all(category_id: answer[:category_id], name: answer[:name], updated_at: Time.current)
      [ answer[:category_id], "ai" ]
    end

    # The classifier is an external boundary: a failure leaves the merchant uncategorized.
    def ask_classifier(transaction)
      classifier.classify(description: transaction.description, amount: transaction.amount, categories: categories)
    rescue StandardError => error
      Rails.logger.warn("TransactionCategorizer: classifier failed (#{error.class})")
      nil
    end

    # Accepts only an existing category we offered, with enough confidence and a merchant name.
    def valid_answer(result)
      return unless result.is_a?(Hash)

      category_id, confidence, name = result.values_at("category_id", "confidence", "normalized_merchant")
      return unless category_id.is_a?(Integer) && categories.any? { |category| category[:id] == category_id }
      return unless confidence.is_a?(Numeric) && confidence >= MIN_CONFIDENCE
      return unless name.is_a?(String) && name.present?

      { category_id: category_id, name: name.squish.truncate(100, omission: "") }
    end

    def categories
      @categories ||= user.categories.order(:name).map do |category|
        { id: category.id, name: category.name, type: category.category_type }
      end
    end
end
