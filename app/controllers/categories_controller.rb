class CategoriesController < ApplicationController
  def index
    @categories = Category.order(:name)
    @category = Category.new
  end

  def create
    @category = Category.new(category_params)

    if @category.save
      redirect_to categories_path, notice: "Category created."
    else
      @categories = Category.order(:name)
      render :index, status: :unprocessable_entity
    end
  end

  private
    def category_params
      params.expect(category: [ :name ])
    end
end
