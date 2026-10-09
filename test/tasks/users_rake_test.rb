require "test_helper"
require "rake"
require "io/console"

class UsersRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.none?
    Rake::Task["users:set_password"].reenable
  end

  test "creates a user with the default categories" do
    assert_output(/Created leah@example.com with the default categories/) do
      set_password("Leah@Example.com", "correct horse battery staple")
    end

    user = User.find_by!(email_address: "leah@example.com")
    assert user.authenticate("correct horse battery staple")
    assert_equal 19, user.categories.count
  end

  test "changes an existing user's password and signs them out everywhere" do
    user = create(:user, email_address: "leah@example.com", password: "old password")
    user.sessions.create!
    create(:category, user: user, name: "Groceries")

    assert_output(/Changed the password for leah@example.com and signed it out everywhere/) do
      set_password("leah@example.com", "new password")
    end

    user.reload
    assert user.authenticate("new password")
    assert_not user.authenticate("old password")
    assert_empty user.sessions
    assert_equal [ "Groceries" ], user.categories.pluck(:name)
  end

  test "aborts without an email, with a blank password, or when the passwords don't match" do
    user = create(:user, email_address: "leah@example.com", password: "old password")

    assert_aborts(/Usage/) { set_password("", "anything") }
    assert_aborts(/can't be blank/) { set_password("leah@example.com", " ") }
    assert_aborts(/don't match/) { set_password("leah@example.com", "new password", confirmation: "typo") }

    assert user.reload.authenticate("old password")
    assert_equal 1, User.count
  end

  private
    def set_password(email, password, confirmation: password)
      answers = [ password, confirmation ]
      with_email(email) do
        $stdin.stub(:getpass, ->(_prompt) { answers.shift }) do
          Rake::Task["users:set_password"].invoke
        end
      end
    ensure
      Rake::Task["users:set_password"].reenable
    end

    def with_email(email)
      previous = ENV["EMAIL"]
      ENV["EMAIL"] = email
      yield
    ensure
      ENV["EMAIL"] = previous
    end

    def assert_aborts(message)
      assert_output(nil, message) do
        assert_raises(SystemExit) { yield }
      end
    end
end
