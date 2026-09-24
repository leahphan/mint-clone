FactoryBot.define do
  factory :transaction do
    account
    transaction_date { Date.current }
    description { "Groceries" }
    amount { "-84.37" }
  end
end
