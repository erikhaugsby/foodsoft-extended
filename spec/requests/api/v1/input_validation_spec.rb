require 'spec_helper'

# Wrong types in API requests get a clear 422 instead of being misread or crashing:
# numbers, whole numbers, ids and request objects.
describe 'API input validation' do
  let(:user) { create(:user, groups: [create(:ordergroup)]) }
  let(:headers) do
    token = create(:oauth2_access_token, resource_owner_id: user.id, scopes: 'group_orders:user orders:read finance:user')
    { 'Authorization' => "Bearer #{token.token}" }
  end
  let(:json) { response.parsed_body }
  let(:order) { create(:order, article_count: 2) }
  let(:group_order) { create(:group_order, ordergroup: user.ordergroup, order_id: order.id) }
  let(:goa) { create(:group_order_article, group_order: group_order, order_article: order.order_articles.first, quantity: 2) }

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

    it 'answers 422 instead of crashing for a number the database cannot hold' do
      api :patch, "/user/group_order_articles/#{goa.id}", { group_order_article: { quantity: '99999999999999' } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(goa.reload.quantity).to eq 2
    end
  end

  describe 'ids' do
    it 'does not find path ids with letters (no longer read as the number in front)' do
      api :get, "/orders/#{order.id}abc"
      expect(response).to have_http_status(:not_found)
    end

    it 'refuses an order article id with letters' do
      api :post, '/user/group_order_articles', { group_order_article: { order_article_id: "#{order.order_articles.first.id}x", quantity: 1 } }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'request objects' do
    it 'refuses a text where an object belongs' do
      api :post, '/user/group_order_articles', { group_order_article: 'x' }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'answers a missing object with a JSON 400' do
      api :post, '/user/group_order_articles', { other: 1 }
      expect(response).to have_http_status(:bad_request)
      expect(json['error']).to eq 'bad_request'
    end
  end

  describe 'lists and search' do
    before { create_list(:order, 3) }

    it 'rounds the number of pages up' do
      api :get, '/orders?per_page=2'
      expect(json['meta']['total_pages']).to eq (json['meta']['total_count'] / 2.0).ceil
    end

    it 'refuses a search that is not an object' do
      api :get, '/order_articles?q=abc'
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'self-service payments' do
    before { FoodsoftConfig.config[:use_self_service] = true }

    let(:type) { create(:financial_transaction_type) }

    it 'answers 422 without amount' do
      api :post, '/user/financial_transactions', { financial_transaction: { financial_transaction_type_id: type.id, note: 'x' } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(user.ordergroup.financial_transactions).to be_empty
    end

    %w[1,5 1.300,50 1e3].each do |value|
      it "refuses the amount #{value.inspect} instead of misreading it" do
        api :post, '/user/financial_transactions', { financial_transaction: { financial_transaction_type_id: type.id, amount: value, note: 'x' } }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(user.ordergroup.financial_transactions).to be_empty
      end
    end

    it 'accepts a dot as decimal separator' do
      api :post, '/user/financial_transactions', { financial_transaction: { financial_transaction_type_id: type.id, amount: '1.5', note: 'x' } }
      expect(response).to have_http_status(:ok)
      expect(user.ordergroup.financial_transactions.last.amount).to eq 1.5
    end
  end
end
