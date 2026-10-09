require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "gives every user the default categories once" do
    users = create_list(:user, 2)

    load_seeds
    assert_no_difference "Category.count" do
      load_seeds
    end

    assert_equal [ 19, 19 ], users.map { |user| user.categories.count }
  end

  private
    def load_seeds
      load Rails.root.join("db/seeds.rb")
    end
end
