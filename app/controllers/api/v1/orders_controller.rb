class Api::V1::OrdersController < Api::V1::BaseController
  include Concerns::CollectionScope
  include Concerns::SendOrderPdf

  DOCUMENTS = %w[groups articles fax matrix].freeze

  before_action -> { doorkeeper_authorize! 'orders:read', 'orders:write' }
  before_action -> { doorkeeper_authorize! 'orders:write' }, only: %i[create update finish]
  before_action :require_orders_or_pickups_role, only: :document

  def index
    render_collection search_scope
  end

  def show
    render json: scope.find(params.require(:id))
  end

  # Opens a new order for a supplier. When no +article_ids+ are given, all
  # available articles of the supplier are included.
  def create
    supplier = Supplier.undeleted.find(order_params.require(:supplier_id))
    return unless valid_end_action?

    order = Order.new(order_attributes.merge(supplier_id: supplier.id))
    order.init_dates
    order.article_ids = article_ids_for(order) || supplier.articles.available.pluck(:id)
    order.created_by = current_user
    order.updated_by = current_user
    order.save!
    render json: order.reload, status: :created
  end

  def update
    order = scope.find(params.require(:id))
    return unless valid_end_action?

    order.assign_attributes(order_attributes)
    article_ids = article_ids_for(order)
    order.article_ids = article_ids unless article_ids.nil?
    order.ignore_warnings = ActiveModel::Type::Boolean.new.cast(order_params[:ignore_warnings])
    order.updated_by = current_user
    order.save!
    render json: order.reload
  end

  # Closes an open order for ordering (state +finished+).
  def finish
    order = Order.where(state: 'open').find(params.require(:id))
    order.finish!(current_user)
    render json: order.reload
  end

  # Sends one of the order PDFs.
  def document
    order = scope.find(params.require(:id))
    document = params.require(:document)
    raise ActiveRecord::RecordNotFound, 'Document not found' unless DOCUMENTS.include?(document)

    send_order_pdf order, document
  end

  private

  def scope
    Order.includes(:supplier)
  end

  def order_params
    params.require(:order)
  end

  def order_attributes
    attributes = order_params.permit(:starts, :ends, :boxfill, :pickup, :note, :end_action)
    attributes.delete(:end_action) if attributes[:end_action].blank?
    attributes
  end

  # @return [Array<Integer>, nil] Requested articles that belong to the order's supplier, or +nil+ when not given.
  def article_ids_for(order)
    return nil unless order_params.key?(:article_ids)

    ids = Array(order_params[:article_ids]).compact_blank
    order.supplier.articles.undeleted.where(id: ids).pluck(:id)
  end

  def valid_end_action?
    end_action = order_params[:end_action]
    return true if end_action.blank? || Order.end_actions.key?(end_action.to_s)

    render status: :unprocessable_entity,
           json: { error: 'not_acceptable', error_description: "Invalid end_action: #{end_action}" }
    false
  end

  def require_orders_or_pickups_role
    return if performed?
    return if current_user.role_orders? || current_user.role_pickups?

    raise Api::Errors::PermissionRequired, 'Forbidden, no permission'
  end
end
