# Default categories. Idempotent: run it any time with bin/rails db:seed.
# Categories that already exist (matched by name, ignoring case) are left as they are.
# Uncategorized is a transaction with no category, not a record. Misc is the
# catch-all for known expenses that don't fit another category.
{
  "income" => [ "Income" ],
  "expense" => [
    "Housing", "Groceries", "Restaurants & Dining", "Transportation", "Utilities", "Shopping",
    "Entertainment", "Health & Medical", "Personal Care", "Kids & Family", "Travel", "Education",
    "Gifts & Donations", "Fees & Charges", "Taxes", "Misc"
  ],
  "transfer" => [ "Transfer", "Credit Card Payment" ]
}.each do |category_type, names|
  names.each do |name|
    Category.where("LOWER(name) = LOWER(?)", name).first_or_create!(name: name, category_type: category_type)
  end
end
