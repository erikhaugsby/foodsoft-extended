class OrderSerializer < ActiveModel::Serializer
  attributes :id, :name, :starts, :ends, :boxfill, :pickup, :is_open, :is_boxfill
  attributes :state, :supplier_id, :note, :end_action

  def is_open
    object.open?
  end

  def is_boxfill
    object.boxfill?
  end
end
