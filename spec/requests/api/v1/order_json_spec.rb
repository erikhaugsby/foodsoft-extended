require 'spec_helper'

describe 'Order JSON for the apps' do
  let(:user) { create(:user, :ordergroup) }
  let(:headers) do
    { 'Authorization' => "Bearer #{create(:oauth2_access_token, resource_owner_id: user.id, scopes: 'orders:read').token}" }
  end

  it 'shows the invoice and the minimum order to every member' do
    supplier = create(:supplier, article_count: 1, min_order_quantity: '50 EUR')
    order = create(:order, supplier: supplier, article_ids: supplier.articles.map(&:id))
    invoice = create(:invoice, supplier: supplier)
    order.update!(invoice: invoice)
    get "/f/api/v1/orders/#{order.id}", headers: headers
    expect(response.parsed_body['order']).to include('invoice_id' => invoice.id, 'supplier_min_order_quantity' => '50 EUR')
  end
end
