class BudgetsController < ApplicationController
  before_action :set_budget, only: %i[edit update destroy]

  def index
    @budgets = Budget.by_category_name.to_a
  end

  def new
    @budget = Budget.new
    @categories = unbudgeted_categories
  end

  def create
    @budget = Budget.new(params.expect(budget: [ :category_id, :amount ]))

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
      @budget = Budget.find(params[:id])
    end

    def render_new
      @categories = unbudgeted_categories
      render :new, status: :unprocessable_entity
    end

    def unbudgeted_categories
      Category.where.missing(:budget).order(:name)
    end
end
