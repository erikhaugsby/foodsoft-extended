class Api::V1::OrdersController < Api::V1::BaseController
  include Concerns::CollectionScope
  include Concerns::SendOrderPdf

  DOCUMENTS = %w[groups articles fax matrix].freeze

  before_action -> { doorkeeper_authorize! 'orders:read', 'orders:write' }
  before_action -> { doorkeeper_authorize! 'orders:write' }, only: %i[create update finish send_to_supplier]
  before_action -> { doorkeeper_authorize! 'orders:read' }, only: :receive
  before_action :require_orders_or_pickups_role, only: %i[document receive]

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

  # Emails the order to the supplier, like the website's "Send to supplier" button (also again).
  # The email is sent in the background; +last_sent_mail+ is set once it has gone out.
  def send_to_supplier
    order = Order.where(state: %w[finished received]).find(params.require(:id))
    return unprocessable('Stock orders have no supplier to send to') if order.stockit?
    return unprocessable('The supplier has no email address') if order.supplier.email.blank?

    order.send_to_supplier!(current_user)
    render json: order.reload
  end

  # Receives a finished order, like the website's "Receive" page: optionally the boxes that
  # were delivered per article (+units_received+, distributed to the members as on the
  # website), then the order is +received+. Articles not listed stay as they are.
  def receive
    order = Order.where(state: %w[finished received]).find(params.require(:id))
    return unprocessable('Stock orders cannot be received') if order.stockit?

    data = params.fetch(:order, {})
    entries = data[:order_articles]
    return unprocessable('order_articles must be a list') unless entries.nil? || entries.is_a?(Array)

    # all entries are checked before anything is changed
    changes = Array(entries).map do |entry|
      bad_entry = !entry.is_a?(ActionController::Parameters) || entry[:id].blank?
      return unprocessable('each order article must be an object with id and units_received') if bad_entry

      units = entry[:units_received]
      units = nil if units.is_a?(String) && units.strip.empty?
      return unprocessable('units_received must not be negative') if units&.to_d&.negative?

      order_article = order.order_articles.find(entry[:id])
      # locked on the website as well
      return unprocessable(locked_message(order_article)) if order_article.result_manually_changed?

      [order_article, units]
    end

    to_tolerance = !data.key?(:rest_to_tolerance) || ActiveModel::Type::Boolean.new.cast(data[:rest_to_tolerance])
    rest_to = to_tolerance ? [:tolerance, nil] : [nil]

    Order.transaction do
      changes.each do |order_article, units|
        order_article.units_received = units
        if order_article.units_received_changed? && order_article.units_received.present?
          delivered = order_article.units_received * order_article.price.unit_quantity
          order_article.redistribute delivered, rest_to
        end
        order_article.save!
      end
      order.update_attribute(:state, 'received') unless order.received? # as the website: no validations
    end
    NotifyReceivedOrderJob.perform_later(order)
    render json: order.reload
  end

  # Sends one of the order PDFs.
  def document
    order = scope.find(params.require(:id))
    document = params.require(:document)
    raise ActiveRecord::RecordNotFound, 'Document not found' unless DOCUMENTS.include?(document)

    # the PDF titles show the end date
    if order.ends.nil?
      return render status: :unprocessable_entity,
                    json: { error: 'not_acceptable', error_description: 'The order has no end date yet' }
    end

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

    if order.supplier.nil? # stock orders have no supplier articles to choose from
      order.errors.add(:article_ids, 'can only be chosen for supplier orders')
      raise ActiveRecord::RecordInvalid, order
    end

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

  def locked_message(order_article)
    "#{order_article.article.name}: the members' amounts were changed by hand, please receive it on the website"
  end

  def unprocessable(description)
    render status: :unprocessable_entity, json: { error: 'not_acceptable', error_description: description }
  end

  def require_orders_or_pickups_role
    return if performed?
    return if current_user.role_orders? || current_user.role_pickups?

    raise Api::Errors::PermissionRequired, 'Forbidden, no permission'
  end
end
