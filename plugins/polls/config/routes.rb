Rails.application.routes.draw do
  scope '/:foodcoop', constraints: { foodcoop: /__FOODCOOPS__/ } do
    resources :polls do
      member do
        get :vote
        post :vote
      end
    end
  end
end
