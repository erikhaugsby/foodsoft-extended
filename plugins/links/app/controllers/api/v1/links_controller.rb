# The coop's links (the website's "Links" menu) for the apps. Only names: the app opens
# /links/{id} in its web view, so addresses and credentials of indirect links stay on the server.
class Api::V1::LinksController < Api::V1::BaseController
  before_action -> { doorkeeper_authorize! 'config:user' }

  def index
    links = Link.ordered
    links = links.where(workgroup_id: [nil] + current_user.workgroups.map(&:id)) unless current_user.role_admin?
    render json: { links: links.map { |link| { id: link.id, name: link.name } } }
  end
end
