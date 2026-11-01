# frozen_string_literal: true

# Puts an account's SAML users back on password sign-in (provider 'saml' to
# 'email') once its SAML settings are deleted: the rollback lever, run on
# every DELETE and safe to run again. A user who is a member of any account
# with SSO configured (its saml feature and a settings row) stays 'saml', or
# they could sign in to that account with a password and skip its SSO. That
# includes this account, should its settings be back by the time this runs.
class Comvor::SamlProviderResetJob < ApplicationJob
  queue_as :low

  def perform(account_id)
    sso_members = AccountUser.where(account_id: Comvor::SamlSso.configured_account_ids).select(:user_id)
    User.where(id: AccountUser.where(account_id: account_id).select(:user_id))
        .where.not(id: sso_members)
        .where(provider: 'saml')
        .update_all(provider: 'email', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end
end
