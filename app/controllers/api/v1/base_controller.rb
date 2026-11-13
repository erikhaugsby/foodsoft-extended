class Api::V1::BaseController < ApplicationController
  include Concerns::AuthApi

  protect_from_forgery with: :null_session

  # Money and amount fields in requests: a number, or a string with digits and at most one
  # dot as decimal separator ("130.5"). Commas, thousands separators and exponents are refused,
  # whatever the user's language, so "130,5" or "1.300,50" never turn into a wrong amount.
  DECIMAL_PARAMS = %w[price tax deposit amount deposit_credit result units_received].freeze
  DECIMAL_FORMAT = /\A\s*-?\d+(\.\d+)?\s*\z/

  before_action :skip_session
  before_action :authenticate
  # Whole numbers: digits only ("3", 3). Ids and id lists (*_id, *_ids) as well.
  INTEGER_PARAMS = %w[quantity tolerance unit_quantity page per_page].freeze
  # Dates and times: ISO 8601 only (2026-12-31, 2026-12-31T18:00, 2026-12-31T18:00:00+01:00)
  DATE_PARAMS = %w[starts ends boxfill pickup date paid_on].freeze
  DATE_FORMAT = /\A(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})?)?\z/
  BOOLEAN_PARAMS = %w[ignore_warnings availability private for_me threads rest_to_tolerance].freeze
  BOOLEAN_VALUES = [true, false, 'true', 'false', '1', '0', 1, 0].freeze
  # top-level request objects, e.g. {"order": {...}}
  OBJECT_PARAMS = %w[order article invoice message group_order_article financial_transaction supplier].freeze

  before_action :check_decimal_params, unless: -> { request.get? || request.head? }

  rescue_from ActiveRecord::RecordNotFound, with: :not_found_handler
  rescue_from ActiveRecord::RecordNotSaved, with: :not_acceptable_handler
  rescue_from ActiveRecord::RecordInvalid, with: :not_acceptable_handler
  rescue_from Api::Errors::PermissionRequired, with: :permission_required_handler
  # values the database cannot hold (too large numbers, too long texts)
  rescue_from ActiveRecord::RangeError, ActiveRecord::ValueTooLong, ActiveModel::RangeError,
              with: :value_too_large_handler
  rescue_from ActionController::ParameterMissing, with: :parameter_missing_handler

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

  # Runs after all before_actions (login, scopes, roles), right before the action itself,
  # so unauthorized requests still get 401/403 first.
  def send_action(method_name, *args)
    check_input_params
    return if performed?

    super
  end

  # Checks the types of whole numbers, ids, dates, booleans and request objects anywhere in
  # the params, so a wrong type gets a clear error instead of being misread or crashing.
  def check_input_params
    data = params.to_unsafe_h.except('controller', 'action', 'format', 'foodcoop')
    # list searches (ransack) need an object; other actions may use q as plain search text
    return render_input_problem('q must be an object') if action_name == 'index' && data.key?('q') && !data['q'].is_a?(Hash)

    problems = input_problems(data)
    # a malformed value (422) is reported before an id that cannot exist (404)
    problem = problems.find { |p| p.is_a?(String) } || problems.first
    render_input_problem(problem) if problem
  end

  def render_input_problem(problem)
    if problem.is_a?(Array) # [:not_found, message]: an id with letters cannot exist
      render status: :not_found, json: { error: 'not_found', error_description: problem.last }
    else
      render status: :unprocessable_entity, json: { error: 'not_acceptable', error_description: problem }
    end
  end

  def input_problems(data)
    case data
    when Hash
      data.flat_map do |key, value|
        [param_problem(key.to_s, value)].compact + (container?(value) ? input_problems(value) : [])
      end
    when Array then data.flat_map { |value| container?(value) ? input_problems(value) : [] }
    else []
    end
  end

  def param_problem(key, value)
    if OBJECT_PARAMS.include?(key)
      "#{key} must be an object" unless value.is_a?(Hash)
    elsif key.end_with?('_ids')
      "#{key} must be a list of ids" unless value.is_a?(Array) && value.all? { |v| blank_or?(v) { integer?(v) } }
    elsif key == 'id' || key.end_with?('_id') # an id with letters cannot exist
      [:not_found, "#{key} #{value} not found"] unless blank_or?(value) { integer?(value) }
    elsif INTEGER_PARAMS.include?(key)
      "#{key} must be a whole number" unless blank_or?(value) { integer?(value) && value.to_i >= minimum(key) }
    elsif DATE_PARAMS.include?(key)
      "#{key} must be a date like 2026-12-31 or 2026-12-31T18:00" unless blank_or?(value) { date?(value) }
    elsif BOOLEAN_PARAMS.include?(key)
      "#{key} must be true or false" unless value.nil? || BOOLEAN_VALUES.include?(value)
    end
  end

  def container?(value)
    value.is_a?(Hash) || value.is_a?(Array)
  end

  def blank_or?(value)
    (value.nil? || (value.is_a?(String) && value.strip.empty?)) || yield
  end

  def integer?(value)
    value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A\s*\d+\s*\z/))
  end

  def minimum(key)
    %w[page per_page].include?(key) ? 1 : 0
  end

  def date?(value)
    match = value.is_a?(String) && DATE_FORMAT.match(value.strip)
    return false unless match

    year, month, day, hour, minute, second = match.captures.map { |part| part&.to_i }
    Date.valid_date?(year, month, day) && (hour || 0) < 24 && (minute || 0) < 60 && (second || 0) < 60
  end

  def parameter_missing_handler(error)
    render status: :bad_request, json: { error: 'bad_request', error_description: error.message }
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
