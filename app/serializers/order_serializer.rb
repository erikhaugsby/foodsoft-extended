class OrderSerializer < ActiveModel::Serializer
  attributes :id, :name, :starts, :ends, :boxfill, :pickup, :is_open, :is_boxfill
  attributes :state, :supplier_id, :note, :end_action, :invoice_id, :supplier_min_order_quantity

  # shown to every member on the ordering page, also without the suppliers role (free text, e.g. "50 EUR")
  def supplier_min_order_quantity
    object.supplier&.min_order_quantity
  end

  def is_open
    object.open?
  end

  def is_boxfill
    object.boxfill?
  end
end
