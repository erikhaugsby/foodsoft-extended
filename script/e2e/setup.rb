# Creates the data for the end-to-end API run (rails runner script/e2e/setup.rb).
# Writes the OAuth App ID to tmp/e2e_app_id.
category = ArticleCategory.create!(name: 'Vegetables')
supplier = Supplier.create!(name: 'E2E Farm', phone: '+43 1 2345678', address: 'Farm Road 1, Vienna')
%w[Carrots Potatoes Onions].each do |name|
  supplier.articles.create!(name: "#{name} (organic)", unit: '1 kg', unit_quantity: 1, price: 2.5, tax: 10,
                            deposit: 0, article_category: category, availability: true)
end

def user(nick, first_name)
  User.create!(nick: nick, first_name: first_name, last_name: 'E2E', email: "#{nick}@example.org",
               password: 'e2e-secret-password')
end

manager = user('manager', 'Manager')
member = user('member', 'Member')
Workgroup.create!(name: 'Management', role_orders: true, role_article_meta: true, role_suppliers: true,
                  role_invoices: true, role_finance: true, user_ids: [manager.id])
Ordergroup.create!(name: 'Household Manager', user_ids: [manager.id])
Ordergroup.create!(name: 'Household Member', user_ids: [member.id])

app = Doorkeeper::Application.create!(name: 'Foodsoft App', redirect_uri: 'urn:ietf:wg:oauth:2.0:oob',
                                      confidential: false)
File.write(Rails.root.join('tmp/e2e_app_id'), app.uid)
puts "E2E data ready, App ID #{app.uid}"
