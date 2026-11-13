class Api::V1::BaseController < ApplicationController
  include Concerns::AuthApi

  protect_from_forgery with: :null_session

  # Money and amount fields in requests: a number, or a string with digits and at most one
  # dot as decimal separator ("130.5"). Commas, thousands separators and exponents are refused,
  # whatever the user's language, so "130,5" or "1.300,50" never turn into a wrong amount.
  DECIMAL_PARAMS = %w[price tax deposit amount deposit_credit result].freeze
  DECIMAL_FORMAT = /\A\s*-?\d+(\.\d+)?\s*\z/

  before_action :skip_session
  before_action :authenticate
  before_action :check_decimal_params, unless: -> { request.get? || request.head? }

  rescue_from ActiveRecord::RecordNotFound, with: :not_found_handler
  rescue_from ActiveRecord::RecordNotSaved, with: :not_acceptable_handler
  rescue_from ActiveRecord::RecordInvalid, with: :not_acceptable_handler
  rescue_from Api::Errors::PermissionRequired, with: :permission_required_handler
  # values the database cannot hold (too large numbers, too long texts)
  rescue_from ActiveRecord::RangeError, ActiveRecord::ValueTooLong, with: :value_too_large_handler

  private

  # @return [Ordergroup] Current user's ordergroup, or +nil+ if no valid token or user has no ordergroup.
  def current_ordergroup
    current_user.try(:ordergroup)
  end

  def require_ordergroup
    authenticate
    return if current_ordergroup.present?

    raise Api::Errors::PermissionRequired, 'Forbidden, must be in an ordergroup'
  end

  def require_minimum_balance
    minimum_balance = FoodsoftConfig[:minimum_balance] or return
    return unless current_ordergroup.account_balance < minimum_balance

    raise Api::Errors::PermissionRequired, t('application.controller.error_minimum_balance', min: minimum_balance)
  end

  def require_enough_apples
    return unless current_ordergroup.not_enough_apples?

    s = t('group_orders.messages.not_enough_apples', apples: current_ordergroup.apples,
                                                     stop_ordering_under: FoodsoftConfig[:stop_ordering_under])
    raise Api::Errors::PermissionRequired, s
  end

  def require_config_enabled(config)
    return if FoodsoftConfig[config]

    raise Api::Errors::PermissionRequired, t('application.controller.error_not_enabled', config: config)
  end

  def skip_session
    request.session_options[:skip] = true
  end

  def check_decimal_params
    invalid = invalid_decimal_params(params.to_unsafe_h)
    return if invalid.empty?

    key, value = invalid.first
    render status: :unprocessable_entity,
           json: { error: 'not_acceptable',
                   error_description: "#{key} must be a number with a dot as decimal separator, e.g. 130.5 (got #{value.inspect})" }
  end

  # [key, value] pairs of decimal fields with an invalid value, anywhere in the (nested) params
  def invalid_decimal_params(data)
    case data
    when Hash
      data.flat_map do |key, value|
        if DECIMAL_PARAMS.include?(key.to_s) && !(value.is_a?(Hash) || value.is_a?(Array))
          valid_decimal?(value) ? [] : [[key, value]]
        else
          invalid_decimal_params(value)
        end
      end
    when Array then data.flat_map { |value| invalid_decimal_params(value) }
    else []
    end
  end

  def valid_decimal?(value)
    return true if value.nil? || (value.is_a?(Numeric) && value.to_f.finite?)
    return false unless value.is_a?(String)

    value.strip.empty? || value.match?(DECIMAL_FORMAT) # blank is left to the model's presence checks
  end

  def value_too_large_handler(_error)
    render status: :unprocessable_entity,
           json: { error: 'not_acceptable', error_description: 'A value is too large or too long' }
  end

  def not_found_handler(e)
    # remove where-clauses from error message (not suitable for end-users)
    msg = e.message.try { |m| m.sub(/\s*\[.*?\]\s*$/, '') } || 'Not found'
    render status: :not_found, json: { error: 'not_found', error_description: msg }
  end

  def not_acceptable_handler(e)
    msg = e.message || 'Data not acceptable'
    render status: :unprocessable_entity, json: { error: 'not_acceptable', error_description: msg }
  end

  def doorkeeper_unauthorized_render_options(error:)
    { json: { error: error.name, error_description: error.description } }
  end

  def doorkeeper_forbidden_render_options(error:)
    { json: { error: error.name, error_description: error.description } }
  end

  def permission_required_handler(e)
    msg = e.message || 'Forbidden, user has no access'
    render status: :forbidden, json: { error: 'forbidden', error_description: msg }
  end

  # @todo something with ApplicationHelper#show_user
  def show_user(user = current_user, **_options)
    user.display
  end
end
