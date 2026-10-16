# Categorizes a batch of one user's transactions that have no category, by merchant: first the
# merchant's learned category, then the starter list of common merchants. Those lookups are quick,
# so an import runs them (classifier: nil) before showing the transactions. The other merchants go to
# the classifier, if AI categorization is enabled, a batch of merchants per request, offered only
# this user's categories. A valid, confident answer is learned on the user's merchant so it isn't
# sent to the classifier again.
class TransactionCategorizer
  MIN_CONFIDENCE = 0.8
  CLASSIFIER_BATCH_SIZE = 25

  # transactions is a relation; only its uncategorized rows in the user's accounts are changed.
  def self.call(transactions, user:, classifier: default_classifier)
    new(transactions, user, classifier).call
  end

  def self.ai_enabled?
    ENV["AI_CATEGORIZATION_ENABLED"] == "true"
  end

  def self.default_classifier
    OllamaClassifier.new if ai_enabled?
  end

  def initialize(transactions, user, classifier)
    # update_all below skips validations, so only the user's own transactions are touched.
    @transactions = transactions.where(category_id: nil, account: user.accounts).to_a
    @user = user
    @classifier = classifier
  end

  def call
    by_merchant = merchants_for(transactions.group_by { |transaction| Merchant.key_for(transaction.description) })
    known, unknown = by_merchant.partition { |merchant, _group| known_category(merchant) }

    known.each { |merchant, group| assign(group, merchant, *known_category(merchant)) }
    classifier ? classify(unknown) : unknown.each { |merchant, group| assign(group, merchant) }
  end

  private
    attr_reader :transactions, :user, :classifier

    # { the user's merchant => its transactions } for { merchant key => transactions },
    # creating the user's new merchants in one insert.
    def merchants_for(groups)
      return {} if groups.empty?

      # Sorted, so two imports inserting the same new merchants take their locks in the same order.
      missing = (groups.keys - user.merchants.where(key: groups.keys).pluck(:key)).sort
      if missing.any?
        rows = missing.map { |key| { user_id: user.id, key: key, name: Merchant.display_name_for(key) } }
        Merchant.insert_all(rows, unique_by: %i[user_id key]) # another import may have just created some
      end
      user.merchants.where(key: groups.keys).to_h { |merchant| [ merchant, groups.fetch(merchant.key) ] }
    end

    # [category id, source] from what we already know about the merchant, or nil.
    def known_category(merchant)
      if merchant.category_id
        [ merchant.category_id, "learned" ]
      elsif (category_id = starter_category_ids[Merchant.starter_category_name(merchant.key)&.downcase])
        [ category_id, "starter_list" ]
      end
    end

    # Only rows still uncategorized: the user may have picked a category while this was running.
    def assign(group, merchant, category_id = nil, source = nil)
      Transaction.where(id: group.map(&:id), category_id: nil).update_all(
        merchant_id: merchant.id, category_id: category_id, categorization_source: source, updated_at: Time.current
      )
    end

    # Asks the classifier about [merchant, transactions] pairs, a batch per request, and categorizes
    # each batch's transactions as soon as it answers, so they show up while later batches wait.
    def classify(unknown)
      unknown.each_slice(CLASSIFIER_BATCH_SIZE) do |batch|
        answers = valid_answers(ask_classifier(batch), batch.size)
        batch.each.with_index(1) do |(merchant, group), ref|
          assign(group, merchant, *(learn(merchant, *answers[ref]) if answers[ref]))
        end
      end
    end

    # The classifier is an external boundary: a failure leaves the batch's merchants uncategorized.
    # It's asked about one transaction per merchant.
    def ask_classifier(batch)
      merchants = batch.map.with_index(1) do |(_merchant, group), ref|
        { ref: ref, description: group.first.description, amount: group.first.amount }
      end
      classifier.classify_merchants(merchants: merchants, categories: categories)
    rescue StandardError => error
      Rails.logger.warn("TransactionCategorizer: classifier failed (#{error.class})")
      nil
    end

    # { ref => [category id, merchant name] } for the answers that are a confident choice of an
    # offered category for a merchant in the batch. Anything else is ignored.
    def valid_answers(result, batch_size)
      answers = result["merchants"] if result.is_a?(Hash)
      return {} unless answers.is_a?(Array)

      answers.each_with_object({}) do |answer, valid|
        next unless answer.is_a?(Hash)

        ref, category_id, confidence, name = answer.values_at("ref", "category_id", "confidence", "normalized_merchant")
        next unless ref.is_a?(Integer) && ref.between?(1, batch_size) && !valid.key?(ref)
        next unless category_id.is_a?(Integer) && categories.any? { |category| category[:id] == category_id }
        next unless confidence.is_a?(Numeric) && confidence >= MIN_CONFIDENCE
        next unless name.is_a?(String) && name.present?

        valid[ref] = [ category_id, name.squish.truncate(100, omission: "") ]
      end
    end

    # Learns the answer on the merchant, unless it learned a category meanwhile (e.g. the user picked
    # one while the classifier was answering), which then wins. Returns [category id, source].
    def learn(merchant, category_id, name)
      learned = user.merchants.where(id: merchant.id, category_id: nil)
        .update_all(category_id: category_id, name: name, updated_at: Time.current)
      learned.positive? ? [ category_id, "ai" ] : [ merchant.reload.category_id, "learned" ]
    end

    def categories
      @categories ||= user.categories.order(:name).map do |category|
        { id: category.id, name: category.name, type: category.category_type }
      end
    end

    # The user's category ids by lower-case name, for the starter list's category names.
    def starter_category_ids
      @starter_category_ids ||= categories.to_h { |category| [ category[:name].downcase, category[:id] ] }
    end
end
