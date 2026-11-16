require 'spec_helper'

# POST /orders/{id}/send_to_supplier and POST /orders/{id}/receive, the website's
# "Send to supplier" button and "Receive" page for apps.
describe 'Orders: send to supplier and receive' do
  let(:supplier) { create(:supplier, email: 'supplier@example.com') }
  let(:article) { create(:article, supplier: supplier, unit_quantity: 3) }
  let(:order) { create(:order, supplier: supplier, article_ids: [article.id]) }
  let(:oa) { order.order_articles.find_by(article_id: article.id) }
  let(:household_a_order) { create(:group_order, order: order) }
  let(:household_b_order) { create(:group_order, order: order) }
  let(:household_a) { create(:group_order_article, group_order: household_a_order, order_article: oa) }
  let(:household_b) { create(:group_order_article, group_order: household_b_order, order_article: oa) }
  let(:orders_user) { create(:user, groups: [create(:workgroup, role_orders: true)]) }
  let(:pickups_user) { create(:user, groups: [create(:workgroup, role_pickups: true)]) }
  let(:member) { create(:user, :ordergroup) }
  let(:json) { response.parsed_body }

  def headers_for(user, scopes)
    token = create(:oauth2_access_token, resource_owner_id: user.id, scopes: scopes.join(' ')).token
    { 'Authorization' => "Bearer #{token}", 'Accept' => 'application/json' }
  end

  def call(path, user, scopes, params = nil)
    post "/f/api/v1#{path}", headers: headers_for(user, scopes), params: params, as: (params ? :json : nil)
  end

  # members ordered 2+0 and 3+2 (quantity+tolerance) of a box of 3: Foodsoft orders 2 boxes
  def ordered_and_finished
    household_a.update_quantities(2, 0)
    household_b.update_quantities(3, 2)
    oa.update_results!
    order.finish!(orders_user)
  end

  describe 'send_to_supplier' do
    it 'queues the email for a finished order and tells when it was last sent' do
      ordered_and_finished
      expect do
        call "/orders/#{order.id}/send_to_supplier", orders_user, ['orders:write']
      end.to have_enqueued_job(SendOrderToSupplierJob)
      expect(response).to have_http_status(:ok)
      expect(json['order']).to include('id' => order.id, 'supplier_has_email' => true)
      expect(json['order']).to have_key('last_sent_mail')
    end

    it 'refuses open orders' do
      call "/orders/#{order.id}/send_to_supplier", orders_user, ['orders:write']
      expect(response).to have_http_status(:not_found)
    end

    it 'refuses suppliers without email' do
      supplier.update_column(:email, '')
      ordered_and_finished
      call "/orders/#{order.id}/send_to_supplier", orders_user, ['orders:write']
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error_description']).to include('email')
    end

    it 'needs the orders role and the orders:write scope' do
      ordered_and_finished
      call "/orders/#{order.id}/send_to_supplier", member, ['orders:write']
      expect(response).to have_http_status(:forbidden)
      call "/orders/#{order.id}/send_to_supplier", orders_user, ['orders:read']
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'receive' do
    def check_results(units, result_a, result_b)
      [oa, household_a, household_b].each(&:reload)
      expect(oa.units).to eq units
      expect(household_a.result).to be_within(1e-3).of result_a
      expect(household_b.result).to be_within(1e-3).of result_b
    end

    it 'marks the order received without changing amounts when no articles are given' do
      ordered_and_finished
      call "/orders/#{order.id}/receive", orders_user, ['orders:read']
      expect(response).to have_http_status(:ok)
      expect(json['order']['state']).to eq 'received'
      check_results 2, 2, 4
    end

    it 'redistributes when more was delivered, using the tolerance' do
      ordered_and_finished
      call "/orders/#{order.id}/receive", orders_user, ['orders:read'],
           { order: { order_articles: [{ id: oa.id, units_received: 3 }] } }
      expect(response).to have_http_status(:ok)
      check_results 3, 2, 5
      expect(oa.reload.units_received).to eq 3
    end

    it 'redistributes when less was delivered' do
      ordered_and_finished
      call "/orders/#{order.id}/receive", orders_user, ['orders:read'],
           { order: { order_articles: [{ id: oa.id, units_received: '1' }] } }
      expect(response).to have_http_status(:ok)
      check_results 1, 2, 1
    end

    it 'may be done by the pickups role too, as on the website' do
      ordered_and_finished
      call "/orders/#{order.id}/receive", pickups_user, ['orders:read']
      expect(response).to have_http_status(:ok)
      expect(order.reload.state).to eq 'received'
    end

    it 'refuses members without a role' do
      ordered_and_finished
      call "/orders/#{order.id}/receive", member, ['orders:read']
      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses negative amounts, commas and articles of other orders without changing anything' do
      ordered_and_finished
      other = create(:order)
      [{ id: oa.id, units_received: -1 }, { id: oa.id, units_received: '1,5' },
       { id: other.order_articles.first.id, units_received: 1 }].each do |entry|
        call "/orders/#{order.id}/receive", orders_user, ['orders:read'], { order: { order_articles: [entry] } }
        expect(response.status).to be_in([404, 422]), "#{entry}: #{response.status}"
      end
      expect(order.reload.state).to eq 'finished'
      check_results 2, 2, 4
    end

    it 'leaves articles changed by hand to the website' do
      ordered_and_finished
      household_a.update!(result: household_a.result + 1)
      call "/orders/#{order.id}/receive", orders_user, ['orders:read'],
           { order: { order_articles: [{ id: oa.id, units_received: 3 }] } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(order.reload.state).to eq 'finished'
    end

    it 'shows units_received and the lock in the order articles' do
      ordered_and_finished
      call "/orders/#{order.id}/receive", orders_user, ['orders:read'],
           { order: { order_articles: [{ id: oa.id, units_received: 2 }] } }
      get "/f/api/v1/order_articles/#{oa.id}", headers: headers_for(orders_user, ['orders:read'])
      expect(json['order_article']).to include('units_received' => 2.0, 'result_manually_changed' => false)
    end
  end
end
