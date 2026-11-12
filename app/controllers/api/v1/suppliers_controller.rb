class Api::V1::SuppliersController < Api::V1::BaseController
  include Concerns::CollectionScope

  # Suppliers are needed to open orders, manage articles and file invoices.
  before_action lambda {
    doorkeeper_authorize! 'suppliers:read', 'orders:write', 'articles:read', 'articles:write',
                          'invoices:read', 'invoices:write'
  }

  def index
    render_collection search_scope
  end

  def show
    render json: scope.find(params.require(:id))
  end

  private

  def scope
    Supplier.undeleted.order(:name)
  end
end
