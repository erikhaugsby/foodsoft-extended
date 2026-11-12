Rails.application.routes.draw do
  scope '/:foodcoop', constraints: { foodcoop: /__FOODCOOPS__/ } do
    resources :documents do
      get :move
      get :new
      get :new_folder
    end
  end
end
