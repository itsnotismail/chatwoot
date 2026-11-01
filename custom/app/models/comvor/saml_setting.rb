# frozen_string_literal: true

# An account's SAML settings row. To the Comvor sign-in (the comvor_saml
# strategy) the row only means "SSO is enabled for this account": the
# identity provider is always Comvor::PortalIdp, never what the row says.
# Writes are still pinned to the portal, so the row cannot drift from it.
#
# Shares account_saml_settings with enterprise's model while enterprise is
# present. Creating a row converts nobody: users become provider 'saml' one
# at a time, at their first SSO sign-in.
class Comvor::SamlSetting < ApplicationRecord
  include Comvor::SamlIdpPin

  self.table_name = 'account_saml_settings'

  belongs_to :account
end
