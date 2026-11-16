class OrderArticleSerializer < ActiveModel::Serializer
  attributes :id, :order_id, :price
  attributes :quantity, :tolerance, :units_to_order, :units_received, :result_manually_changed

  has_one :article

  # boxes delivered, as entered when receiving the order; null before
  def units_received
    object.units_received&.to_f
  end

  # amounts changed by hand: the website locks receiving this article, and so does the API
  def result_manually_changed
    object.result_manually_changed?
  end

  def price
    object.price.fc_price.to_f
  end
end
