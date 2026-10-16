# Asks an Ollama Cloud model to categorize a batch of merchants in one request, using a JSON
# Schema to shape its answer. Returns the parsed answer, which TransactionCategorizer
# validates, or nil when there is no API key, Ollama is unavailable, or it answers with
# invalid JSON.
class OllamaClassifier
  SYSTEM_PROMPT = <<~PROMPT
    You categorize personal finance transactions. You get a list of bank transactions, one per merchant, each with a ref, its description and its amount, and a list of categories. Answer for every transaction, with its ref:
    - normalized_merchant: the merchant's common name, e.g. "Netflix" for "PAYPAL *NETFLIX.COM".
    - category_id: the id of the best category from the list, or null if none fits or you are unsure. Only use ids from the list.
    - confidence: from 0 to 1, how sure you are of the category.
    Amounts are from the account holder's side: negative is money out, positive is money in. Money in can be income, a refund, or a transfer or card payment, so don't decide between expense and income categories from the sign alone.
    Categories of type "transfer" are for money moving between the account holder's own accounts, such as credit card payments, in either direction.
  PROMPT

  RESPONSE_SCHEMA = {
    type: "object",
    properties: {
      merchants: {
        type: "array",
        items: {
          type: "object",
          properties: {
            ref: { type: "integer" },
            normalized_merchant: { type: "string" },
            category_id: { type: [ "integer", "null" ] },
            confidence: { type: "number", minimum: 0, maximum: 1 }
          },
          required: %w[ref normalized_merchant category_id confidence]
        }
      }
    },
    required: %w[merchants]
  }.freeze

  # Takes the same options as OllamaClient (api_key:, base_url:, model:).
  def initialize(**options)
    @client = OllamaClient.new(**options, log_as: "OllamaClassifier")
  end

  # merchants: [{ ref:, description:, amount: }], one transaction per merchant.
  # categories: [{ id:, name:, type: }]
  def classify_merchants(merchants:, categories:)
    transactions = merchants.map { |merchant| merchant.merge(amount: merchant[:amount].to_s("F")) }
    content = { transactions: transactions, categories: categories }.to_json
    client.chat(system: SYSTEM_PROMPT, content: content, schema: RESPONSE_SCHEMA)
  end

  private
    attr_reader :client
end
