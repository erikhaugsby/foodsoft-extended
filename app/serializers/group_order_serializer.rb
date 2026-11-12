class GroupOrderSerializer < ActiveModel::Serializer
  attributes :id, :order_id, :price, :transport, :updated_on, :updated_by_user_id, :updated_by_name

  def price
    object.price.to_f
  end

  def transport
    object.transport&.to_f
  end

  def updated_by_name
    object.updated_by&.display
  end
end
