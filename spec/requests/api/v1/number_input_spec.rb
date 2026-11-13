require 'spec_helper'

# Numbers in API requests: a dot is the decimal separator, independent of the user's language.
# Commas, thousands separators and exponents are refused instead of being misread.
describe 'API number input' do
  let(:user) do
    user = create(:user, :ordergroup)
    create(:workgroup, role_article_meta: true, role_finance: true, role_invoices: true, user_ids: [user.id])
    user
  end
  let(:token) { create(:oauth2_access_token, resource_owner_id: user.id, scopes: 'articles:read articles:write invoices:read invoices:write').token }
  let(:supplier) { create(:supplier, article_count: 1) }
  let(:article) { supplier.articles.first }
  let(:invoice) { create(:invoice, supplier: supplier, created_by: user, amount: 10) }
  let(:json) { response.parsed_body }

  %w[en de].each do |language|
    context "with Accept-Language #{language}" do
      let(:headers) { { 'Authorization' => "Bearer #{token}", 'Accept-Language' => language } }

      def change_price(value)
        patch "/f/api/v1/articles/#{article.id}", headers: headers, as: :json, params: { article: { price: value } }
      end

      { 130.5 => 130.5, '130.5' => 130.5, ' 12 ' => 12, '1.300' => 1.3, '7' => 7 }.each do |input, stored|
        it "stores #{input.inspect} as #{stored}" do
          change_price(input)
          expect(response).to have_http_status(:ok)
          expect(article.reload.price).to eq stored
        end
      end

      ['130,5', '1.300,50', '1,300.50', '1,300', '1e3', '12 EUR', '0x1A'].each do |input|
        it "refuses #{input.inspect} and keeps the price" do
          old_price = article.price
          change_price(input)
          expect(response).to have_http_status(:unprocessable_entity)
          expect(json['error_description']).to include('dot as decimal separator')
          expect(article.reload.price).to eq old_price
        end
      end
    end
  end

  describe 'invoices' do
    let(:headers) { { 'Authorization' => "Bearer #{token}" } }

    it 'refuses a comma in JSON' do
      patch "/f/api/v1/invoices/#{invoice.id}", headers: headers, as: :json, params: { invoice: { deposit: '1,5' } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(invoice.reload.deposit).to eq 0
    end

    it 'refuses a comma in a form upload' do
      post '/f/api/v1/invoices', headers: headers,
                                 params: { invoice: { supplier_id: supplier.id, number: 'X1', amount: '130,5' } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Invoice.where(number: 'X1')).to be_empty
    end
  end

  describe 'values the database cannot hold' do
    let(:headers) { { 'Authorization' => "Bearer #{token}" } }

    it 'answers 422 instead of crashing for a too large number' do
      patch "/f/api/v1/articles/#{article.id}", headers: headers, as: :json, params: { article: { price: '99999999999999' } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'answers 422 instead of crashing for a too long text' do
      patch "/f/api/v1/articles/#{article.id}", headers: headers, as: :json, params: { article: { note: 'x' * 1000 } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
