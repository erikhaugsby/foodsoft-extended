require 'spec_helper'

# can_edit in the invoice JSON follows the website: the finance role, or the creator
# of an unpaid invoice with the invoices role.
describe 'Invoices API can_edit' do
  let(:token) { create(:oauth2_access_token, resource_owner_id: user.id, scopes: 'invoices:read').token }
  let(:headers) { { 'Authorization' => "Bearer #{token}" } }
  let(:can_edit) do
    get "/f/api/v1/invoices/#{invoice.id}", headers: headers
    response.parsed_body['invoice']['can_edit']
  end

  context 'with the invoices role' do
    let(:user) { create(:user, :role_invoices) }

    context 'with an own unpaid invoice' do
      let(:invoice) { create(:invoice, created_by: user) }

      it { expect(can_edit).to be true }
    end

    context 'with an own paid invoice' do
      let(:invoice) { create(:invoice, created_by: user, paid_on: Time.zone.today) }

      it { expect(can_edit).to be false }
    end

    context "with someone else's invoice" do
      let(:invoice) { create(:invoice) }

      it { expect(can_edit).to be false }
    end
  end

  context 'with the finance role' do
    let(:user) { create(:user, :role_finance) }
    let(:invoice) { create(:invoice, paid_on: Time.zone.today) }

    it { expect(can_edit).to be true }
  end
end
