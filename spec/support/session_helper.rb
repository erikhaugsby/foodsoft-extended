module SessionHelper
  # Logs in through the login form. With a user (or none), it waits until the login went
  # through and retries a failed attempt: the headless browser can drop keystrokes while
  # typing. With a nick and password, it submits once and doesn't wait, so tests can check
  # failed logins.
  def login(user = nil, password = nil)
    return submit_login(user, password) unless user.nil? || user.instance_of?(::User)

    user = FactoryBot.create(:user) if user.nil?
    3.times do
      submit_login(user.nick, user.password)
      return if page.has_no_field?('password', wait: 5)
    end
    raise "Login failed three times for #{user.nick}"
  end

  private

  def submit_login(nick, password)
    visit login_path
    fill_in 'nick', with: nick
    fill_in 'password', with: password
    find('input[type=submit]').click
  end
end
