FactoryBot.define do
  factory :merchant do
    sequence(:key) { |n| "MERCHANT #{n}" }
    name { key.titleize }
  end
end
