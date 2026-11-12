class InvoiceSerializer < ActiveModel::Serializer
  attributes :id, :supplier_id, :supplier_name, :number, :date, :paid_on, :note
  attributes :amount, :deposit, :deposit_credit
  attributes :created_at, :created_by_user_id, :order_ids, :attachments

  def supplier_name
    object.supplier.try(:name)
  end

  def amount
    object.amount.to_f
  end

  def deposit
    object.deposit.to_f
  end

  def deposit_credit
    object.deposit_credit.to_f
  end

  def order_ids
    object.orders.map(&:id)
  end

  def attachments
    object.attachments.map do |attachment|
      {
        id: attachment.id,
        filename: attachment.filename.to_s,
        content_type: attachment.content_type,
        byte_size: attachment.byte_size
      }
    end
  end
end
