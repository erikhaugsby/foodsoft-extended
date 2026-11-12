require 'spec_helper'

# Safety checks for the management API (suppliers, articles, orders, invoices):
# each change needs both the right token scope and the right role, fields the
# user must not control are ignored, and probe requests change nothing.
describe 'Management API safety' do
  def all_scopes
    Doorkeeper.configuration.scopes.to_a.map(&:to_s)
  end

  let(:supplier) { create(:supplier, article_count: 2) }
  let(:other_supplier) { create(:supplier, article_count: 1) }
  let(:article) { supplier.articles.first }
  let(:order) { create(:order, supplier: supplier, article_ids: supplier.articles.map(&:id)) }
  let(:invoice) { create(:invoice, supplier: supplier) }
  let(:json) { response.parsed_body }

  # a member of a workgroup with every management role, plus an ordergroup
  def powerful_user
    user = create(:user, :ordergroup)
    create(:workgroup, role_orders: true, role_article_meta: true, role_suppliers: true, role_invoices: true,
                       role_finance: true, role_pickups: true, user_ids: [user.id])
    user
  end

  def headers_for(user, scopes)
    token = create(:oauth2_access_token, resource_owner_id: user.id, scopes: scopes.join(' ')).token
    { 'Authorization' => "Bearer #{token}", 'Accept' => 'application/json' }
  end

  def call(verb, path, headers, params = nil)
    process verb, "/f/api/v1#{path}", headers: headers, params: params, as: (params ? :json : nil)
  end

  # [verb, path, body, scope it needs]
  def write_endpoints
    [
      [:post, '/articles', { article: { supplier_id: supplier.id, name: 'X', unit: '1 kg', unit_quantity: 1, price: 1, tax: 10,
                                        deposit: 0, article_category_id: article.article_category_id } }, 'articles:write'],
      [:patch, "/articles/#{article.id}", { article: { name: 'Changed' } }, 'articles:write'],
      [:delete, "/articles/#{article.id}", nil, 'articles:write'],
      [:post, '/orders', { order: { supplier_id: supplier.id } }, 'orders:write'],
      [:patch, "/orders/#{order.id}", { order: { note: 'Changed' } }, 'orders:write'],
      [:post, "/orders/#{order.id}/finish", nil, 'orders:write'],
      [:post, '/invoices', { invoice: { supplier_id: supplier.id, number: '1', amount: 1 } }, 'invoices:write'],
      [:patch, "/invoices/#{invoice.id}", { invoice: { note: 'Changed' } }, 'invoices:write']
    ]
  end

  it 'refuses every change when the token lacks the needed scope, even for a user with every role' do
    user = powerful_user
    write_endpoints.each do |verb, path, body, scope|
      call verb, path, headers_for(user, all_scopes - [scope]), body
      expect(response).to have_http_status(:forbidden), "#{verb} #{path} without #{scope}: #{response.status}"
    end
  end

  it 'refuses every change by a member without roles, even with every scope' do
    user = create(:user, :ordergroup)
    write_endpoints.each do |verb, path, body, _scope|
      call verb, path, headers_for(user, all_scopes), body
      expect(response).to have_http_status(:forbidden), "#{verb} #{path} by a member: #{response.status}"
    end
    expect(article.reload.name).not_to eq 'Changed'
    expect(order.reload).to be_open
    expect(order.note).not_to eq 'Changed'
  end

  it 'refuses management reads by a member without roles, even with every scope' do
    user = create(:user, :ordergroup)
    ['/suppliers', "/suppliers/#{supplier.id}", '/articles', "/articles/#{article.id}", '/invoices',
     "/invoices/#{invoice.id}", "/orders/#{order.id}/documents/groups"].each do |path|
      call :get, path, headers_for(user, all_scopes)
      expect(response).to have_http_status(:forbidden), "GET #{path} by a member: #{response.status}"
    end
  end

  describe 'fields the user must not control' do
    let(:user) { powerful_user }
    let(:headers) { headers_for(user, all_scopes) }
    let(:someone_else) { create(:user) }

    it 'keeps an article with its supplier' do
      call :patch, "/articles/#{article.id}", headers, { article: { supplier_id: other_supplier.id } }
      expect(article.reload.supplier_id).to eq supplier.id
    end

    it 'opens orders as open, created by the current user, with articles of their own supplier only' do
      foreign_article = other_supplier.articles.first
      call :post, '/orders', headers,
           { order: { supplier_id: supplier.id, state: 'closed', created_by_user_id: someone_else.id,
                      article_ids: [article.id, foreign_article.id] } }
      expect(response).to have_http_status(:created)
      created = Order.find(json['order']['id'])
      expect(created).to be_open
      expect(created.created_by).to eq user
      expect(created.article_ids.map(&:to_i)).to eq [article.id]
    end

    it 'does not change the state of an order through update' do
      call :patch, "/orders/#{order.id}", headers, { order: { state: 'closed' } }
      expect(order.reload).to be_open
    end

    it 'records the current user as creator of an invoice' do
      call :post, '/invoices', headers,
           { invoice: { supplier_id: supplier.id, number: '7', amount: 3, created_by_user_id: someone_else.id } }
      expect(Invoice.find(json['invoice']['id']).created_by).to eq user
    end

    it 'ignores paid_on from members without the finance role' do
      invoices_only = create(:user, :role_invoices)
      call :post, '/invoices', headers_for(invoices_only, all_scopes),
           { invoice: { supplier_id: supplier.id, number: '8', amount: 3, paid_on: Date.current } }
      expect(response).to have_http_status(:created)
      expect(Invoice.find(json['invoice']['id']).paid_on).to be_nil
    end
  end

  describe 'invoices of others and their files' do
    let(:invoices_user) { create(:user, :role_invoices) }
    let(:headers) { headers_for(invoices_user, all_scopes) }
    let(:pdf) { Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4\n%%EOF\n"), 'application/pdf', original_filename: 'r.pdf') }

    it 'refuses changing an invoice someone else created' do
      call :patch, "/invoices/#{invoice.id}", headers, { invoice: { note: 'Changed' } }
      expect(response).to have_http_status(:forbidden)
      process :post, "/f/api/v1/invoices/#{invoice.id}/attachments", headers: headers, params: { attachments: [pdf] }
      expect(response).to have_http_status(:forbidden)
      expect(invoice.reload.attachments).to be_empty
    end

    it 'does not hand out a file through another invoice' do
      invoice.attachments.attach(io: StringIO.new("%PDF-1.4\n%%EOF\n"), filename: 'a.pdf', content_type: 'application/pdf')
      other_invoice = create(:invoice, supplier: supplier)
      attachment_id = invoice.attachments.first.id
      call :get, "/invoices/#{other_invoice.id}/attachments/#{attachment_id}", headers
      expect(response).to have_http_status(:not_found)
    end

    it 'refuses files that only pretend to be a PDF' do
      html = Rack::Test::UploadedFile.new(StringIO.new('<html><script>alert(1)</script></html>'), 'application/pdf',
                                          original_filename: 'fake.pdf')
      process :post, '/f/api/v1/invoices', headers: headers,
                                           params: { invoice: { supplier_id: supplier.id, number: '9', amount: 1 }, attachments: [html] }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Invoice.where(number: '9')).to be_empty
    end
  end

  describe 'token scope and role must match' do
    it 'refuses suppliers to a token for reading articles held by a member of the invoices team' do
      call :get, '/suppliers', headers_for(create(:user, :role_invoices), ['articles:read'])
      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses articles to an orders token held by an article manager without the orders role' do
      call :get, '/articles', headers_for(create(:user, :role_article_meta), ['orders:write'])
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'linking invoices to orders' do
    let(:user) { create(:user, :role_invoices) }
    let(:headers) { headers_for(user, all_scopes) }
    let(:paid_invoice) { create(:invoice, supplier: other_supplier, paid_on: Date.current) }
    let(:foreign_order) { create(:order, supplier: other_supplier).tap { |o| o.update!(invoice: paid_invoice) } }

    it 'refuses orders of another supplier or another invoice' do
      call :post, '/invoices', headers, { invoice: { supplier_id: supplier.id, number: '10', amount: 1,
                                                     order_ids: [foreign_order.id] } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(foreign_order.reload.invoice).to eq paid_invoice
    end

    it 'refuses moving an order of the same supplier away from another invoice' do
      own = create(:invoice, supplier: supplier, created_by: user)
      taken = create(:order, supplier: supplier).tap { |o| o.update!(invoice: invoice) }
      call :patch, "/invoices/#{own.id}", headers, { invoice: { order_ids: [taken.id] } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(taken.reload.invoice).to eq invoice
    end

    it 'links a free order of the same supplier' do
      call :post, '/invoices', headers, { invoice: { supplier_id: supplier.id, number: '11', amount: 1,
                                                     order_ids: [order.id] } }
      expect(response).to have_http_status(:created)
      expect(order.reload.invoice_id).to eq json['invoice']['id']
    end
  end

  describe 'invoice files' do
    let(:headers) { headers_for(create(:user, :role_finance), all_scopes) }

    def upload(content, type, name)
      file = Rack::Test::UploadedFile.new(StringIO.new(content), type, original_filename: name)
      process :post, '/f/api/v1/invoices', headers: headers,
                                           params: { invoice: { supplier_id: supplier.id, number: name, amount: 1 },
                                                     attachments: [file] }
    end

    it 'refuses unknown content named and declared as an image' do
      upload(Random.bytes(2000), 'image/png', 'x.png')
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'refuses files over 10 MB' do
      upload("%PDF-1.4\n#{'0' * 10.megabytes}\n%%EOF\n", 'application/pdf', 'big.pdf')
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'accepts a real PDF and stores its content' do
      upload("%PDF-1.4\n%%EOF\n", 'application/pdf', 'ok.pdf')
      expect(response).to have_http_status(:created)
      expect(Invoice.find(json['invoice']['id']).attachments.first.download).to start_with('%PDF')
    end
  end

  describe 'the app’s probe requests change nothing' do
    it 'answers 403 to members without the orders role and changes no order' do
      user = create(:user, :ordergroup)
      call :patch, "/orders/#{order.id}", headers_for(user, all_scopes), { order: {} }
      expect(response).to have_http_status(:forbidden)
      call :patch, '/orders/0', headers_for(user, all_scopes), { order: {} }
      expect(response).to have_http_status(:forbidden)
      expect(order.reload.updated_by).not_to eq user
    end

    it 'answers 404 to the orders role for order 0' do
      user = create(:user, :role_orders)
      call :patch, '/orders/0', headers_for(user, all_scopes), { order: {} }
      expect(response).to have_http_status(:not_found)
      call :get, '/orders/0/documents/groups', headers_for(user, all_scopes)
      expect(response).to have_http_status(:not_found)
    end
  end
end
