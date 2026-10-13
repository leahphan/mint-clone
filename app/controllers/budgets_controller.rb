class BudgetsController < ApplicationController
  before_action :set_budget, only: %i[edit update destroy]

  def index
    @budgets = Current.user.budgets.by_category_name.to_a
  end

  def new
    @budget = Budget.new
    @categories = unbudgeted_categories
  end

  def create
    attributes = params.expect(budget: [ :category_id, :amount ])
    @budget = Budget.new(amount: attributes[:amount], category: Current.user.categories.find_by(id: attributes[:category_id]))

    if @budget.save
      redirect_to budgets_path, notice: "Budget created."
    else
      render_new
    end
  rescue ActiveRecord::RecordNotUnique
    @budget.errors.add(:category_id, :taken)
    render_new
  end

  def edit
  end

  def update
    if @budget.update(params.expect(budget: [ :amount ]))
      redirect_to budgets_path, notice: "Budget updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @budget.destroy
    redirect_to budgets_path, notice: "Budget removed.", status: :see_other
  end

  private
    def set_budget
      @budget = Current.user.budgets.find(params[:id])
    end

    def render_new
      @categories = unbudgeted_categories
      render :new, status: :unprocessable_entity
    end

    def unbudgeted_categories
      Current.user.categories.budgetable.where.missing(:budget).order(:name)
    end
end
