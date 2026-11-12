require 'spec_helper'

# Plain request specs (not rswag), see doc/API.md for the endpoint description.
describe 'Messages API' do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:third_user) { create(:user) }
  let(:api_scopes) { ['messages:read', 'messages:write'] }
  let(:token) { create(:oauth2_access_token, resource_owner_id: user.id, scopes: api_scopes.join(' ')).token }
  let(:headers) { { 'Authorization' => "Bearer #{token}", 'Accept' => 'application/json' } }
  let(:json) { response.parsed_body }

  def create_message(sender:, recipients:, subject: 'Hello', body: 'Some text', private: false, reply_to: nil)
    message = Message.new(sender: sender, subject: subject, body: body, private: private, reply_to: reply_to)
    message.add_recipients(recipients.map(&:id))
    message.save!
    message
  end

  describe 'GET /messages' do
    let!(:public_message) { create_message(sender: other_user, recipients: [third_user]) }
    let!(:my_private_message) { create_message(sender: other_user, recipients: [user], private: true) }

    before do
      create_message(sender: other_user, recipients: [third_user], private: true)
      create_message(sender: other_user, recipients: [user]).tap(&:soft_delete!)
    end

    it 'lists readable messages, without deleted ones' do
      get '/f/api/v1/messages', headers: headers
      expect(response).to have_http_status(:ok)
      ids = json['messages'].pluck('id')
      expect(ids).to contain_exactly(public_message.id, my_private_message.id)
      expect(json['meta']['total_count']).to eq 2
    end

    it 'needs a messages scope' do
      token_without_scope = create(:oauth2_access_token, resource_owner_id: user.id, scopes: 'user:read').token
      get '/f/api/v1/messages', headers: { 'Authorization' => "Bearer #{token_without_scope}" }
      expect(response).to have_http_status(:forbidden)
    end

    it 'answers 404 when messages are disabled' do
      FoodsoftConfig.config[:use_messages] = false
      get '/f/api/v1/messages', headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /messages/:id and /messages/:id/thread' do
    let!(:root) { create_message(sender: other_user, recipients: [user]) }
    let!(:reply) { create_message(sender: user, recipients: [other_user], reply_to: root.id) }
    let!(:deleted_reply) { create_message(sender: other_user, recipients: [user], reply_to: root.id).tap(&:soft_delete!) }
    let!(:private_reply) { create_message(sender: other_user, recipients: [third_user], reply_to: root.id, private: true) }

    it 'shows a message with plain text and recipients' do
      get "/f/api/v1/messages/#{root.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(json['message']['body']).to eq 'Some text'
      expect(json['message']['recipients'].pluck('id')).to eq [user.id]
      expect(json['message']['can_edit']).to be false
    end

    it 'hides private messages of others' do
      get "/f/api/v1/messages/#{private_reply.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it 'shows the thread with a placeholder for deleted messages' do
      get "/f/api/v1/messages/#{reply.id}/thread", headers: headers
      expect(response).to have_http_status(:ok)
      expect(json['messages'].pluck('id')).to eq [root.id, reply.id, deleted_reply.id]
      deleted = json['messages'].last
      expect(deleted['deleted']).to be true
      expect(deleted['body']).to be_nil
    end
  end

  describe 'POST /messages' do
    it 'sends a message to users and queues the email' do
      expect do
        post '/f/api/v1/messages', headers: headers, as: :json,
                                   params: { message: { subject: 'Pickup', body: "Line 1\n<Line 2>", recipient_ids: [other_user.id] } }
      end.to have_enqueued_job(DeliverMessageJob)
      expect(response).to have_http_status(:created)
      message = Message.find(json['message']['id'])
      expect(message.sender).to eq user
      expect(message.recipients).to eq [other_user]
      expect(message.body.to_plain_text).to include('<Line 2>')
    end

    it 'replies in the thread of the original message' do
      root = create_message(sender: other_user, recipients: [user], subject: 'Question')
      post '/f/api/v1/messages', headers: headers, as: :json,
                                 params: { message: { reply_to: root.id, body: 'Answer' } }
      expect(response).to have_http_status(:created)
      expect(json['message']['reply_to']).to eq root.id
      expect(json['message']['subject']).to include('Question')
      expect(json['message']['recipients'].pluck('id')).to eq [other_user.id]
    end

    it 'refuses a message without recipients' do
      post '/f/api/v1/messages', headers: headers, as: :json,
                                 params: { message: { subject: 'Nobody', body: 'Text' } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'refuses an unknown send method' do
      post '/f/api/v1/messages', headers: headers, as: :json,
                                 params: { message: { subject: 'X', body: 'Y', send_method: 'everyone' } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'needs messages:write' do
      read_token = create(:oauth2_access_token, resource_owner_id: user.id, scopes: 'messages:read').token
      post '/f/api/v1/messages', headers: { 'Authorization' => "Bearer #{read_token}" }, as: :json,
                                 params: { message: { subject: 'X', body: 'Y', recipient_ids: [other_user.id] } }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'PATCH /messages/:id' do
    let!(:message) { create_message(sender: user, recipients: [other_user], subject: 'Old') }

    it 'lets the sender change subject and text' do
      params = { message: { subject: 'New', body: 'Changed' } }
      patch "/f/api/v1/messages/#{message.id}", headers: headers, as: :json, params: params
      expect(response).to have_http_status(:ok)
      message.reload
      expect(message.subject).to eq 'New'
      expect(message.body.to_plain_text).to eq 'Changed'
      expect(message.edited_at).to be_present
    end

    it 'refuses others' do
      other_message = create_message(sender: other_user, recipients: [user])
      params = { message: { body: 'Changed' } }
      patch "/f/api/v1/messages/#{other_message.id}", headers: headers, as: :json, params: params
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'DELETE /messages/:id' do
    let!(:message) { create_message(sender: user, recipients: [other_user]) }

    it 'lets the sender delete the text and keeps a placeholder' do
      delete "/f/api/v1/messages/#{message.id}", headers: headers
      expect(response).to have_http_status(:no_content)
      message.reload
      expect(message).to be_deleted
      expect(message.body.to_plain_text).to eq ''
    end

    it 'refuses other members' do
      other_message = create_message(sender: other_user, recipients: [user])
      delete "/f/api/v1/messages/#{other_message.id}", headers: headers
      expect(response).to have_http_status(:forbidden)
    end

    context 'when the user is an admin' do
      let(:user) { create(:admin) }

      it 'tells the app it may delete, as a boolean' do
        other_message = create_message(sender: other_user, recipients: [third_user])
        get "/f/api/v1/messages/#{other_message.id}", headers: headers
        expect(json['message']['can_delete']).to be true
        expect(json['message']['can_edit']).to be false
      end

      it 'deletes messages of others' do
        other_message = create_message(sender: other_user, recipients: [third_user])
        delete "/f/api/v1/messages/#{other_message.id}", headers: headers
        expect(response).to have_http_status(:no_content)
      end
    end
  end

  describe 'safety' do
    let(:strangers_private) { create_message(sender: other_user, recipients: [third_user], private: true) }

    it 'hides private messages of others from every action, also for admins' do
      [user, create(:admin)].each do |member|
        h = { 'Authorization' => "Bearer #{create(:oauth2_access_token, resource_owner_id: member.id, scopes: api_scopes.join(' ')).token}" }
        get "/f/api/v1/messages/#{strangers_private.id}/thread", headers: h
        expect(response).to have_http_status(:not_found)
        patch "/f/api/v1/messages/#{strangers_private.id}", headers: h, as: :json, params: { message: { body: 'X' } }
        expect(response).to have_http_status(:not_found)
        delete "/f/api/v1/messages/#{strangers_private.id}", headers: h
        expect(response).to have_http_status(:not_found)
        post '/f/api/v1/messages', headers: h, as: :json, params: { message: { reply_to: strangers_private.id, body: 'X' } }
        expect(response).to have_http_status(:not_found)
      end
      expect(strangers_private.reload).not_to be_deleted
      expect(strangers_private.body.to_plain_text).to eq 'Some text'
    end

    it 'ignores sender, timestamps and deletion sent along with a new message' do
      post '/f/api/v1/messages', headers: headers, as: :json,
                                 params: { message: { subject: 'S', body: 'B', recipient_ids: [other_user.id],
                                                      sender_id: other_user.id, deleted_at: Time.now,
                                                      edited_at: Time.now, created_at: 1.year.ago } }
      message = Message.find(json['message']['id'])
      expect(message.sender).to eq user
      expect(message.deleted_at).to be_nil
      expect(message.edited_at).to be_nil
      expect(message.created_at).to be > 1.minute.ago
    end

    it 'does not let the website create pre-deleted or pre-edited messages' do
      post '/f/sessions', params: { nick: user.email, password: user.password }
      post '/f/messages', params: { message: { subject: 'Web', body: 'B', send_method: 'recipients',
                                               recipient_tokens: other_user.id.to_s,
                                               deleted_at: Time.now, edited_at: Time.now } }
      message = Message.find_by(subject: 'Web')
      expect(message).to be_present
      expect(message.deleted_at).to be_nil
      expect(message.edited_at).to be_nil
    end
  end

  describe 'GET /messages/recipients' do
    it 'finds users by name' do
      found = create(:user, first_name: 'Zebedäus')
      get '/f/api/v1/messages/recipients', headers: headers, params: { q: 'Zebed' }
      expect(response).to have_http_status(:ok)
      expect(json['users'].pluck('id')).to eq [found.id]
    end
  end
end
