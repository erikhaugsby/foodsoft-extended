class Api::V1::InvoicesController < Api::V1::BaseController
  include Concerns::CollectionScope

  ATTRIBUTES = [:number, :date, :note, :amount, :deposit, :deposit_credit,
                { order_ids: [], delivery_ids: [] }].freeze

  MAX_FILES = 10
  MAX_FILE_SIZE = 10.megabytes
  FILE_TYPES = %w[image/jpeg image/png application/pdf].freeze

  before_action -> { doorkeeper_authorize! 'invoices:read', 'invoices:write' }
  before_action -> { doorkeeper_authorize! 'invoices:write' },
                only: %i[create update create_attachment destroy_attachment]

  def index
    render_collection search_scope
  end

  def show
    render json: scope.find(params.require(:id))
  end

  # Creates an invoice. Send as +multipart/form-data+ to upload files
  # (JPEG, PNG or PDF) in +attachments[]+ along with the invoice fields.
  def create
    invoice = Invoice.new
    attributes = invoice_attributes(:supplier_id)
    return unless valid_links?(invoice, attributes) && valid_files?

    invoice.assign_attributes(attributes)
    invoice.created_by = current_user
    invoice.attachments.attach(uploaded_files) if uploaded_files.any?
    invoice.save!
    render json: invoice, status: :created
  end

  def update
    invoice = find_editable_invoice
    attributes = params[:invoice].present? ? invoice_attributes : {}
    return unless valid_links?(invoice, attributes) && valid_files?

    # assigning order_ids writes at once; roll back if the invoice turns out invalid
    Invoice.transaction do
      invoice.assign_attributes(attributes)
      invoice.attachments.attach(uploaded_files) if uploaded_files.any?
      invoice.save!
    end
    render json: invoice
  end

  # Adds files to an existing invoice.
  def create_attachment
    invoice = find_editable_invoice
    return unprocessable('No file uploaded in attachments[]') if uploaded_files.empty?
    return unless valid_files?

    # touch the record so that the files are validated and stored by save! below
    invoice.updated_at = Time.now
    invoice.attachments.attach(uploaded_files)
    invoice.save!
    render json: invoice, status: :created
  end

  # Downloads one attached file.
  def attachment
    attachment = scope.find(params.require(:id)).attachments.find(params.require(:attachment_id))
    send_data attachment.download, filename: attachment.filename.to_s, type: attachment.content_type,
                                   disposition: 'attachment'
  end

  def destroy_attachment
    invoice = find_editable_invoice
    invoice.attachments.find(params.require(:attachment_id)).purge
    render json: invoice.reload
  end

  private

  def scope
    Invoice.includes(:supplier, :orders).with_attached_attachments.order(date: :desc, id: :desc)
  end

  def find_editable_invoice
    invoice = scope.find(params.require(:id))
    return invoice if invoice.user_can_edit?(current_user)

    raise Api::Errors::PermissionRequired, 'Forbidden, invoice cannot be edited by this user'
  end

  def invoice_attributes(*extra)
    allowed = ATTRIBUTES + extra
    allowed += [:paid_on] if current_user.role_finance? # as in the web interface, payment is a finance matter
    params.require(:invoice).permit(*allowed)
  end

  # As in the web form: orders and deliveries already on this invoice, or not on any
  # invoice and from the invoice's supplier.
  def valid_links?(invoice, attributes)
    supplier_id = attributes[:supplier_id].presence || invoice.supplier_id
    { order_ids: Order, delivery_ids: Delivery }.each do |key, model|
      next unless attributes.key?(key)

      ids = Array(attributes[key]).compact_blank.map(&:to_i)
      allowed = model.where(id: ids).where('invoice_id = ? OR (invoice_id IS NULL AND supplier_id = ?)',
                                           invoice.id, supplier_id).pluck(:id)
      return unprocessable("#{key} must belong to the invoice's supplier and no other invoice") if (ids - allowed).any?
    end
    true
  end

  # Checks size and the real type of each file from its content, not its name or declared type.
  def valid_files?
    return unprocessable("At most #{MAX_FILES} files at a time") if uploaded_files.size > MAX_FILES

    uploaded_files.each do |file|
      return unprocessable("#{file.original_filename} is larger than 10 MB") if file.size > MAX_FILE_SIZE

      type = Marcel::MimeType.for(Pathname.new(file.tempfile.path)) # content only
      return unprocessable("#{file.original_filename} is not a JPEG, PNG or PDF") unless type.in?(FILE_TYPES)
    end
    true
  end

  def unprocessable(description)
    render status: :unprocessable_entity, json: { error: 'not_acceptable', error_description: description }
    false
  end

  # Files may be sent as top-level +attachments[]+ or nested as +invoice[attachments][]+.
  def uploaded_files
    @uploaded_files ||= begin
      nested = params[:invoice].respond_to?(:[]) ? params[:invoice][:attachments] : nil
      (Array(params[:attachments]) + Array(nested)).select { |f| f.respond_to?(:original_filename) }
    end
  end
end
