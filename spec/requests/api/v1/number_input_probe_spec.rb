require 'spec_helper'

# Temporary probe: records what the API stores for different number formats.
describe 'Number input probe' do
  let(:user) do
    user = create(:user, :ordergroup)
    create(:workgroup, role_article_meta: true, role_finance: true, role_invoices: true, user_ids: [user.id])
    user
  end
  let(:token) { create(:oauth2_access_token, resource_owner_id: user.id, scopes: 'articles:read articles:write invoices:read invoices:write').token }
  let(:supplier) { create(:supplier, article_count: 1) }
  let(:article) { supplier.articles.first }
  let(:invoice) { create(:invoice, supplier: supplier, created_by: user) }

  inputs = [130.5, '130.5', '130,5', '1.300', '1,300', '1.300,50', '1,300.50', ' 12 ', '1e3', 'abc', '', '-5', '99999999999999']

  %w[en de].each do |lang|
    inputs.each do |input|
      it "#{lang}: #{input.inspect}" do
        headers = { 'Authorization' => "Bearer #{token}", 'Accept-Language' => lang }
        patch "/f/api/v1/articles/#{article.id}", headers: headers, as: :json, params: { article: { price: input } }
        a_status = response.status
        a_value = article.reload.price.to_s('F')
        patch "/f/api/v1/invoices/#{invoice.id}", headers: headers, as: :json, params: { invoice: { amount: input } }
        i_status = response.status
        i_value = invoice.reload.amount.to_s('F')
        puts "PROBE\t#{lang}\t#{input.inspect}\tarticle price: #{a_status} -> #{a_value}\tinvoice amount: #{i_status} -> #{i_value}"
      end
    end
  end
end
