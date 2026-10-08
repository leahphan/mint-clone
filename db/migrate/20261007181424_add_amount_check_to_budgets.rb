class AddAmountCheckToBudgets < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :budgets, "amount > 0", name: "budgets_amount_positive"
  end
end
