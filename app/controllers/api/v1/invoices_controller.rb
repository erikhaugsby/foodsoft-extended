class Api::V1::InvoicesController < Api::V1::BaseController
  include Concerns::CollectionScope

  ATTRIBUTES = [:number, :date, :note, :amount, :deposit, :deposit_credit,
                { order_ids: [], delivery_ids: [] }].freeze

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
    invoice = Invoice.new(invoice_attributes(:supplier_id))
    invoice.created_by = current_user
    invoice.attachments.attach(uploaded_files) if uploaded_files.any?
    invoice.save!
    render json: invoice, status: :created
  end

  def update
    invoice = find_editable_invoice
    invoice.assign_attributes(invoice_attributes) if params[:invoice].present?
    invoice.attachments.attach(uploaded_files) if uploaded_files.any?
    invoice.save!
    render json: invoice
  end

  # Adds files to an existing invoice.
  def create_attachment
    invoice = find_editable_invoice
    if uploaded_files.empty?
      return render status: :unprocessable_entity,
                    json: { error: 'not_acceptable', error_description: 'No file uploaded in attachments[]' }
    end

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

  # Files may be sent as top-level +attachments[]+ or nested as +invoice[attachments][]+.
  def uploaded_files
    @uploaded_files ||= begin
      nested = params[:invoice].respond_to?(:[]) ? params[:invoice][:attachments] : nil
      (Array(params[:attachments]) + Array(nested)).select { |f| f.respond_to?(:original_filename) }
    end
  end
end
