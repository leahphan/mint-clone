require "test_helper"

class SessionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, email_address: "leah@example.com", password: "correct horse battery staple")
  end

  test "signed-out visitors are sent to sign in, then back to the page they asked for" do
    account = create(:account, user: @user)

    get account_path(account)
    assert_redirected_to new_session_path

    follow_redirect!
    assert_select "h1", text: "Sign in"
    assert_select "nav", count: 0

    post session_path, params: { email_address: "LEAH@example.com ", password: "correct horse battery staple" }
    assert_redirected_to account_url(account)
    follow_redirect!
    assert_response :success
  end

  test "a form submitted after the session was revoked goes to the dashboard after signing in again" do
    category = create(:category, user: @user, name: "Groceries")
    sign_in_as @user
    @user.sessions.destroy_all

    patch category_path(category), params: { category: { name: "Food" } }
    assert_redirected_to new_session_path
    assert_equal "Groceries", category.reload.name

    post session_path, params: { email_address: "leah@example.com", password: "correct horse battery staple" }
    assert_redirected_to root_url
  end

  test "signing in goes to the dashboard" do
    post session_path, params: { email_address: "leah@example.com", password: "correct horse battery staple" }

    assert_redirected_to root_url
    follow_redirect!
    assert_select "button", text: "Sign out"
  end

  test "a wrong password doesn't sign in" do
    assert_no_difference "Session.count" do
      post session_path, params: { email_address: "leah@example.com", password: "wrong" }
    end

    assert_redirected_to new_session_path
    follow_redirect!
    assert_select "p", text: "Try another email address or password."
    get root_path
    assert_redirected_to new_session_path
  end

  test "signing out ends the session" do
    post session_path, params: { email_address: "leah@example.com", password: "correct horse battery staple" }

    assert_difference "Session.count", -1 do
      delete session_path
    end

    assert_redirected_to new_session_path
    get root_path
    assert_redirected_to new_session_path
  end

  test "every page needs a signed-in user except the health check" do
    get root_path
    assert_redirected_to new_session_path
    post accounts_path, params: { account: { name: "Chequing", account_type: "chequing" } }
    assert_redirected_to new_session_path
    assert_equal 0, Account.count

    get rails_health_check_path
    assert_response :success
  end
end
