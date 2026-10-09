require "test_helper"

class OllamaClassifierTest < ActiveSupport::TestCase
  # Stands in for the Net::HTTP connection: records where it connected and the request, and returns a canned response.
  class FakeHttp
    attr_reader :connections, :requests

    def initialize(response)
      @response = response
      @connections = []
      @requests = []
    end

    def post(path, body, headers)
      requests << { path: path, body: JSON.parse(body), headers: headers }
      @response.respond_to?(:call) ? @response.call : @response
    end
  end

  CATEGORIES = [ { id: 7, name: "Coffee", type: "expense" } ].freeze

  setup do
    @classifier = OllamaClassifier.new(api_key: "test-key", base_url: "https://ollama.com", model: "test-model")
  end

  test "asks the Ollama Cloud model with the categories and a response schema, and returns its parsed answer" do
    answer = { "normalized_merchant" => "Pilot Coffee Roasters", "category_id" => 7, "confidence" => 0.9 }
    http = FakeHttp.new(ok_response({ message: { content: answer.to_json } }.to_json))

    result = with_http(http) { classify }

    assert_equal answer, result
    assert_equal [ "ollama.com", 443, true ], http.connections.sole
    request = http.requests.sole
    assert_equal "/api/chat", request[:path]
    assert_equal "Bearer test-key", request[:headers]["Authorization"]
    body = request[:body]
    assert_equal [ "test-model", false ], body.values_at("model", "stream")
    assert_equal %w[normalized_merchant category_id confidence], body.dig("format", "required")
    assert_equal({ "description" => "SQ *PILOT COFFEE", "amount" => "-4.5", "categories" => [ { "id" => 7, "name" => "Coffee", "type" => "expense" } ] },
      JSON.parse(body["messages"].last["content"]))
  end

  test "parses an answer wrapped in a Markdown code fence" do
    content = "```json\n{\n  \"normalized_merchant\": \"Pilot Coffee\",\n  \"category_id\": 7,\n  \"confidence\": 1.0\n}\n```"
    http = FakeHttp.new(ok_response({ message: { content: content } }.to_json))

    assert_equal({ "normalized_merchant" => "Pilot Coffee", "category_id" => 7, "confidence" => 1.0 }, with_http(http) { classify })
  end

  test "returns nil without calling Ollama when there is no API key" do
    http = FakeHttp.new(ok_response("{}"))

    [ nil, "" ].each do |key|
      classifier = OllamaClassifier.new(api_key: key, base_url: "https://ollama.com", model: "test-model")
      assert_nil with_http(http) { classifier.classify(description: "SQ *PILOT COFFEE", amount: BigDecimal("-4.50"), categories: CATEGORIES) }
    end
    assert_empty http.requests
  end

  test "returns nil when Ollama can't be reached or times out" do
    [ Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout, SocketError, OpenSSL::SSL::SSLError ].each do |error|
      failing_start = ->(*, **) { raise error }
      Net::HTTP.stub(:start, failing_start) { assert_nil classify, "for #{error}" }
    end
  end

  test "returns nil for an error status" do
    [ Net::HTTPUnauthorized.new("1.1", "401", "Unauthorized"), Net::HTTPInternalServerError.new("1.1", "500", "Internal Server Error") ].each do |response|
      assert_nil with_http(FakeHttp.new(response)) { classify }, "for #{response.code}"
    end
  end

  test "returns nil for a response that isn't the expected JSON" do
    [ "not json", { message: { content: "not json" } }.to_json, {}.to_json ].each do |body|
      assert_nil with_http(FakeHttp.new(ok_response(body))) { classify }, "for #{body}"
    end
  end

  private
    def classify
      @classifier.classify(description: "SQ *PILOT COFFEE", amount: BigDecimal("-4.50"), categories: CATEGORIES)
    end

    def with_http(http, &block)
      start = ->(host, port, use_ssl:, **, &request) do
        http.connections << [ host, port, use_ssl ]
        request.call(http)
      end
      Net::HTTP.stub(:start, start, &block)
    end

    def ok_response(body)
      Net::HTTPOK.new("1.1", "200", "OK").tap do |response|
        response.instance_variable_set(:@read, true)
        response.instance_variable_set(:@body, body)
      end
    end
end
