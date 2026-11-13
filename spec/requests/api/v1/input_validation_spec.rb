require 'spec_helper'

# Wrong types in API requests get a clear 422 instead of being misread or crashing:
# whole numbers, ids, dates, booleans and request objects.
describe 'API input validation' do
  let(:user) do
    user = create(:user, groups: [create(:ordergroup)])
    create(:workgroup, role_orders: true, role_article_meta: true, role_invoices: true, role_finance: true,
                       user_ids: [user.id])
    user
  end
  let(:scopes) do
    'group_orders:user orders:read orders:write articles:read articles:write invoices:read invoices:write ' \
      'finance:user messages:read messages:write'
  end
  let(:headers) do
    { 'Authorization' => "Bearer #{create(:oauth2_access_token, resource_owner_id: user.id, scopes: scopes).token}" }
  end
  let(:json) { response.parsed_body }
  let(:order) { create(:order, article_count: 2) }
  let(:group_order) { create(:group_order, ordergroup: user.ordergroup, order_id: order.id) }
  let(:goa) { create(:group_order_article, group_order: group_order, order_article: order.order_articles.first, quantity: 2) }
  let(:article) { order.supplier.articles.first }

  def api(method, path, params = nil)
    process method, "/f/api/v1#{path}", headers: headers, params: params, as: (params && method != :get ? :json : nil)
  end

  describe 'whole numbers' do
    ['abc', 2.9, '2,5', '1e3', [3], true, '-1'].each do |value|
      it "refuses quantity #{value.inspect} and keeps the ordered article" do
        api :patch, "/user/group_order_articles/#{goa.id}", { group_order_article: { quantity: value } }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(goa.reload.quantity).to eq 2
      end
    end

    it 'accepts "3" and 3' do
      api :patch, "/user/group_order_articles/#{goa.id}", { group_order_article: { quantity: '3' } }
      expect(goa.reload.quantity).to eq 3
      api :patch, "/user/group_order_articles/#{goa.id}", { group_order_article: { quantity: 4 } }
      expect(goa.reload.quantity).to eq 4
    end

    it 'refuses a fractional unit quantity' do
      api :patch, "/articles/#{article.id}", { article: { unit_quantity: 2.5 } }
      expect(response).to have_http_status(:unprocessable_entity)
      api :patch, "/articles/#{article.id}", { article: { unit_quantity: 6 } }
      expect(article.reload.unit_quantity).to eq 6
    end

    it 'does not find path ids with letters (no longer read as the number in front)' do
      api :get, "/orders/#{order.id}abc"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'request objects' do
    it 'refuses a text where an object belongs' do
      api :post, '/user/group_order_articles', { group_order_article: 'x' }
      expect(response).to have_http_status(:unprocessable_entity)
      api :patch, "/orders/#{order.id}", { order: 'x' }
      expect(response).to have_http_status(:unprocessable_entity)
      api :post, '/messages', { message: 'hi' }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'answers a missing object with a JSON 400' do
      api :patch, "/orders/#{order.id}", { other: 1 }
      expect(response).to have_http_status(:bad_request)
      expect(json['error']).to eq 'bad_request'
    end
  end

  describe 'id lists' do
    it 'refuses recipient ids as one text or an object' do
      api :post, '/messages', { message: { subject: 's', body: 'b', recipient_ids: '3,4' } }
      expect(response).to have_http_status(:unprocessable_entity)
      api :post, '/messages', { message: { subject: 's', body: 'b', recipient_ids: { a: 1 } } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'dates' do
    %w[garbage 2026-02-31T10:00:00Z 31.12.2026 2026-12-31T25:00].each do |value|
      it "refuses #{value.inspect} as end date and keeps the old one" do
        old_ends = order.ends
        api :patch, "/orders/#{order.id}", { order: { ends: value } }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(order.reload.ends).to eq old_ends
      end
    end

    it 'accepts ISO dates and times' do
      api :patch, "/orders/#{order.id}", { order: { ends: '2099-12-31' } }
      expect(response).to have_http_status(:ok)
      api :patch, "/orders/#{order.id}", { order: { ends: '2099-12-31T18:00:00+01:00' } }
      expect(response).to have_http_status(:ok)
    end

    it 'refuses an invoice with an impossible date' do
      api :post, '/invoices', { invoice: { supplier_id: order.supplier_id, number: 'D1', amount: 1, date: '31.13.2026' } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Invoice.where(number: 'D1')).to be_empty
    end
  end

  describe 'booleans' do
    it 'refuses "no" for ignore_warnings and keeps the order articles' do
      api :patch, "/orders/#{order.id}", { order: { ignore_warnings: 'no', article_ids: [] } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(order.reload.order_articles.count).to eq 2
    end
  end

  describe 'lists and search' do
    before { create_list(:order, 3) }

    it 'refuses page sizes below 1 and page lists' do
      api :get, '/orders?per_page=-1'
      expect(response).to have_http_status(:unprocessable_entity)
      api :get, '/orders?page[]=1'
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rounds the number of pages up' do
      api :get, '/orders?per_page=2'
      expect(json['meta']['total_pages']).to eq (json['meta']['total_count'] / 2.0).ceil
    end

    it 'refuses a search that is not an object' do
      api :get, '/order_articles?q=abc'
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it 'answers 422 for a stock order with article ids' do
    stock_order = create(:stock_order)
    api :patch, "/orders/#{stock_order.id}", { order: { article_ids: [1] } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'answers 422 for a self-service payment without amount' do
    FoodsoftConfig.config[:use_self_service] = true
    type = create(:financial_transaction_type)
    api :post, '/user/financial_transactions', { financial_transaction: { financial_transaction_type_id: type.id, note: 'x' } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(user.ordergroup.financial_transactions).to be_empty
  end
end
