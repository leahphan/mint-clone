FactoryBot.define do
  factory :category do
    sequence(:name) { |n| "Category #{n}" }
    category_type { "expense" }

    trait :income do
      category_type { "income" }
    end
  end
end
