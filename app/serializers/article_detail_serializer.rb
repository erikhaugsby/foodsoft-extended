# Article with the fields needed to manage it (prices, availability).
# {ArticleSerializer} is the member-facing subset.
class ArticleDetailSerializer < ArticleSerializer
  attributes :order_number, :availability, :price, :tax, :deposit, :fc_price

  def price
    object.price.to_f
  end

  def deposit
    object.deposit.to_f
  end

  def fc_price
    object.fc_price.to_f
  end
end
