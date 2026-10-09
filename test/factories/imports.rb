FactoryBot.define do
  factory :import do
    account
    filename { "transactions.csv" }
    sequence(:checksum) { |n| Digest::SHA256.hexdigest("file #{n}") }
    rows_imported { 1 }
    status { "completed" }

    trait :pending do
      status { "pending" }
      content { "2026-09-01,Loblaws,-54.32\n" }
      rows_imported { 0 }
    end
  end
end
