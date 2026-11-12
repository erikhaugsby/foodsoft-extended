Rails.application.routes.draw do
  scope '/:foodcoop', constraints: { foodcoop: /__FOODCOOPS__/ } do
    namespace :api do
      namespace :v1 do
        resources :printer, only: [:show]
      end
    end

    resources :printer_jobs, only: %i[index create show destroy] do
      post :requeue, on: :member
      get :document, on: :member
    end
  end
end
