Rails.application.routes.draw do
  scope '/:foodcoop', constraints: { foodcoop: /__FOODCOOPS__/ } do
    resources :links, only: [:show]

    namespace :admin do
      resources :links
    end
  end
end
