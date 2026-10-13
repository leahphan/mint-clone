class CategoriesController < ApplicationController
  def index
    @categories = Current.user.categories.order(:name)
    @category = Current.user.categories.new
  end

  def create
    @category = Current.user.categories.new(category_params)

    if @category.save
      redirect_to categories_path, notice: "Category created."
    else
      @categories = Current.user.categories.order(:name)
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    @category = Current.user.categories.find(params[:id])
  end

  def update
    @category = Current.user.categories.find(params[:id])

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
