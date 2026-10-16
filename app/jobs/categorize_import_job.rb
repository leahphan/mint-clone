# Categorizes the transactions an import couldn't categorize from known merchants, with the
# AI classifier, then marks the import done so its pages stop showing "Categorizing…".
class CategorizeImportJob < ApplicationJob
  def perform(import)
    TransactionCategorizer.call(import.transactions, user: import.account.user)
  ensure
    import.update!(categorizing_since: nil)
  end
end
