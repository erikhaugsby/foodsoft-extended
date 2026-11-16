require 'spec_helper'

# The input rules (doc/API.md, "Input rules") for the management endpoints: dates, booleans,
# whole numbers and objects.
describe 'API input validation, management endpoints' do
  let(:user) do
    user = create(:user, groups: [create(:ordergroup)])
    create(:workgroup, role_orders: true, role_article_meta: true, role_invoices: true, role_finance: true,
                       user_ids: [user.id])
    user
  end
  let(:scopes) { 'orders:read orders:write articles:read articles:write invoices:read invoices:write' }
  let(:headers) do
    { 'Authorization' => "Bearer #{create(:oauth2_access_token, resource_owner_id: user.id, scopes: scopes).token}" }
  end
  let(:order) { create(:order, article_count: 2) }
  let(:article) { order.supplier.articles.first }

  def api(method, path, params = nil)
    process method, "/f/api/v1#{path}", headers: headers, params: params, as: (params && method != :get ? :json : nil)
  end

  it 'refuses a fractional unit quantity' do
    api :patch, "/articles/#{article.id}", { article: { unit_quantity: 2.5 } }
    expect(response).to have_http_status(:unprocessable_entity)
    api :patch, "/articles/#{article.id}", { article: { unit_quantity: 6 } }
    expect(article.reload.unit_quantity).to eq 6
  end

  it 'refuses a text where the order object belongs' do
    api :patch, "/orders/#{order.id}", { order: 'x' }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'answers a missing order object with a JSON 400' do
    api :patch, "/orders/#{order.id}", { other: 1 }
    expect(response).to have_http_status(:bad_request)
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

  it 'refuses "no" for ignore_warnings and keeps the order articles' do
    api :patch, "/orders/#{order.id}", { order: { ignore_warnings: 'no', article_ids: [] } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(order.reload.order_articles.count).to eq 2
  end

  it 'answers 422 for a stock order with article ids' do
    stock_order = create(:stock_order)
    api :patch, "/orders/#{stock_order.id}", { order: { article_ids: [1] } }
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
