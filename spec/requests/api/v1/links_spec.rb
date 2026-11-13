require 'spec_helper'

describe 'Links API' do
  let(:user) { create(:user) }
  let(:team) { create(:workgroup) }
  let(:headers) do
    { 'Authorization' => "Bearer #{create(:oauth2_access_token, resource_owner_id: user.id, scopes: 'config:user').token}" }
  end
  let(:json) { response.parsed_body }

  before do
    Link.create!(name: 'Webmail', url: 'https://mail.example.org', indirect: true, authorization: 'Basic secret')
    Link.create!(name: 'Accounting', url: 'https://books.example.org', workgroup_id: team.id)
    Link.create!(name: 'Calendar', url: 'https://cal.example.org')
  end

  it 'lists the links a member may open, by name, without addresses or credentials' do
    get '/f/api/v1/links', headers: headers
    expect(response).to have_http_status(:ok)
    expect(json['links'].pluck('name')).to eq %w[Calendar Webmail]
    expect(json['links'].first.keys).to eq %w[id name]
    expect(response.body).not_to include('example.org', 'secret')
  end

  it 'includes a workgroup link for its members' do
    Group.find(team.id).update!(user_ids: [user.id])
    get '/f/api/v1/links', headers: headers
    expect(json['links'].pluck('name')).to eq %w[Accounting Calendar Webmail]
  end

  it 'includes all links for admins' do
    get '/f/api/v1/links', headers: { 'Authorization' => "Bearer #{create(:oauth2_access_token, resource_owner_id: create(:admin).id, scopes: 'config:user').token}" }
    expect(json['links'].size).to eq 3
  end

  it 'needs a login' do
    get '/f/api/v1/links'
    expect(response).to have_http_status(:unauthorized)
  end
end
