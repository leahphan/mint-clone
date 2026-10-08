require "net/http"

# Asks an Ollama Cloud model to categorize a transaction, using a JSON Schema to
# shape its answer. Returns the parsed answer, which TransactionCategorizer
# validates, or nil when there is no API key, Ollama is unavailable, or it
# answers with invalid JSON.
class OllamaClassifier
  SYSTEM_PROMPT = <<~PROMPT
    You categorize personal finance transactions. Given a bank transaction's description, its amount, and a list of categories, answer with:
    - normalized_merchant: the merchant's common name, e.g. "Netflix" for "PAYPAL *NETFLIX.COM".
    - category_id: the id of the best category from the list, or null if none fits or you are unsure. Only use ids from the list.
    - confidence: from 0 to 1, how sure you are of the category.
    Amounts are from the account holder's side: negative is money out, positive is money in. Money in can be income, a refund, or a transfer or card payment, so don't decide between expense and income categories from the sign alone.
    Categories of type "transfer" are for money moving between the account holder's own accounts, such as credit card payments, in either direction.
  PROMPT

  RESPONSE_SCHEMA = {
    type: "object",
    properties: {
      normalized_merchant: { type: "string" },
      category_id: { type: [ "integer", "null" ] },
      confidence: { type: "number", minimum: 0, maximum: 1 }
    },
    required: %w[normalized_merchant category_id confidence]
  }.freeze

  # The cloud API names models as https://ollama.com/api/tags lists them;
  # "gemma4:31b" is the model the Ollama app calls "gemma4:cloud".
  def initialize(api_key: ENV["OLLAMA_API_KEY"], base_url: ENV.fetch("OLLAMA_BASE_URL", "https://ollama.com"), model: ENV.fetch("OLLAMA_MODEL", "gemma4:31b"))
    @api_key = api_key
    @uri = URI.join(base_url, "/api/chat")
    @model = model
  end

  # categories: [{ id:, name:, type: }]
  def classify(description:, amount:, categories:)
    return failed("no API key") if api_key.blank?

    response = post(request_body(description, amount, categories))
    return failed("HTTP #{response.code}") unless response.is_a?(Net::HTTPSuccess)

    parse_answer(JSON.parse(response.body).dig("message", "content"))
  rescue SystemCallError, SocketError, IOError, Timeout::Error, OpenSSL::SSL::SSLError, JSON::ParserError, TypeError => error
    failed(error.class.name)
  end

  private
    attr_reader :api_key, :uri, :model

    def request_body(description, amount, categories)
      {
        model: model,
        stream: false,
        think: false,
        format: RESPONSE_SCHEMA,
        options: { temperature: 0 },
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: { description: description, amount: amount.to_s("F"), categories: categories }.to_json }
        ]
      }
    end

    def post(body)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 30) do |http|
        http.post(uri.path, body.to_json, "Content-Type" => "application/json", "Authorization" => "Bearer #{api_key}")
      end
    end

    # The cloud API doesn't enforce `format`, so the model may wrap its JSON in a Markdown code fence.
    def parse_answer(content)
      json = content.to_s.strip
      json = json.delete_prefix("```json").delete_prefix("```").delete_suffix("```") if json.start_with?("```")
      JSON.parse(json)
    end

    # Logs only the reason, never the transaction or the API key.
    def failed(reason)
      Rails.logger.warn("OllamaClassifier: request failed (#{reason})")
      nil
    end
end
