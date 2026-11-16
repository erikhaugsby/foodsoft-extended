class MessageSerializer < ActiveModel::Serializer
  attributes :id, :subject, :body, :body_html, :sender_id, :sender_name, :group_id, :group_name,
             :reply_to, :private, :created_at, :edited_at, :deleted, :recipient_count,
             :can_edit, :can_delete, :for_me

  # Only for a single message: the list can be long for messages to all members.
  attribute :recipients, if: -> { instance_options[:include_recipients] }

  # Plain text, for apps. A deleted message has no text.
  def body
    return nil if object.deleted?

    object.body.to_plain_text
  end

  def body_html
    return nil if object.deleted?

    object.body.to_trix_html
  end

  def group_name
    object.group&.name
  end

  def deleted
    object.deleted?
  end

  def recipient_count
    object.message_recipients.size
  end

  def recipients
    object.recipients.map { |user| { id: user.id, name: user.display } }
  end

  # Addressed to the current user, directly or through a group, all members or an order:
  # exactly the people Foodsoft emails it to. Uses the preloaded recipients, no extra query.
  def for_me
    scope.present? && object.message_recipients.any? { |recipient| recipient.user_id == scope.id }
  end

  def can_edit
    object.can_edit?(scope)
  end

  def can_delete
    object.can_delete?(scope)
  end
end
