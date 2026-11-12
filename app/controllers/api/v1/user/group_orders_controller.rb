# The current user's ordergroup's orders: what the household ordered per order,
# with its total and who changed it last.
class Api::V1::User::GroupOrdersController < Api::V1::BaseController
  include Concerns::CollectionScope

  before_action -> { doorkeeper_authorize! 'group_orders:user' }
  before_action :require_ordergroup

  # Filter with +q[order_id_in][]=…+.
  def index
    render_collection search_scope
  end

  def show
    render json: scope.find(params.require(:id))
  end

  private

  def scope
    current_ordergroup.group_orders.includes(:updated_by).order(updated_on: :desc)
  end
end
