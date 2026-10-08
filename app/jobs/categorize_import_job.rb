class CategorizeImportJob < ApplicationJob
  def perform(import)
    TransactionCategorizer.call(import.transactions)
  end
end
