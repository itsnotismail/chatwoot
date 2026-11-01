# frozen_string_literal: true

# Comvor: routes served by custom/ controllers. Prepended, so they match
# before config/routes.rb (and enterprise's controllers) for the same path;
# each needs its own name, or boot raises "route name already in use".
Rails.application.routes.prepend do
  post 'api/v1/auth/saml_login', to: 'comvor/saml_logins#create', as: :comvor_saml_login

  # Every verb config/routes.rb's `resource :saml_settings` answers, PUT
  # included (the dashboard updates with it).
  scope 'api/v1/accounts/:account_id', defaults: { format: 'json' } do
    get 'saml_settings', to: 'comvor/saml_settings#show', as: :comvor_saml_settings
    post 'saml_settings', to: 'comvor/saml_settings#create', as: :comvor_create_saml_settings
    patch 'saml_settings', to: 'comvor/saml_settings#update', as: :comvor_patch_saml_settings
    put 'saml_settings', to: 'comvor/saml_settings#update', as: :comvor_put_saml_settings
    delete 'saml_settings', to: 'comvor/saml_settings#destroy', as: :comvor_destroy_saml_settings
  end
end
