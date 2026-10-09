class CategorizeImportJob < ApplicationJob
  def perform(import)
    TransactionCategorizer.call(import.transactions, user: import.account.user)
  end
end
