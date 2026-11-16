require 'swagger_helper'

describe Api::V1::InvoicesController do
  include ApiHelper

  let(:api_scopes) { ['invoices:write'] }
  let(:user) { create(:user, :role_invoices) }
  let(:supplier) { create(:supplier) }
  let!(:invoice) { create(:invoice, supplier: supplier, created_by: user) }

  path '/invoices' do
    get 'invoices' do
      tags 'Invoice'
      produces 'application/json'
      pagination_param

      response '200', 'success' do
        schema type: :object, properties: {
          meta: { '$ref' => '#/components/schemas/Meta' },
          invoices: { type: :array, items: { '$ref': '#/components/schemas/Invoice' } }
        }

        run_test! do |response|
          expect(response.parsed_body['invoices'].pluck('id')).to eq [invoice.id]
        end
      end

      it_handles_invalid_token_and_scope
    end

    post 'create an invoice (use multipart/form-data with attachments[] to upload files)' do
      tags 'Invoice'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :payload, in: :body, required: true, schema: {
        type: :object,
        properties: { invoice: { '$ref': '#/components/schemas/InvoiceForCreate' } },
        required: %w[invoice]
      }

      let(:payload) { { invoice: { supplier_id: supplier.id, number: 'R-2024-17', amount: 123.45, date: '2024-05-06' } } }

      response '201', 'invoice created' do
        schema type: :object, properties: { invoice: { '$ref': '#/components/schemas/Invoice' } }

        run_test! do |response|
          created = Invoice.find(response.parsed_body['invoice']['id'])
          expect(created.created_by).to eq user
          expect(created.amount).to eq 123.45
        end
      end

      response '422', 'invalid data' do
        schema '$ref' => '#/components/schemas/Error422'
        let(:payload) { { invoice: { number: 'no supplier' } } }

        run_test!
      end

      response '403', 'missing scope or no permission' do
        let(:user) { create(:user) }
        schema '$ref' => '#/components/schemas/Error403'
        run_test!
      end
    end
  end

  path '/invoices/{id}' do
    patch 'update an invoice' do
      tags 'Invoice'
      consumes 'application/json'
      produces 'application/json'
      id_url_param
      parameter name: :payload, in: :body, required: true, schema: {
        type: :object,
        properties: { invoice: { '$ref': '#/components/schemas/InvoiceForUpdate' } },
        required: %w[invoice]
      }

      let(:id) { invoice.id }
      let(:payload) { { invoice: { note: 'checked', paid_on: '2024-05-07' } } }

      response '200', 'success (paid_on is ignored without the finance role)' do
        schema type: :object, properties: { invoice: { '$ref': '#/components/schemas/Invoice' } }

        run_test! do
          invoice.reload
          expect(invoice.note).to eq 'checked'
          expect(invoice.paid_on).to be_nil
        end
      end

      response '403', 'invoice cannot be edited by this user' do
        let(:invoice) { create(:invoice, supplier: supplier) }
        schema '$ref' => '#/components/schemas/Error403'
        run_test!
      end

      it_handles_invalid_token_with_id
      # in a context, so that its +let(:id)+ does not replace the operation's own
      context 'with an unknown id' do
        it_cannot_find_object 'invoice not found'
      end
    end
  end

  # File transfer is tested without rswag, as plain multipart requests.
  describe 'attachments' do
    let(:headers) { { 'Authorization' => "Bearer #{api_access_token}" } }
    let(:base) { "/f/api/v1/invoices/#{invoice.id}/attachments" }
    let(:pdf) do
      file = Tempfile.new(['receipt', '.pdf'])
      file.binmode
      file.write("%PDF-1.4\n1 0 obj\n<< >>\nendobj\ntrailer\n<< >>\n%%EOF\n")
      file.rewind
      Rack::Test::UploadedFile.new(file.path, 'application/pdf', true, original_filename: 'receipt.pdf')
    end
    let(:text) do
      file = Tempfile.new(['notes', '.txt'])
      file.write('just some text')
      file.rewind
      Rack::Test::UploadedFile.new(file.path, 'text/plain', false, original_filename: 'notes.txt')
    end

    it 'uploads, lists, downloads and removes a file' do
      post base, params: { attachments: [pdf] }, headers: headers
      expect(response).to have_http_status :created
      attachments = response.parsed_body['invoice']['attachments']
      expect(attachments.length).to eq 1
      expect(attachments.first).to include('filename' => 'receipt.pdf', 'content_type' => 'application/pdf')

      get "#{base}/#{attachments.first['id']}", headers: headers
      expect(response).to have_http_status :ok
      expect(response.body).to start_with '%PDF'

      delete "#{base}/#{attachments.first['id']}", headers: headers
      expect(response).to have_http_status :ok
      expect(response.parsed_body['invoice']['attachments']).to be_empty
    end

    it 'creates an invoice together with a file' do
      post '/f/api/v1/invoices',
           params: { invoice: { supplier_id: supplier.id, amount: '12.50' }, attachments: [pdf] },
           headers: headers
      expect(response).to have_http_status :created
      expect(response.parsed_body['invoice']['attachments'].length).to eq 1
    end

    it 'rejects other file types' do
      post base, params: { attachments: [text] }, headers: headers
      expect(response).to have_http_status :unprocessable_entity
      expect(invoice.reload.attachments).to be_empty
    end

    it 'requires a file' do
      post base, headers: headers
      expect(response).to have_http_status :unprocessable_entity
    end
  end
end
