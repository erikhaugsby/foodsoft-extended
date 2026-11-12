require 'spec_helper'

# Every API route must refuse requests without a valid login, so that no endpoint
# can be added without authentication by mistake. The routes are read from the
# app itself, so new endpoints are covered automatically.
describe 'API authentication on every route' do
  def self.api_routes
    Rails.application.routes.routes.filter_map do |route|
      path = route.path.spec.to_s
      verb = route.verb.to_s
      next if verb.blank? || path.exclude?('/api/v1/')

      next unless implemented?(route)

      url = path.sub('(.:format)', '').gsub(':foodcoop', FoodsoftConfig.scope).gsub(/:\w+/, '1')
      [verb.split('|').first, url]
    end.uniq
  end

  # Routes without code behind them (e.g. +resources+ with more actions than the controller has) are skipped.
  def self.implemented?(route)
    controller = "#{route.defaults[:controller]}_controller".camelize.safe_constantize
    controller&.action_methods&.include?(route.defaults[:action].to_s)
  end

  it 'finds the API routes' do
    expect(self.class.api_routes.size).to be > 30
  end

  api_routes.each do |verb, url|
    it "refuses #{verb} #{url} without a valid login" do
      process verb.downcase.to_sym, url, headers: { 'Accept' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)

      process verb.downcase.to_sym, url, headers: { 'Accept' => 'application/json',
                                                    'Authorization' => 'Bearer not-a-valid-token' }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
