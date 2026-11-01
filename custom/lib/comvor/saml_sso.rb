# frozen_string_literal: true

# When SAML sign-in through the Comvor portal is switched on: for the whole
# installation (the ENABLE_SAML_SSO_LOGIN kill switch and a portal it can
# trust), and for one account (its saml feature and a settings row).
module Comvor::SamlSso
  module_function

  def available?
    GlobalConfigService.load('ENABLE_SAML_SSO_LOGIN', 'true').to_s != 'false' && Comvor::PortalIdp.secure?
  end

  def enabled_for?(account)
    account.present? && available? && account.feature_enabled?('saml') && Comvor::SamlSetting.exists?(account_id: account.id)
  end
end
