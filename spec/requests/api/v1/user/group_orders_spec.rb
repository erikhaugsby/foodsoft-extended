require 'spec_helper'

# Plain request specs (not rswag).
describe 'User group orders API' do
  let(:user) { create(:user, :ordergroup, first_name: 'Erik') }
  let(:token) { create(:oauth2_access_token, resource_owner_id: user.id, scopes: 'group_orders:user').token }
  let(:headers) { { 'Authorization' => "Bearer #{token}" } }
  let(:json) { response.parsed_body }
  let(:order) { create(:order) }
  let(:other_order) { create(:order) }
  let!(:group_order) { create(:group_order, order: order, ordergroup: user.ordergroup, updated_by: user, price: 15.02) }

  before do
    create(:group_order, order: other_order, ordergroup: user.ordergroup)
    create(:group_order, order: order) # another household
  end

  it 'lists the household’s group orders, filtered by order' do
    get '/f/api/v1/user/group_orders', headers: headers, params: { q: { order_id_in: [order.id] } }
    expect(response).to have_http_status(:ok)
    expect(json['group_orders'].pluck('id')).to eq [group_order.id]
    expect(json['group_orders'].first).to include('order_id' => order.id, 'price' => 15.02,
                                                  'updated_by_name' => user.display)
  end

  it 'lists all of the household’s group orders without a filter' do
    get '/f/api/v1/user/group_orders', headers: headers
    expect(json['group_orders'].count).to eq 2
  end

  it 'does not show group orders of other households' do
    foreign = GroupOrder.where.not(ordergroup: user.ordergroup).first
    get "/f/api/v1/user/group_orders/#{foreign.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end
end
