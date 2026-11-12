require 'swagger_helper'

describe Api::V1::ArticlesController do
  include ApiHelper

  let(:api_scopes) { ['articles:write'] }
  let(:user) { create(:user, :role_article_meta) }
  let(:supplier) { create(:supplier) }
  let(:article_category) { create(:article_category) }
  let!(:article) { create(:article, supplier: supplier) }

  path '/suppliers' do
    get 'suppliers' do
      tags 'Supplier'
      produces 'application/json'
      pagination_param

      response '200', 'success' do
        schema type: :object, properties: {
          meta: { '$ref' => '#/components/schemas/Meta' },
          suppliers: { type: :array, items: { '$ref': '#/components/schemas/Supplier' } }
        }

        run_test! do |response|
          expect(JSON.parse(response.body)['suppliers'].pluck('id')).to include supplier.id
        end
      end

      it_handles_invalid_token_and_scope
    end
  end

  path '/articles' do
    get 'articles of suppliers (filter with q[supplier_id_eq], q[name_cont], ...)' do
      tags 'Article'
      produces 'application/json'
      pagination_param

      response '200', 'success' do
        schema type: :object, properties: {
          meta: { '$ref' => '#/components/schemas/Meta' },
          articles: { type: :array, items: { '$ref': '#/components/schemas/ArticleDetail' } }
        }

        run_test! do |response|
          data = response.parsed_body['articles']
          # other specs may leave articles in the shared test database
          found = data.find { |a| a['id'] == article.id }
          expect(found['price']).to eq article.price.to_f
        end
      end

      it_handles_invalid_token_and_scope
    end

    post 'create an article' do
      tags 'Article'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :payload, in: :body, required: true, schema: {
        type: :object,
        properties: { article: { '$ref': '#/components/schemas/ArticleForCreate' } },
        required: %w[article]
      }

      let(:payload) do
        { article: { supplier_id: supplier.id, article_category_id: article_category.id, name: 'Apple juice',
                     unit: '1 l', unit_quantity: 6, price: 2.5, tax: 10, deposit: 0.29 } }
      end

      response '201', 'article created' do
        schema type: :object, properties: { article: { '$ref': '#/components/schemas/ArticleDetail' } }

        run_test! do |response|
          created = Article.find(JSON.parse(response.body)['article']['id'])
          expect(created.supplier).to eq supplier
          expect(created.price).to eq 2.5
          expect(created.unit_quantity).to eq 6
        end
      end

      response '422', 'invalid data' do
        schema '$ref' => '#/components/schemas/Error422'
        let(:payload) { { article: { supplier_id: supplier.id, name: 'x' } } }

        run_test!
      end

      context 'without the article role' do
        let(:user) { create(:user) }

        response '403', 'missing scope or no permission' do
          schema '$ref' => '#/components/schemas/Error403'
          run_test!
        end
      end
    end
  end

  path '/articles/{id}' do
    patch 'update an article' do
      tags 'Article'
      consumes 'application/json'
      produces 'application/json'
      id_url_param
      parameter name: :payload, in: :body, required: true, schema: {
        type: :object,
        properties: { article: { '$ref': '#/components/schemas/ArticleForUpdate' } },
        required: %w[article]
      }

      let(:id) { article.id }
      let(:payload) { { article: { price: 9.99, availability: false } } }

      response '200', 'success' do
        schema type: :object, properties: { article: { '$ref': '#/components/schemas/ArticleDetail' } }

        run_test! do
          article.reload
          expect(article.price).to eq 9.99
          expect(article.availability).to be false
        end
      end

      it_handles_invalid_token_with_id
      # in a context, so that its +let(:id)+ does not replace the one above
      context 'with an unknown id' do
        it_cannot_find_object 'article not found'
      end
    end

    delete 'remove an article (marks it as deleted)' do
      tags 'Article'
      produces 'application/json'
      id_url_param

      let(:id) { article.id }

      response '200', 'success' do
        run_test! do
          expect(article.reload.deleted_at).not_to be_nil
        end
      end

      response '422', 'article is part of an open order' do
        schema '$ref' => '#/components/schemas/Error422'
        before { create(:order, supplier: supplier, article_ids: [article.id]) }

        run_test! do
          expect(article.reload.deleted_at).to be_nil
        end
      end
    end
  end
end
