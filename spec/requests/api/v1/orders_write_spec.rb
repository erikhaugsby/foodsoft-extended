require 'swagger_helper'

describe 'Orders (write)' do
  include ApiHelper

  let(:api_scopes) { ['orders:write'] }
  let(:user) { create(:user, :role_orders) }
  let(:supplier) { create(:supplier, article_count: 3) }
  let(:existing_order) { create(:order, article_count: 3) }

  path '/orders' do
    post 'open a new order' do
      tags 'Order'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :payload, in: :body, required: true, schema: {
        type: :object,
        properties: { order: { '$ref': '#/components/schemas/OrderForCreate' } },
        required: %w[order]
      }

      let(:payload) { { order: { supplier_id: supplier.id, ends: 3.days.from_now.iso8601, note: 'via API' } } }

      response '201', 'order opened with all available articles of the supplier' do
        schema type: :object, properties: { order: { '$ref': '#/components/schemas/Order' } }

        run_test! do |response|
          data = response.parsed_body['order']
          order = Order.find(data['id'])
          expect(data['is_open']).to be true
          expect(order.created_by).to eq user
          expect(order.article_ids.map(&:to_i)).to match_array supplier.articles.map(&:id)
        end
      end

      response '201', 'order opened with selected articles' do
        let(:article) { supplier.articles.first }
        let(:payload) { { order: { supplier_id: supplier.id, article_ids: [article.id] } } }

        run_test! do |response|
          order = Order.find(response.parsed_body['order']['id'])
          expect(order.articles).to eq [article]
        end
      end

      response '422', 'invalid data, e.g. no articles or end before start' do
        schema '$ref' => '#/components/schemas/Error422'
        let(:payload) { { order: { supplier_id: supplier.id, article_ids: [] } } }

        run_test!
      end

      response '404', 'supplier not found' do
        schema '$ref' => '#/components/schemas/Error404'
        let(:payload) { { order: { supplier_id: 0 } } }

        run_test!
      end

      response '403', 'missing scope or no permission' do
        let(:user) { create(:user) }
        schema '$ref' => '#/components/schemas/Error403'
        run_test!
      end

      it_handles_invalid_token
    end
  end

  path '/orders/{id}' do
    patch 'update an order' do
      tags 'Order'
      consumes 'application/json'
      produces 'application/json'
      id_url_param
      parameter name: :payload, in: :body, required: true, schema: {
        type: :object,
        properties: { order: { '$ref': '#/components/schemas/OrderForUpdate' } },
        required: %w[order]
      }

      let(:id) { existing_order.id }
      let(:payload) { { order: { note: 'changed', pickup: 5.days.from_now.to_date.iso8601 } } }

      response '200', 'success' do
        schema type: :object, properties: { order: { '$ref': '#/components/schemas/Order' } }

        run_test! do |response|
          expect(response.parsed_body['order']['note']).to eq 'changed'
          expect(existing_order.reload.updated_by).to eq user
        end
      end

      it_handles_invalid_token_with_id
      # in a context, so that its +let(:id)+ does not replace the operation's own
      context 'with an unknown id' do
        it_cannot_find_object 'order not found'
      end
    end
  end

  path '/orders/{id}/finish' do
    post 'close an open order for ordering' do
      tags 'Order'
      produces 'application/json'
      id_url_param

      let(:id) { existing_order.id }

      response '200', 'success' do
        schema type: :object, properties: { order: { '$ref': '#/components/schemas/Order' } }

        run_test! do |response|
          data = response.parsed_body['order']
          expect(data['is_open']).to be false
          expect(data['state']).to eq 'finished'
        end
      end

      response '404', 'order not found or not open' do
        schema '$ref' => '#/components/schemas/Error404'
        before { existing_order.finish!(user) }

        run_test!
      end

      it_handles_invalid_token_with_id
    end
  end

  path '/orders/{id}/documents/{document}' do
    get 'download an order PDF' do
      tags 'Order'
      produces 'application/pdf'
      id_url_param
      parameter name: :document, in: :path, required: true,
                schema: { type: :string, enum: %w[groups articles fax matrix] }

      let(:api_scopes) { ['orders:read'] }
      let(:id) { existing_order.id }
      let(:document) { 'articles' }

      # the PDF titles show the end date
      let(:existing_order) { create(:order, article_count: 3, ends: 1.day.from_now) }

      response '200', 'the PDF file' do
        run_test! do |response|
          expect(response.media_type).to eq 'application/pdf'
          expect(response.body).to start_with '%PDF'
        end
      end

      response '403', 'no permission' do
        let(:user) { create(:user) }
        run_test!
      end

      response '422', 'the order has no end date yet' do
        let(:existing_order) { create(:order, article_count: 3, ends: nil) }
        schema '$ref' => '#/components/schemas/Error422'
        run_test!
      end

      response '404', 'order or document not found' do
        let(:document) { 'nonsense' }
        run_test!
      end
    end
  end
end
