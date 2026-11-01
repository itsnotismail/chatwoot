# frozen_string_literal: true

# When SAML sign-in through the Comvor portal is switched on: for the whole
# installation (the ENABLE_SAML_SSO_LOGIN kill switch and a portal it can
# trust), and for one account (its saml feature and a settings row).
module Comvor::SamlSso
  module_function

  def available?
    switched_on? && Comvor::PortalIdp.secure?
  end

  # The installation's ENABLE_SAML_SSO_LOGIN kill switch alone. On only for
  # the value true (or 'true'); it fails closed on everything else. That
  # includes every word GlobalConfigService reads as false (false, FALSE, 0,
  # f, F, off, OFF), which reach this as the stored string, and nil or a
  # blank value.
  def switched_on?
    GlobalConfigService.load('ENABLE_SAML_SSO_LOGIN', 'true').to_s == 'true'
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
