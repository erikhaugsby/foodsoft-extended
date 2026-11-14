module SessionHelper
  def login(user = nil, password = nil)
    visit login_path
    user = FactoryBot.create(:user) if user.nil?
    if user.instance_of? ::User
      nick = user.nick
      password = user.password
    else
      nick = user
    end
    fill_in 'nick', with: nick
    fill_in 'password', with: password
    find('input[type=submit]').click
    # wait until the login went through, so the next visit is not sent while still logged out
    expect(page).to have_no_field('password')
  end
end
