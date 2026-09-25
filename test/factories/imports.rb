FactoryBot.define do
  factory :import do
    account
    filename { "transactions.csv" }
    sequence(:checksum) { |n| Digest::SHA256.hexdigest("file #{n}") }
    rows_imported { 1 }
  end
end
