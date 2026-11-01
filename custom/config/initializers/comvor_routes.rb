# frozen_string_literal: true

# Comvor: routes served by custom/ controllers. Prepended, so they match
# before config/routes.rb (and enterprise's controllers) for the same path;
# each needs its own name, or boot raises "route name already in use".
Rails.application.routes.prepend do
  post 'api/v1/auth/saml_login', to: 'comvor/saml_logins#create', as: :comvor_saml_login
end
