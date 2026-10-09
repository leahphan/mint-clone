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

  test "for_description creates a merchant with a display name, then finds it" do
    merchant = Merchant.for_description("7-ELEVEN 34512")
    assert_equal [ "7-ELEVEN 34512", "7-Eleven 34512" ], [ merchant.key, merchant.name ]

    assert_no_difference "Merchant.count" do
      assert_equal merchant, Merchant.for_description("7-eleven 34512")
    end
  end
end
