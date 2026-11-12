# Runs the app's API calls (docs/app-spec.md, section 8, in erikhaugsby/foodsoft-test)
# against a running Foodsoft over real HTTP: sign-in, ordering, management, PDFs,
# invoices with files, refresh and sign-out. Plain Ruby, no gems.
#   ruby script/e2e/app_flow.rb http://127.0.0.1:3000/f <app id>
require 'json'
require 'net/http'
require 'securerandom'
require 'uri'

BASE = ARGV.fetch(0)
APP_ID = ARGV.fetch(1)
SCOPES = 'config:user user:read orders:read group_orders:user offline_access orders:write articles:write invoices:write'.freeze
PDF = "%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n".freeze
@failures = []

def http(method, path, token: nil, json: nil, form: nil, multipart: nil)
  uri = URI(path.start_with?('http') ? path : "#{BASE}#{path}")
  req = Net::HTTP.const_get(method.to_s.capitalize).new(uri)
  req['Accept'] = 'application/json'
  req['Authorization'] = "Bearer #{token}" if token
  if json
    req['Content-Type'] = 'application/json'
    req.body = JSON.generate(json)
  elsif form
    req.set_form_data(form)
  elsif multipart
    req.set_form(multipart, 'multipart/form-data')
  end
  Net::HTTP.start(uri.host, uri.port) { |h| h.request(req) }
end

def body(res)
  JSON.parse(res.body)
rescue JSON::ParserError
  {}
end

def check(name, passed, detail = nil)
  puts "#{passed ? 'ok  ' : 'FAIL'} #{name}#{" (#{detail})" if !passed && detail}"
  @failures << name unless passed
  passed
end

def expect_status(name, res, *codes)
  check(name, codes.include?(res.code.to_i), "got #{res.code}: #{res.body.to_s[0, 300]}")
end

def sign_in(user)
  res = http(:post, '/oauth/token', form: { grant_type: 'password', username: "#{user}@example.org",
                                            password: 'e2e-secret-password', client_id: APP_ID, scope: SCOPES })
  expect_status("#{user} signs in with the app's scopes", res, 200)
  body(res)
end

# --- sign-in
manager = sign_in('manager')
member = sign_in('member')
m = manager['access_token']
u = member['access_token']
check('granted scopes include the write scopes', manager['scope'].to_s.split.include?('orders:write'))
expect_status('GET /config (version)', http(:get, '/api/v1/config', token: m), 200)

# --- capability checks (section 5)
expect_status('probe: suppliers', http(:get, '/api/v1/suppliers?per_page=1', token: m), 200)
expect_status('probe: orders as manager', http(:patch, '/api/v1/orders/0', token: m, json: { order: {} }), 404)
expect_status('probe: PDFs as manager', http(:get, '/api/v1/orders/0/documents/groups', token: m), 404)
expect_status('probe: articles as manager', http(:patch, '/api/v1/articles/0', token: m, json: { article: {} }), 404)
expect_status('probe: invoices as manager', http(:get, '/api/v1/invoices?per_page=1', token: m), 200)
expect_status('probe: orders as member', http(:patch, '/api/v1/orders/0', token: u, json: { order: {} }), 403)
expect_status('probe: PDFs as member', http(:get, '/api/v1/orders/0/documents/groups', token: u), 403)
expect_status('probe: articles as member', http(:patch, '/api/v1/articles/0', token: u, json: { article: {} }), 403)
expect_status('probe: invoices as member', http(:get, '/api/v1/invoices?per_page=1', token: u), 403)

# --- open an order
supplier = body(http(:get, '/api/v1/suppliers', token: m))['suppliers'].first
articles = body(http(:get, "/api/v1/articles?q[supplier_id_eq]=#{supplier['id']}", token: m))['articles']
check('articles of the supplier', articles.size == 3, articles.size)
res = http(:post, '/api/v1/orders', token: m,
                                    json: { order: { supplier_id: supplier['id'], note: 'E2E', article_ids: articles.first(2).map { |a| a.fetch('id') } } })
expect_status('POST /orders', res, 201)
order_id = body(res).dig('order', 'id')
open_ids = body(http(:get, '/api/v1/orders?q[state_eq]=open', token: u))['orders'].map { |o| o.fetch('id') }
check('member sees the open order', open_ids.include?(order_id))
expect_status('PATCH /orders (choose articles)',
              http(:patch, "/api/v1/orders/#{order_id}", token: m, json: { order: { article_ids: articles.map { |a| a.fetch('id') } } }), 200)
expect_status('member cannot open orders', http(:post, '/api/v1/orders', token: u, json: { order: { supplier_id: supplier['id'] } }), 403)

# --- member orders
order_articles = body(http(:get, "/api/v1/order_articles?q[order_id_eq]=#{order_id}", token: u))['order_articles']
check('three order articles', order_articles.size == 3, order_articles.size)
res = http(:post, '/api/v1/user/group_order_articles', token: u,
                                                       json: { group_order_article: { order_article_id: order_articles.first['id'], quantity: 2, tolerance: 0 } })
expect_status('member orders an article', res, 201)
goa_id = body(res).dig('group_order_article', 'id')
expect_status('member changes the quantity',
              http(:patch, "/api/v1/user/group_order_articles/#{goa_id}", token: u, json: { group_order_article: { quantity: 3 } }), 200)
group_orders = body(http(:get, "/api/v1/user/group_orders?q[order_id_in][]=#{order_id}", token: u))['group_orders'] || []
check('who ordered last', group_orders.first&.dig('updated_by_name').to_s.include?('Member'), group_orders.inspect)

# --- close the order, PDFs
res = http(:post, "/api/v1/orders/#{order_id}/finish", token: m)
expect_status('POST /orders/:id/finish', res, 200)
check('order is finished', body(res).dig('order', 'state') == 'finished')
%w[groups articles matrix fax].each do |doc|
  res = http(:get, "/api/v1/orders/#{order_id}/documents/#{doc}", token: m)
  expect_status("PDF #{doc}", res, 200)
  check("PDF #{doc} is a PDF", res.body.to_s.start_with?('%PDF'))
end

# --- invoices with files
invoice_form = [['invoice[supplier_id]', supplier['id'].to_s], ['invoice[number]', 'E2E-1'],
                ['invoice[amount]', '12.5'], ['invoice[order_ids][]', order_id.to_s],
                ['attachments[]', PDF, { filename: 'receipt.pdf', content_type: 'application/pdf' }]]
res = http(:post, '/api/v1/invoices', token: m, multipart: invoice_form)
expect_status('POST /invoices with a file', res, 201)
invoice = body(res)['invoice'] || {}
check('invoice linked to the order', invoice['order_ids'] == [order_id], invoice['order_ids'])
file_id = invoice.dig('attachments', 0, 'id')
res = http(:get, "/api/v1/invoices/#{invoice['id']}/attachments/#{file_id}", token: m)
expect_status('download the file', res, 200)
check('file content intact', res.body == PDF)
fake = [['attachments[]', '<html>x</html>', { filename: 'fake.pdf', content_type: 'application/pdf' }]]
res = http(:post, "/api/v1/invoices/#{invoice['id']}/attachments", token: m, multipart: fake)
expect_status('a fake PDF is refused', res, 422)
expect_status('PATCH /invoices (paid)', http(:patch, "/api/v1/invoices/#{invoice['id']}", token: m,
                                                                                         json: { invoice: { paid_on: Time.now.strftime('%F'), deposit: 1 } }), 200)
expect_status('delete the file', http(:delete, "/api/v1/invoices/#{invoice['id']}/attachments/#{file_id}", token: m), 200)

# --- articles
res = http(:post, '/api/v1/articles', token: m,
                                      json: { article: { supplier_id: supplier['id'], name: 'Garlic (E2E)', unit: '100 g', unit_quantity: 1,
                                                         price: 1.2, tax: 10, deposit: 0, article_category_id: articles.first['article_category_id'] } })
expect_status('POST /articles', res, 201)
article_id = body(res).dig('article', 'id')
expect_status('PATCH /articles', http(:patch, "/api/v1/articles/#{article_id}", token: m, json: { article: { price: 1.3 } }), 200)
expect_status('DELETE /articles', http(:delete, "/api/v1/articles/#{article_id}", token: m), 200, 204)

# --- refresh and sign-out
res = http(:post, '/oauth/token', form: { grant_type: 'refresh_token', refresh_token: manager['refresh_token'], client_id: APP_ID })
expect_status('refresh the token', res, 200)
fresh = body(res)['access_token']
expect_status('the new token works', http(:get, '/api/v1/config', token: fresh), 200)
expect_status('sign out', http(:post, '/oauth/revoke', form: { token: fresh, client_id: APP_ID }), 200)
expect_status('the revoked token is refused', http(:get, '/api/v1/config', token: fresh), 401)

puts
if @failures.empty?
  puts 'All end-to-end checks passed.'
else
  puts "#{@failures.size} end-to-end checks failed: #{@failures.join('; ')}"
  exit 1
end
