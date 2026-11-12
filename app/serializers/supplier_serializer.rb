class SupplierSerializer < ActiveModel::Serializer
  attributes :id, :name, :delivery_days, :min_order_quantity, :note
end
