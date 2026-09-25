ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    include FactoryBot::Syntax::Methods

    def csv_upload(content, filename: "transactions.csv")
      Rack::Test::UploadedFile.new(StringIO.new(content), "text/csv", original_filename: filename)
    end

    # Add more helper methods to be used by all tests here...
  end
end
