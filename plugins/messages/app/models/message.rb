require 'base32'

class Message < ApplicationRecord
  belongs_to :sender, class_name: 'User'
  belongs_to :group, optional: true, class_name: 'Group'
  belongs_to :reply_to_message, optional: true, class_name: 'Message', foreign_key: 'reply_to'
  has_many :message_recipients, dependent: :destroy
  has_many :recipients, through: :message_recipients, source: :user
  has_one :last_reply, -> { order(created_at: :desc) }, class_name: 'Message', foreign_key: :reply_to

  attr_accessor :send_method, :recipient_tokens, :order_id, :mrecipients_ids

  scope :threads, -> { where(reply_to: nil) }
  scope :not_deleted, -> { where(deleted_at: nil) }
  scope :thread, ->(id) { where('id = ? OR reply_to = ?', id, id) }
  scope :readable_for, lambda { |user|
    return none unless user

    left_joins(:message_recipients)
      .where('messages.private = FALSE OR messages.sender_id = :user_id OR message_recipients.user_id = :user_id',
             user_id: user.id)
      .distinct
  }
  scope :last_readable_for, lambda { |user, nr|
    user_id = user.try(&:id)
    received = MessageRecipient.select(:message_id, :user_id).where(user_id: user_id).limit(nr)

    joins("LEFT OUTER JOIN (#{received.to_sql}) sub ON messages.id = sub.message_id")
      .where('private = ? OR sender_id = ? OR sub.user_id = ?', false, user_id, user_id)
  }

  validates_presence_of :message_recipients, :subject, :body
  validates_length_of :subject, in: 1..255

  after_initialize do
    @mrecipients_ids ||= []
    @send_method ||= 'recipients'
  end

  before_create :create_salt
  before_validation :create_message_recipients, on: :create

  has_rich_text :body

  # Override the `attributes=` method to exclude `mrecipients_ids`
  def attributes=(new_attributes)
    new_attributes = new_attributes.with_indifferent_access if new_attributes.respond_to?(:with_indifferent_access)

    # Log the attributes for debugging purposes
    Rails.logger.debug { "Original attributes: #{new_attributes.inspect}" }

    # Remove `mrecipients_ids` from the attributes hash
    new_attributes = new_attributes.except(:mrecipients_ids, 'mrecipients_ids')

    # Log the sanitized attributes for debugging purposes
    Rails.logger.debug { "Sanitized attributes: #{new_attributes.inspect}" }

    super(new_attributes)
  end

  attr_writer :mrecipients_ids

  def add_recipients(users)
    @mrecipients_ids += users
  end

  def group_id=(group_id)
    group = Group.find(group_id) if group_id.present?
    if group
      @send_method = 'workgroup' if group.type == 'Workgroup'
      @send_method = 'ordergroup' if group.type == 'Ordergroup'
      @send_method = 'messagegroup' if group.type == 'Messagegroup'
    end
    super
  end

  def workgroup_id
    group_id if send_method == 'workgroup'
  end

  def ordergroup_id
    group_id if send_method == 'ordergroup'
  end

  def messagegroup_id
    group_id if send_method == 'messagegroup'
  end

  def workgroup_id=(workgroup_id)
    self.group_id = workgroup_id if send_method == 'workgroup'
  end

  def ordergroup_id=(ordergroup_id)
    self.group_id = ordergroup_id if send_method == 'ordergroup'
  end

  def messagegroup_id=(messagegroup_id)
    self.group_id = messagegroup_id if send_method == 'messagegroup'
  end

  def order_id=(order_id)
    @order_id = order_id
    @send_method ||= 'order'
  end

  def recipient_tokens=(ids)
    @recipient_tokens = ids
    @mrecipients_ids = ids.split(',').map(&:to_i)
  end

  def mail_to=(user_id)
    @mrecipients_ids = [user_id]
  end

  def mail_hash_for_user(user)
    digest = Digest::SHA1.new
    digest.update id.to_s
    digest.update ':'
    digest.update salt
    digest.update ':'
    digest.update user.id.to_s
    Base32.encode digest.digest
  end

  # Returns true if this message is a system message, i.e. was sent automatically by Foodsoft itself.
  def system_message?
    sender_id.nil?
  end

  def sender_name
    system_message? ? I18n.t('layouts.foodsoft') : sender.display
  rescue StandardError
    '?'
  end

  def is_readable_for?(user)
    !private || sender == user || message_recipients.where(user: user).any?
  end

  def deleted?
    deleted_at.present?
  end

  def edited?
    edited_at.present?
  end

  # Only the sender can change subject and text of a message, as long as it is not deleted.
  def can_edit?(user)
    return false if user.nil? || deleted? || system_message?

    sender_id == user.id
  end

  # The sender and admins can delete a message.
  def can_delete?(user)
    return false if user.nil? || deleted?

    sender_id == user.id || user.role_admin?
  end

  # Changes subject and text. Emails that were already sent are not changed.
  def edit!(subject:, body:)
    self.subject = subject unless subject.nil?
    self.body = body unless body.nil?
    self.edited_at = Time.now
    save!
  end

  # Deletes the text of a message, but keeps the record, so that replies in its thread
  # still make sense. The subject is kept as the title of the thread.
  # Emails that were already sent are not changed.
  def soft_delete!
    transaction do
      rich_text_body&.destroy
      update_columns(deleted_at: Time.now)
    end
  end

  def can_toggle_private?(user)
    return true if sender == user
    return false if private?

    user.role_admin?
  end

  private

  def create_message_recipients
    user_ids = @mrecipients_ids
    user_ids += User.undeleted.pluck(:id) if send_method == 'all'
    user_ids += Group.find(group_id).users.pluck(:id) if group_id.present?
    user_ids += Order.find(order_id).users_ordered.pluck(:id) if send_method == 'order'

    user_ids.uniq.each do |user_id|
      recipient = MessageRecipient.new message: self, user_id: user_id
      message_recipients << recipient
    end
  end

  def create_salt
    self.salt = [Array.new(6) { rand(256).chr }.join].pack('m').chomp
  end
end
