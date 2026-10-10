require "test_helper"

class TransactionCategorizerTest < ActiveSupport::TestCase
  # Stands in for the AI classifier: returns a canned answer and records each call.
  class FakeClassifier
    attr_reader :calls

    def initialize(&answer)
      @answer = answer
      @calls = []
    end

    def classify(description:, amount:, categories:)
      calls << { description: description, amount: amount, categories: categories }
      @answer.call(description)
    end
  end

  setup do
    @user = create(:user)
    @account = create(:account, user: @user)
    @groceries = create(:category, user: @user, name: "Groceries")
    @coffee = create(:category, user: @user, name: "Coffee")
  end

  def confident_answer(category, merchant_name = "Pilot Coffee Roasters")
    { "normalized_merchant" => merchant_name, "category_id" => category.id, "confidence" => 0.95 }
  end

  test "uses the merchant's learned category without asking the classifier" do
    create(:merchant, user: @user, key: "COSTCO WHOLESALE", category: @groceries)
    transaction = create(:transaction, account: @account, description: "COSTCO WHOLESALE #123 TORONTO")
    classifier = FakeClassifier.new { flunk "classifier should not be called" }

    TransactionCategorizer.call(Transaction.all, user: @user, classifier: classifier)

    transaction.reload
    assert_equal [ @groceries, "learned" ], [ transaction.category, transaction.categorization_source ]
    assert_equal "COSTCO WHOLESALE", transaction.merchant.key
  end

  test "asks the classifier once per unknown merchant and learns its answer" do
    first = create(:transaction, account: @account, description: "SQ *PILOT COFFEE TORONTO ON", amount: "-4.50")
    second = create(:transaction, account: @account, description: "SQ *PILOT COFFEE TORONTO ON", amount: "-6.25")
    classifier = FakeClassifier.new { confident_answer(@coffee) }

    TransactionCategorizer.call(Transaction.all, user: @user, classifier: classifier)

    assert_equal 1, classifier.calls.size
    call = classifier.calls.first
    assert_equal "SQ *PILOT COFFEE TORONTO ON", call[:description]
    assert_equal [ "Coffee", "Groceries" ], call[:categories].map { |category| category[:name] }

    [ first, second ].each(&:reload)
    assert_equal [ [ @coffee, "ai" ] ] * 2, [ first, second ].map { |t| [ t.category, t.categorization_source ] }
    merchant = first.merchant
    assert_equal [ "Pilot Coffee Roasters", @coffee ], [ merchant.name, merchant.category ]
    assert_equal merchant, second.merchant
  end

  test "a merchant categorized by AI is learned for the next batch" do
    TransactionCategorizer.call(Transaction.where(id: create(:transaction, account: @account, description: "SQ *PILOT COFFEE").id),
      user: @user, classifier: FakeClassifier.new { confident_answer(@coffee) })
    later = create(:transaction, account: @account, description: "SQ *PILOT COFFEE")

    TransactionCategorizer.call(Transaction.where(id: later.id), user: @user, classifier: FakeClassifier.new { flunk "not needed" })

    assert_equal [ @coffee, "learned" ], [ later.reload.category, later.categorization_source ]
  end

  test "rejects answers that aren't a confident choice of an offered category" do
    deleted_id = create(:category, user: @user).tap(&:delete).id
    invalid_answers = [
      nil,
      "Coffee",
      { "normalized_merchant" => "Pilot", "category_id" => deleted_id, "confidence" => 0.99 },
      { "normalized_merchant" => "Pilot", "category_id" => @coffee.id.to_s, "confidence" => 0.99 },
      { "normalized_merchant" => "Pilot", "category_id" => nil, "confidence" => 0.99 },
      { "normalized_merchant" => "Pilot", "category_id" => @coffee.id, "confidence" => 0.5 },
      { "normalized_merchant" => "Pilot", "category_id" => @coffee.id, "confidence" => "high" },
      { "normalized_merchant" => "", "category_id" => @coffee.id, "confidence" => 0.99 },
      { "category_id" => @coffee.id, "confidence" => 0.99 }
    ]

    invalid_answers.each do |answer|
      transaction = create(:transaction, account: @account, description: "SQ *PILOT COFFEE")
      TransactionCategorizer.call(Transaction.where(id: transaction.id), user: @user, classifier: FakeClassifier.new { answer })

      transaction.reload
      assert_nil transaction.category, "accepted #{answer.inspect}"
      assert_nil transaction.categorization_source
      assert_nil transaction.merchant.category
    end
  end

  test "a classifier error leaves transactions uncategorized" do
    transaction = create(:transaction, account: @account, description: "NEW PLACE")
    classifier = FakeClassifier.new { raise Errno::ECONNREFUSED }

    assert_nothing_raised { TransactionCategorizer.call(Transaction.all, user: @user, classifier: classifier) }
    assert_nil transaction.reload.category
    assert_equal "NEW PLACE", transaction.merchant.key
  end

  test "without a classifier, unknown merchants stay uncategorized" do
    transaction = create(:transaction, account: @account, description: "NEW PLACE")

    TransactionCategorizer.call(Transaction.all, user: @user, classifier: nil)

    assert_nil transaction.reload.category
  end

  test "AI categorization is disabled unless configured" do
    with_env("AI_CATEGORIZATION_ENABLED" => nil) do
      assert_nil TransactionCategorizer.default_classifier
    end
    with_env("AI_CATEGORIZATION_ENABLED" => "true") do
      assert_instance_of OllamaClassifier, TransactionCategorizer.default_classifier
    end
  end

  test "leaves already-categorized transactions alone" do
    create(:merchant, user: @user, key: "COSTCO WHOLESALE", category: @groceries)
    transaction = create(:transaction, account: @account, description: "COSTCO WHOLESALE", category: @coffee, categorization_source: "manual")

    TransactionCategorizer.call(Transaction.all, user: @user, classifier: nil)

    assert_equal [ @coffee, "manual" ], [ transaction.reload.category, transaction.categorization_source ]
  end

  test "another user's learned merchant doesn't categorize this user's transaction" do
    other_user = create(:user)
    create(:merchant, user: other_user, key: "COSTCO WHOLESALE", category: create(:category, user: other_user))
    transaction = create(:transaction, account: @account, description: "COSTCO WHOLESALE")

    TransactionCategorizer.call(Transaction.all, user: @user, classifier: nil)

    transaction.reload
    assert_nil transaction.category
    assert_equal @user, transaction.merchant.user
    assert_equal 2, Merchant.where(key: "COSTCO WHOLESALE").count
  end

  test "offers the classifier only this user's categories and learns its answer on this user's merchant only" do
    other_user = create(:user)
    create(:category, user: other_user, name: "Cafes")
    other_merchant = create(:merchant, user: other_user, key: "PILOT COFFEE", name: "Theirs")
    transaction = create(:transaction, account: @account, description: "SQ *PILOT COFFEE")
    classifier = FakeClassifier.new { confident_answer(@coffee) }

    TransactionCategorizer.call(Transaction.all, user: @user, classifier: classifier)

    assert_equal [ "Coffee", "Groceries" ], classifier.calls.first[:categories].map { |category| category[:name] }
    assert_equal [ @coffee, @user ], [ transaction.reload.category, transaction.merchant.user ]
    assert_equal [ nil, "Theirs" ], [ other_merchant.reload.category, other_merchant.name ]
  end

  test "rejects an answer naming another user's category" do
    other_category = create(:category, user: create(:user))
    transaction = create(:transaction, account: @account, description: "SQ *PILOT COFFEE")

    TransactionCategorizer.call(Transaction.all, user: @user, classifier: FakeClassifier.new { confident_answer(other_category) })

    transaction.reload
    assert_nil transaction.category
    assert_nil transaction.merchant.category
  end

  test "ignores transactions in another user's accounts" do
    create(:merchant, user: @user, key: "COSTCO WHOLESALE", category: @groceries)
    theirs = create(:transaction, description: "COSTCO WHOLESALE")

    TransactionCategorizer.call(Transaction.all, user: @user, classifier: nil)

    theirs.reload
    assert_nil theirs.category
    assert_nil theirs.merchant
  end

  private
    def with_env(values)
      previous = values.keys.index_with { |key| ENV[key] }
      ENV.update(values)
      yield
    ensure
      ENV.update(previous)
    end
end
