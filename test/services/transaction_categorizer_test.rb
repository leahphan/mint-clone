require "test_helper"

class TransactionCategorizerTest < ActiveSupport::TestCase
  # Stands in for the AI classifier and records each request. With a block, it answers each merchant in
  # the batch with the block's answer for its description (nil for none); otherwise with `response`.
  class FakeClassifier
    attr_reader :calls

    def initialize(response: nil, &answer)
      @response = response
      @answer = answer
      @calls = []
    end

    def classify_merchants(merchants:, categories:)
      calls << { merchants: merchants, categories: categories }
      return @response unless @answer

      { "merchants" => merchants.filter_map { |merchant| @answer.call(merchant[:description])&.merge("ref" => merchant[:ref]) } }
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
    create(:merchant, user: @user, key: "CORNER GROCER", category: @groceries)
    transaction = create(:transaction, account: @account, description: "CORNER GROCER #123 TORONTO")
    classifier = FakeClassifier.new { flunk "classifier should not be called" }

    TransactionCategorizer.call(Transaction.all, user: @user, classifier: classifier)

    transaction.reload
    assert_equal [ @groceries, "learned" ], [ transaction.category, transaction.categorization_source ]
    assert_equal "CORNER GROCER", transaction.merchant.key
  end

  test "uses the starter list's category for a common merchant, without learning it or asking the classifier" do
    transaction = create(:transaction, account: @account, description: "LOBLAWS #1234 TORONTO ON")
    classifier = FakeClassifier.new { flunk "classifier should not be called" }

    TransactionCategorizer.call(Transaction.all, user: @user, classifier: classifier)

    transaction.reload
    assert_equal [ @groceries, "starter_list" ], [ transaction.category, transaction.categorization_source ]
    assert_equal [ "LOBLAWS", nil ], [ transaction.merchant.key, transaction.merchant.category ]
  end

  test "the merchant's learned category wins over the starter list" do
    create(:merchant, user: @user, key: "LOBLAWS", category: @coffee)
    transaction = create(:transaction, account: @account, description: "LOBLAWS #1234")

    TransactionCategorizer.call(Transaction.all, user: @user, classifier: nil)

    assert_equal [ @coffee, "learned" ], [ transaction.reload.category, transaction.categorization_source ]
  end

  test "skips the starter list's category when the user has no category by that name" do
    transaction = create(:transaction, account: @account, description: "TIM HORTONS #0412")
    classifier = FakeClassifier.new { confident_answer(@coffee, "Tim Hortons") }

    TransactionCategorizer.call(Transaction.all, user: @user, classifier: classifier)

    assert_equal [ @coffee, "ai" ], [ transaction.reload.category, transaction.categorization_source ]
  end

  test "asks the classifier about all unknown merchants in one request and learns its answers" do
    first = create(:transaction, account: @account, description: "SQ *PILOT COFFEE TORONTO ON", amount: "-4.50")
    second = create(:transaction, account: @account, description: "SQ *PILOT COFFEE TORONTO ON", amount: "-6.25")
    market = create(:transaction, account: @account, description: "CORNER GROCER #12", amount: "-30.00")
    classifier = FakeClassifier.new do |description|
      description.include?("PILOT") ? confident_answer(@coffee) : confident_answer(@groceries, "Corner Grocer")
    end

    TransactionCategorizer.call(Transaction.all, user: @user, classifier: classifier)

    call = classifier.calls.sole
    assert_equal [ 1, 2 ], call[:merchants].map { |merchant| merchant[:ref] }
    assert_equal [ "CORNER GROCER #12", "SQ *PILOT COFFEE TORONTO ON" ], call[:merchants].map { |merchant| merchant[:description] }.sort
    assert_equal [ "Coffee", "Groceries" ], call[:categories].map { |category| category[:name] }

    [ first, second, market ].each(&:reload)
    assert_equal [ [ @coffee, "ai" ] ] * 2 + [ [ @groceries, "ai" ] ], [ first, second, market ].map { |t| [ t.category, t.categorization_source ] }
    merchant = first.merchant
    assert_equal [ "Pilot Coffee Roasters", @coffee ], [ merchant.name, merchant.category ]
    assert_equal merchant, second.merchant
    assert_equal [ "Corner Grocer", @groceries ], [ market.merchant.name, market.merchant.category ]
  end

  test "asks about at most CLASSIFIER_BATCH_SIZE merchants per request" do
    (TransactionCategorizer::CLASSIFIER_BATCH_SIZE + 1).times { |n| create(:transaction, account: @account, description: "SHOP NUMBER#{n}") }
    classifier = FakeClassifier.new { confident_answer(@groceries, "A shop") }

    TransactionCategorizer.call(Transaction.all, user: @user, classifier: classifier)

    assert_equal [ TransactionCategorizer::CLASSIFIER_BATCH_SIZE, 1 ], classifier.calls.map { |call| call[:merchants].size }
    assert_equal [ 1 ], classifier.calls.last[:merchants].map { |merchant| merchant[:ref] }
    assert_equal 0, @account.transactions.where(category_id: nil).count
  end

  test "creates the user's new merchants in one insert" do
    5.times { |n| create(:transaction, account: @account, description: "SHOP NUMBER#{n}") }

    assert_queries_match(/INSERT INTO "merchants"/, count: 1) do
      TransactionCategorizer.call(Transaction.all, user: @user, classifier: nil)
    end
    assert_equal 5, @user.merchants.count
  end

  test "a merchant categorized by AI is learned for the next batch" do
    TransactionCategorizer.call(Transaction.where(id: create(:transaction, account: @account, description: "SQ *PILOT COFFEE").id),
      user: @user, classifier: FakeClassifier.new { confident_answer(@coffee) })
    later = create(:transaction, account: @account, description: "SQ *PILOT COFFEE")

    TransactionCategorizer.call(Transaction.where(id: later.id), user: @user, classifier: FakeClassifier.new { flunk "not needed" })

    assert_equal [ @coffee, "learned" ], [ later.reload.category, later.categorization_source ]
  end

  test "rejects answers that aren't a confident choice of an offered category for a merchant in the batch" do
    deleted_id = create(:category, user: @user).tap(&:delete).id
    valid = { "ref" => 1, "normalized_merchant" => "Pilot", "category_id" => @coffee.id, "confidence" => 0.99 }
    invalid_responses = [
      nil,
      "Coffee",
      {},
      { "merchants" => "Coffee" },
      { "merchants" => [ "Coffee", nil ] },
      { "merchants" => [ valid.merge("category_id" => deleted_id) ] },
      { "merchants" => [ valid.merge("category_id" => @coffee.id.to_s) ] },
      { "merchants" => [ valid.merge("category_id" => nil) ] },
      { "merchants" => [ valid.merge("confidence" => 0.5) ] },
      { "merchants" => [ valid.merge("confidence" => "high") ] },
      { "merchants" => [ valid.merge("normalized_merchant" => "") ] },
      { "merchants" => [ valid.except("normalized_merchant") ] },
      { "merchants" => [ valid.merge("ref" => 2) ] },
      { "merchants" => [ valid.merge("ref" => 0) ] },
      { "merchants" => [ valid.merge("ref" => "1") ] },
      { "merchants" => [ valid.except("ref") ] }
    ]

    invalid_responses.each do |response|
      transaction = create(:transaction, account: @account, description: "SQ *PILOT COFFEE")
      TransactionCategorizer.call(Transaction.where(id: transaction.id), user: @user, classifier: FakeClassifier.new(response: response))

      transaction.reload
      assert_nil transaction.category, "accepted #{response.inspect}"
      assert_nil transaction.categorization_source
      assert_nil transaction.merchant.category
    end
  end

  test "uses the first answer when the classifier answers a merchant twice" do
    transaction = create(:transaction, account: @account, description: "SQ *PILOT COFFEE")
    response = { "merchants" => [ confident_answer(@coffee).merge("ref" => 1), confident_answer(@groceries).merge("ref" => 1) ] }

    TransactionCategorizer.call(Transaction.all, user: @user, classifier: FakeClassifier.new(response: response))

    assert_equal @coffee, transaction.reload.category
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
    assert_equal "NEW PLACE", transaction.merchant.key
  end

  test "AI categorization is disabled unless configured" do
    with_env("AI_CATEGORIZATION_ENABLED" => nil) do
      assert_not TransactionCategorizer.ai_enabled?
      assert_nil TransactionCategorizer.default_classifier
    end
    with_env("AI_CATEGORIZATION_ENABLED" => "true") do
      assert TransactionCategorizer.ai_enabled?
      assert_instance_of OllamaClassifier, TransactionCategorizer.default_classifier
    end
  end

  test "leaves already-categorized transactions alone" do
    create(:merchant, user: @user, key: "CORNER GROCER", category: @groceries)
    transaction = create(:transaction, account: @account, description: "CORNER GROCER", category: @coffee, categorization_source: "manual")

    TransactionCategorizer.call(Transaction.all, user: @user, classifier: nil)

    assert_equal [ @coffee, "manual" ], [ transaction.reload.category, transaction.categorization_source ]
  end

  test "a category the user picks while the batch is running isn't overwritten, on the transaction or its merchant" do
    transaction = create(:transaction, account: @account, description: "SQ *PILOT COFFEE")
    classifier = FakeClassifier.new do
      SaveTransaction.call(Transaction.find(transaction.id), category_id: @groceries.id)
      confident_answer(@coffee)
    end

    TransactionCategorizer.call(Transaction.all, user: @user, classifier: classifier)

    assert_equal [ @groceries, "manual" ], [ transaction.reload.category, transaction.categorization_source ]
    assert_equal @groceries, transaction.merchant.category
  end

  test "another user's learned merchant doesn't categorize this user's transaction" do
    other_user = create(:user)
    create(:merchant, user: other_user, key: "CORNER GROCER", category: create(:category, user: other_user))
    transaction = create(:transaction, account: @account, description: "CORNER GROCER")

    TransactionCategorizer.call(Transaction.all, user: @user, classifier: nil)

    transaction.reload
    assert_nil transaction.category
    assert_equal @user, transaction.merchant.user
    assert_equal 2, Merchant.where(key: "CORNER GROCER").count
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
    create(:merchant, user: @user, key: "CORNER GROCER", category: @groceries)
    theirs = create(:transaction, description: "CORNER GROCER")

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
