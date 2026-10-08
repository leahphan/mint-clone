namespace :transactions do
  desc "Categorize existing uncategorized transactions (learned merchants first, then AI if enabled)"
  task categorize: :environment do
    uncategorized = Transaction.where(category_id: nil)
    before = uncategorized.count
    ai = TransactionCategorizer.default_classifier ? "on" : "off (set AI_CATEGORIZATION_ENABLED=true to use it)"
    puts "Categorizing #{before} uncategorized transactions. AI fallback is #{ai}."

    uncategorized.in_batches(of: 500) { |batch| TransactionCategorizer.call(batch) }

    remaining = uncategorized.count
    puts "Categorized #{before - remaining}; #{remaining} still uncategorized."
  end
end
