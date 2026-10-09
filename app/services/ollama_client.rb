require "net/http"

# Sends one chat request to an Ollama Cloud model, using a JSON Schema to shape
# its answer, and returns the parsed answer. Returns nil when there is no API key,
# Ollama is unavailable, or the answer isn't JSON. Logs only the reason, never the
# request, the answer or the API key.
class OllamaClient
  # The cloud API names models as https://ollama.com/api/tags lists them;
  # "gemma4:31b" is the model the Ollama app calls "gemma4:cloud".
  def initialize(api_key: ENV["OLLAMA_API_KEY"], base_url: ENV.fetch("OLLAMA_BASE_URL", "https://ollama.com"), model: ENV.fetch("OLLAMA_MODEL", "gemma4:31b"), log_as: self.class.name)
    @api_key = api_key
    @uri = URI.join(base_url, "/api/chat")
    @model = model
    @log_as = log_as
  end

  def chat(system:, content:, schema:)
    return failed("no API key") if api_key.blank?

    response = post(request_body(system, content, schema))
    return failed("HTTP #{response.code}") unless response.is_a?(Net::HTTPSuccess)

    parse_answer(JSON.parse(response.body).dig("message", "content"))
  rescue SystemCallError, SocketError, IOError, Timeout::Error, OpenSSL::SSL::SSLError, JSON::ParserError, TypeError => error
    failed(error.class.name)
  end

  private
    attr_reader :api_key, :uri, :model, :log_as

    def request_body(system, content, schema)
      {
        model: model,
        stream: false,
        think: false,
        format: schema,
        options: { temperature: 0 },
        messages: [
          { role: "system", content: system },
          { role: "user", content: content }
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

    def failed(reason)
      Rails.logger.warn("#{log_as}: request failed (#{reason})")
      nil
    end
end
