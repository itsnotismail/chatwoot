# frozen_string_literal: true

module Custom::Concerns::User
  extend ActiveSupport::Concern

  # The one place the mobile deep link is constructed. Both the SSO callback's
  # mobile hand-off and the portal's internal mint endpoint use this, so the
  # two can never drift.
  #
  # NOTE the email is double-encoded: url_encode escapes it, then to_query
  # escapes that. This is the exact shape verified end-to-end on a real Android
  # device (2026-07-25) — the app decodes twice. Changing it requires
  # re-verifying on a physical device.
  def generate_mobile_sso_deep_link
    encoded_email = ERB::Util.url_encode(email)
    params = { email: encoded_email, sso_auth_token: generate_sso_auth_token }.to_query
    mobile_deep_link_base = GlobalConfigService.load('MOBILE_DEEP_LINK_BASE', 'chatwootapp')

    "#{mobile_deep_link_base}://auth/saml?#{params}"
  end
end
