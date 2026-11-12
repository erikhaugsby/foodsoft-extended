class Api::V1::MessagesController < Api::V1::BaseController
  include Concerns::CollectionScope

  SEND_METHODS = %w[recipients all workgroup ordergroup messagegroup order].freeze

  before_action :require_messages_enabled
  before_action -> { doorkeeper_authorize! 'messages:read', 'messages:write' }, only: %i[index show thread recipients]
  before_action -> { doorkeeper_authorize! 'messages:write' }, only: %i[create update destroy]

  # Messages the current user may read, newest first. Deleted messages are left out,
  # except with +threads=true+, which lists only the first message of each thread.
  def index
    messages = readable_scope.order(created_at: :desc)
    messages = if ActiveModel::Type::Boolean.new.cast(params[:threads])
                 messages.threads
               else
                 messages.not_deleted
               end
    messages = messages.page(params[:page].to_i).per(per_page)
    render json: messages, meta: collection_meta(messages), scope: current_user
  end

  def show
    render json: find_readable(params.require(:id)), scope: current_user, include_recipients: true
  end

  # All readable messages of the thread the message belongs to, oldest first.
  # Deleted messages are included (without text), so that replies still make sense.
  def thread
    message = find_readable(params.require(:id))
    thread_ids = Message.thread(message.reply_to || message.id).select(:id)
    messages = readable_scope.where(id: thread_ids).order(:created_at, :id)
    render json: messages, root: 'messages', scope: current_user
  end

  # Users and groups to send a message to, searched by name.
  def recipients
    q = params[:q].to_s.strip
    if q.length < 2
      render json: { users: [], groups: [] }
      return
    end

    users = User.undeleted.natural_search(q).order(:first_name, :last_name).limit(20)
    groups = Group.undeleted.where(type: %w[Workgroup Ordergroup Messagegroup])
                  .where(Group.arel_table[:name].matches("%#{Group.sanitize_sql_like(q)}%"))
                  .order(:name).limit(20)
    render json: {
      users: users.map { |user| { id: user.id, name: user.display } },
      groups: groups.map { |group| { id: group.id, name: group.name, type: group.type.underscore } }
    }
  end

  def create
    data = params.require(:message)
    send_method = data[:send_method].presence || 'recipients'
    return unprocessable("Unknown send_method '#{send_method}'") unless SEND_METHODS.include?(send_method)
    if send_method == 'all' && FoodsoftConfig[:mailing_list].present?
      return unprocessable('Sending to all members is not allowed, please use the mailing list')
    end

    message = current_user.send_messages.new
    message.send_method = send_method
    message.group_id = data[:group_id] if %w[workgroup ordergroup messagegroup].include?(send_method)
    message.order_id = data[:order_id] if send_method == 'order'
    message.mrecipients_ids = Array(data[:recipient_ids]).map(&:to_i)

    if data[:reply_to].present?
      original = find_readable(data[:reply_to])
      message.reply_to = original.reply_to || original.id
      message.add_recipients [original.sender_id] if original.sender_id
      message.group_id = original.group_id if original.group_id && data[:group_id].blank?
      message.private = original.private
      message.subject = I18n.t('messages.model.reply_subject', subject: original.subject)
    end

    message.private = ActiveModel::Type::Boolean.new.cast(data[:private]) if data.key?(:private)
    message.subject = data[:subject] if data[:subject].present?
    message.body = plain_text_to_html(data[:body])

    ActiveRecord::Base.transaction do
      current_user.with_lock { message.save! }
    end
    DeliverMessageJob.perform_later(message)
    render json: message, status: :created, scope: current_user, include_recipients: true
  end

  # Changes subject and/or text. Emails that were already sent stay as they were.
  def update
    message = find_readable(params.require(:id))
    raise Api::Errors::PermissionRequired, 'Forbidden, only the sender can edit this message' unless message.can_edit?(current_user)

    data = params.require(:message)
    message.edit!(subject: data[:subject].presence, body: data.key?(:body) ? plain_text_to_html(data[:body]) : nil)
    render json: message, scope: current_user, include_recipients: true
  end

  # Deletes the text, keeps a placeholder in the thread. Emails that were already sent stay as they were.
  def destroy
    message = find_readable(params.require(:id))
    raise Api::Errors::PermissionRequired, 'Forbidden, you cannot delete this message' unless message.can_delete?(current_user)

    message.soft_delete!
    head :no_content
  end

  private

  def require_messages_enabled
    raise ActiveRecord::RecordNotFound, 'Messages are not enabled' unless FoodsoftMessages.enabled?
  end

  def readable_scope
    Message.readable_for(current_user).includes(:sender, :group, :message_recipients, :rich_text_body)
  end

  # Private messages of others are reported as not found, like missing ones.
  def find_readable(id)
    message = Message.find(id)
    raise ActiveRecord::RecordNotFound, 'Message not found' unless message.is_readable_for?(current_user)

    message
  end

  # Apps send plain text; the website stores rich text (HTML).
  def plain_text_to_html(text)
    return '' if text.blank?

    ERB::Util.html_escape(text.to_s).gsub(/\r?\n/, '<br>')
  end

  def unprocessable(description)
    render status: :unprocessable_entity, json: { error: 'not_acceptable', error_description: description }
  end
end
