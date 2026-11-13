class OrderSerializer < ActiveModel::Serializer
  attributes :id, :name, :starts, :ends, :boxfill, :pickup, :is_open, :is_boxfill
  attributes :state, :supplier_id, :note, :end_action, :invoice_id, :supplier_min_order_quantity
  attributes :last_sent_mail, :supplier_has_email

  # shown to every member on the ordering page, also without the suppliers role (free text, e.g. "50 EUR")
  def supplier_min_order_quantity
    object.supplier&.min_order_quantity
  end

  # whether the order can be sent to the supplier at all (the website's button needs it too)
  def supplier_has_email
    object.supplier&.email.present? || false
  end

  def is_open
    object.open?
  end

  def is_boxfill
    object.boxfill?
  end
end
