class Api::V1::ArticlesController < Api::V1::BaseController
  include Concerns::CollectionScope

  ATTRIBUTES = %i[name article_category_id unit unit_quantity note manufacturer origin order_number
                  price tax deposit availability].freeze

  before_action -> { doorkeeper_authorize! 'articles:read', 'articles:write' }
  before_action -> { doorkeeper_authorize! 'articles:write' }, only: %i[create update destroy]

  def index
    articles = search_scope
    render json: articles, each_serializer: ArticleDetailSerializer, meta: collection_meta(articles)
  end

  def show
    render_article scope.find(params.require(:id))
  end

  def create
    attributes = article_params.permit(:supplier_id, *ATTRIBUTES)
    supplier = Supplier.undeleted.find(attributes.require(:supplier_id))
    article = supplier.articles.build(attributes.except(:supplier_id))
    article.tax = FoodsoftConfig[:tax_default] if article.tax.nil?
    article.save!
    render_article article, status: :created
  end

  def update
    article = scope.find(params.require(:id))
    article.update!(article_params.permit(*ATTRIBUTES))
    render_article article
  end

  # Marks the article as deleted, unless it is part of an open order.
  def destroy
    article = scope.find(params.require(:id))
    if article.in_open_order
      return render status: :unprocessable_entity,
                    json: { error: 'not_acceptable',
                            error_description: I18n.t('articles.model.error_in_use', article: article.name.to_s) }
    end

    article.mark_as_deleted
    render_article article
  end

  private

  def scope
    Article.undeleted.not_in_stock.includes(:supplier)
  end

  def article_params
    params.require(:article)
  end

  def render_article(article, status: :ok)
    render json: article, serializer: ArticleDetailSerializer, status: status
  end
end
