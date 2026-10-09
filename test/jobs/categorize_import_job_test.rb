require "test_helper"

class CategorizeImportJobTest < ActiveJob::TestCase
  test "categorizes the import's transactions from the account owner's learned merchants" do
    user = create(:user)
    groceries = create(:category, user: user, name: "Groceries")
    create(:merchant, user: user, key: "LOBLAWS", category: groceries)
    import = create(:import, account: create(:account, user: user))
    transaction = create(:transaction, account: import.account, import: import, description: "LOBLAWS")

    CategorizeImportJob.perform_now(import)

    assert_equal groceries, transaction.reload.category
  end

  test "completes and leaves transactions uncategorized when AI is enabled but Ollama Cloud is down" do
    import = create(:import)
    create(:category, user: import.account.user, name: "Coffee")
    transaction = create(:transaction, account: import.account, import: import, description: "SQ *PILOT COFFEE")
    previous = ENV.to_h.slice("AI_CATEGORIZATION_ENABLED", "OLLAMA_API_KEY")
    ENV.update("AI_CATEGORIZATION_ENABLED" => "true", "OLLAMA_API_KEY" => "test-key")

    Net::HTTP.stub(:start, ->(*, **) { raise Errno::ECONNREFUSED }) do
      assert_nothing_raised { CategorizeImportJob.perform_now(import) }
    end

    assert_nil transaction.reload.category
  ensure
    ENV.update("AI_CATEGORIZATION_ENABLED" => previous["AI_CATEGORIZATION_ENABLED"], "OLLAMA_API_KEY" => previous["OLLAMA_API_KEY"])
  end
end
