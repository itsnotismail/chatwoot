# frozen_string_literal: true

# When SAML sign-in through the Comvor portal is switched on: for the whole
# installation (the ENABLE_SAML_SSO_LOGIN kill switch and a portal it can
# trust), and for one account (its saml feature and a settings row).
module Comvor::SamlSso
  module_function

  def available?
    switched_on? && Comvor::PortalIdp.secure?
  end

  # The installation's ENABLE_SAML_SSO_LOGIN kill switch alone.
  def switched_on?
    GlobalConfigService.load('ENABLE_SAML_SSO_LOGIN', 'true').to_s != 'false'
  end

  def enabled_for?(account)
    account.present? && available? && configured_for?(account)
  end

  # The account's own half: its saml feature and a settings row, whatever
  # the installation switches say.
  def configured_for?(account)
    account.feature_enabled?('saml') && Comvor::SamlSetting.of_account(account.id).exists?
  end

  # Ids of the accounts configured_for? holds for.
  def configured_account_ids
    Account.where(id: Comvor::SamlSetting.select(:account_id)).select { |account| account.feature_enabled?('saml') }.map(&:id)
  end
end
