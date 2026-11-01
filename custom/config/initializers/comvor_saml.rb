# frozen_string_literal: true

# Comvor: the comvor_saml OmniAuth strategy (portal SAML sign-in), at
# /omniauth/comvor_saml. Middleware is built once at boot, so the strategy
# is required here instead of being autoloaded (and reloaded).
comvor_saml_strategies = Rails.root.join('custom/lib/omni_auth')
Rails.autoloaders.main.ignore(comvor_saml_strategies)
require comvor_saml_strategies.join('strategies/comvor_saml').to_s

Rails.application.config.middleware.use OmniAuth::Builder do
  provider OmniAuth::Strategies::ComvorSaml
end
