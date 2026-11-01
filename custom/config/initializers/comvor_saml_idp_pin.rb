# frozen_string_literal: true

# Comvor: the Comvor portal is the only SAML identity provider. The settings
# model refuses any other (Comvor::SamlIdpPin), and a middleware in front of
# the SAML OmniAuth strategy refuses to sign anyone in against a stored row
# that does not name the portal (ComvorSamlCallbackGuard). Both are attached
# from here so the enterprise files stay as upstream ships them.
Rails.application.config.to_prepare do
  AccountSamlSettings.include(Comvor::SamlIdpPin) if Object.const_defined?(:AccountSamlSettings) && !(AccountSamlSettings < Comvor::SamlIdpPin)
end

# The settings validation stops new bad rows; this stops a row written
# before it, however it got there, from being trusted at sign-in. Defined
# here rather than under lib/ because middleware is built before autoloading.
class ComvorSamlCallbackGuard
  PATH_PREFIX = '/omniauth/saml'

  def initialize(app)
    @app = app
  end

  def call(env)
    # Matched the way OmniAuth matches its own paths (case-insensitive, with
    # SCRIPT_NAME), so no spelling of the path reaches SAML unguarded.
    return @app.call(env) unless Rack::Request.new(env).path.downcase.start_with?(PATH_PREFIX) && Comvor::PortalIdp.enforced?

    request = ActionDispatch::Request.new(env)
    account_id = request.params['account_id'] || request.session[:saml_account_id]
    return @app.call(env) if account_id.blank? || pinned_account?(account_id)

    Rails.logger.warn("comvor: SAML sign-in refused for account #{account_id}: settings do not name the Comvor portal")
    [403, { 'Content-Type' => 'text/plain' }, ['SAML sign-in is not available for this account']]
  end

  private

  def pinned_account?(account_id)
    return false unless Comvor::PortalIdp.configured?

    AccountSamlSettings.where(account_id: account_id).all? { |settings| Comvor::PortalIdp.pinned?(settings) }
  rescue Comvor::PortalIdp::MetadataError => e
    Rails.logger.warn("comvor: SAML sign-in refused, portal metadata unreadable: #{e.message}")
    false
  end
end

# SAML_SETUP_PROC is defined by the enterprise SAML initializer, which
# config/application.rb loads before this file; without it there is no SAML
# middleware to guard.
Rails.application.config.middleware.insert_before OmniAuth::Builder, ComvorSamlCallbackGuard if defined?(SAML_SETUP_PROC)
