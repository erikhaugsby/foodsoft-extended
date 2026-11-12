require 'spec_helper'

# Members with only the orders role may read articles (to choose an order's articles), not change them.
describe 'Articles API for the orders role' do
  let(:user) { create(:user, :role_orders) }
  let(:headers) { { 'Authorization' => "Bearer #{token}" } }
  let!(:article) { create(:article) }

  context 'with the orders:write scope' do
    let(:token) { create(:oauth2_access_token, resource_owner_id: user.id, scopes: 'orders:write').token }

    it 'reads articles' do
      get '/f/api/v1/articles', headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['articles'].pluck('id')).to include(article.id)
    end

    it 'reads one article' do
      get "/f/api/v1/articles/#{article.id}", headers: headers
      expect(response).to have_http_status(:ok)
    end
  end

  context 'with the articles:write scope' do
    let(:token) { create(:oauth2_access_token, resource_owner_id: user.id, scopes: 'articles:read articles:write').token }

    it 'reads articles' do
      get '/f/api/v1/articles', headers: headers
      expect(response).to have_http_status(:ok)
    end

    it 'cannot change articles' do
      patch "/f/api/v1/articles/#{article.id}", headers: headers, as: :json, params: { article: { name: 'New' } }
      expect(response).to have_http_status(:forbidden)
    end
  end
end
