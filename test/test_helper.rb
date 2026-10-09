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

    # An upload of a file in test/fixtures/files, or of some of its lines.
    def fixture_upload(name, lines: nil)
      content = lines ? file_fixture(name).readlines.values_at(*lines).join : file_fixture(name).read
      csv_upload(content, filename: name)
    end

    # The rows of the TD Visa export dated on or before the 12th, so every date fits both MM/DD and DD/MM.
    def ambiguous_visa_csv
      file_fixture("td_visa.csv").readlines.select { |line| line[3, 2].to_i <= 12 }.join
    end

    # Add more helper methods to be used by all tests here...
  end
end
