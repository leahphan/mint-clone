require "test_helper"

class MerchantTest < ActiveSupport::TestCase
  test "key strips payment-processor prefixes" do
    assert_equal "NETFLIX", Merchant.key_for("PAYPAL *NETFLIX.COM")
    assert_equal "PILOT COFFEE TORONTO ON", Merchant.key_for("SQ *PILOT COFFEE TORONTO ON")
    assert_equal "BURRITO BOYZ", Merchant.key_for("TST* Burrito Boyz")
  end

  test "key keeps the merchant before a star when there's no processor prefix" do
    assert_equal "UBER", Merchant.key_for("UBER *TRIP HELP.UBER.COM")
    assert_equal "AMAZON", Merchant.key_for("Amazon.ca*RT4Y29QL1")
  end

  test "key drops a labelled store number and what follows it" do
    assert_equal "COSTCO WHOLESALE", Merchant.key_for("COSTCO WHOLESALE #123 TORONTO")
  end

  test "key keeps digits that may be part of the name" do
    assert_equal "7-ELEVEN 34512", Merchant.key_for("7-Eleven 34512")
    assert_equal "SHOPPERS DRUG MART 1234", Merchant.key_for("  shoppers   drug mart 1234 ")
  end

  test "key falls back to the whole description when normalizing leaves nothing" do
    assert_equal "#42", Merchant.key_for("#42")
    assert_equal "*", Merchant.key_for("*")
  end

  test "for_description creates the user's merchant with a display name, then finds it" do
    user = create(:user)
    merchant = user.merchants.for_description("7-ELEVEN 34512")
    assert_equal [ "7-ELEVEN 34512", "7-Eleven 34512", user ], [ merchant.key, merchant.name, merchant.user ]

    assert_no_difference "Merchant.count" do
      assert_equal merchant, user.merchants.for_description("7-eleven 34512")
    end
  end

  test "each user has their own merchant for the same key" do
    user = create(:user)
    theirs = create(:merchant, key: "LOBLAWS")

    assert_difference "Merchant.count", 1 do
      assert_not_equal theirs, user.merchants.for_description("LOBLAWS")
    end
    assert_raises(ActiveRecord::RecordNotUnique) { create(:merchant, user: user, key: "LOBLAWS") }
  end

  test "the database rejects a learned category that belongs to another user" do
    merchant = create(:merchant)

    assert_raises(ActiveRecord::InvalidForeignKey) { merchant.update!(category: create(:category)) }
    assert merchant.update!(category: create(:category, user: merchant.user))
  end

  test "the starter list suggests a category for common merchants by their key" do
    assert_equal "Groceries", Merchant.starter_category_name(Merchant.key_for("LOBLAWS #1234 TORONTO ON"))
    assert_equal "Restaurants & Dining", Merchant.starter_category_name(Merchant.key_for("STARBUCKS COFFEE 04512"))
    assert_equal "Shopping", Merchant.starter_category_name(Merchant.key_for("Amazon.ca*RT4Y29QL1"))
    assert_equal "Transportation", Merchant.starter_category_name(Merchant.key_for("CANADIAN TIRE GAS #0457"))
    assert_equal "Shopping", Merchant.starter_category_name(Merchant.key_for("CANADIAN TIRE #0457"))
  end

  test "the starter list's longer entries win over a shorter merchant they start with" do
    assert_equal "Shopping", Merchant.starter_category_name("INDIGO BOOKS")
    assert_equal "Transportation", Merchant.starter_category_name(Merchant.key_for("INDIGO PARK CANADA #1234 TORONTO"))
    assert_equal "Utilities", Merchant.starter_category_name("ROGERS WIRELESS")
    assert_equal "Entertainment", Merchant.starter_category_name("ROGERS CENTRE TORONTO ON")
    assert_equal "Credit Card Payment", Merchant.starter_category_name("ROGERS BANK")
  end

  test "the starter list only matches whole words at the start of the key" do
    assert_nil Merchant.starter_category_name("SHELLEYS BAKERY")
    assert_nil Merchant.starter_category_name("METROLINX")
    assert_nil Merchant.starter_category_name("THE METRO DINER")
    assert_nil Merchant.starter_category_name("KAFU SEMO AND _F")
  end

  test "the starter list names only default categories, with normalized, unique keys" do
    names = Category::DEFAULTS.values.flatten
    prefixes = Merchant::STARTER_CATEGORIES.map(&:first)

    Merchant::STARTER_CATEGORIES.each do |prefix, category_name|
      assert_includes names, category_name
      assert_equal prefix, Merchant.key_for(prefix), "#{prefix} isn't a normalized merchant key"
    end
    assert_equal prefixes.uniq, prefixes
  end
end
