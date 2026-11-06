# frozen_string_literal: true

# Comvor: the Comvor portal is the only SAML identity provider. The settings
# model refuses any other (Comvor::SamlIdpPin). Comvor::SamlSetting includes
# it directly; enterprise's AccountSamlSettings, present only where enterprise/
# is (development, specs, a phase-3 rollback), gets it from here so the
# enterprise files stay as upstream ships them.
Rails.application.config.to_prepare do
  AccountSamlSettings.include(Comvor::SamlIdpPin) if Object.const_defined?(:AccountSamlSettings) && !(AccountSamlSettings < Comvor::SamlIdpPin)
end
