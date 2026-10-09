FactoryBot.define do
  factory :account do
    user
    name { "Everyday Chequing" }
    account_type { "chequing" }
  end
end
