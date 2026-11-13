Rails.application.routes.draw do
  scope '/:foodcoop', constraints: { foodcoop: /__FOODCOOPS__/ } do
    resources :links, only: [:show]

    namespace :api do
      namespace :v1 do
        resources :links, only: [:index]
      end
    end

    namespace :admin do
      resources :links
    end
  end
end
