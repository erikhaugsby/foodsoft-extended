require 'spec_helper'

describe 'Order JSON' do
  let(:user) { create(:user, :ordergroup) }
  let(:headers) do
    { 'Authorization' => "Bearer #{create(:oauth2_access_token, resource_owner_id: user.id, scopes: 'orders:read').token}" }
  end
  let(:supplier) { create(:supplier, article_count: 1, min_order_quantity: '50 EUR', email: 'farm@example.com') }
  let(:order) { create(:order, supplier: supplier, article_ids: supplier.articles.map(&:id), note: 'Bring bags') }

  it 'shows state, supplier, note and end action' do
    get "/f/api/v1/orders/#{order.id}", headers: headers
    expect(response.parsed_body['order']).to include(
      'state' => 'open', 'supplier_id' => supplier.id, 'note' => 'Bring bags', 'end_action' => 'no_end_action'
    )
  end

  it 'shows the state of a finished order' do
    order.update!(state: 'finished')
    get "/f/api/v1/orders/#{order.id}", headers: headers
    expect(response.parsed_body['order']['state']).to eq 'finished'
  end

  it 'shows the invoice and the minimum order to every member' do
    invoice = create(:invoice, supplier: supplier)
    order.update!(invoice: invoice)
    get "/f/api/v1/orders/#{order.id}", headers: headers
    expect(response.parsed_body['order']).to include('invoice_id' => invoice.id, 'supplier_min_order_quantity' => '50 EUR')
  end

  it 'shows whether the order can be emailed to the supplier, and when it last was' do
    get "/f/api/v1/orders/#{order.id}", headers: headers
    expect(response.parsed_body['order']).to include('supplier_has_email' => true, 'last_sent_mail' => nil)
  end
end
