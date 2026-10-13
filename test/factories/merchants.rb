FactoryBot.define do
  factory :merchant do
    user
    sequence(:key) { |n| "MERCHANT #{n}" }
    name { key.titleize }
  end
end
