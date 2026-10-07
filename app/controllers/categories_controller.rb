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

  def edit
    @category = Category.find(params[:id])
  end

  def update
    @category = Category.find(params[:id])

    if @category.update(category_params)
      redirect_to categories_path, notice: "Category updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def category_params
      params.expect(category: [ :name, :category_type ])
    end
end
