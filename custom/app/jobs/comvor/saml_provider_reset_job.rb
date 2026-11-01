# frozen_string_literal: true

# Puts an account's users back on password sign-in (provider 'email') once
# its SAML settings are deleted: the rollback lever. A user who is a member
# of any account that has SAML settings stays 'saml', or they could sign in
# to that account with a password and skip its SSO. That includes this
# account, should its settings be back by the time the job runs.
class Comvor::SamlProviderResetJob < ApplicationJob
  queue_as :low

  def perform(account_id)
    sso_members = AccountUser.where(account_id: Comvor::SamlSetting.select(:account_id)).select(:user_id)
    User.where(id: AccountUser.where(account_id: account_id).select(:user_id))
        .where.not(id: sso_members)
        .where.not(provider: 'email')
        .update_all(provider: 'email', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end
end
