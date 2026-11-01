# frozen_string_literal: true

# The challenge token for a second factor the PORTAL owes. It is Chatwoot's
# MFA token (same key, same expiry) plus the portal_totp claim, and that
# claim is the only thing telling the two apart: a code answering this
# token goes to the portal, and to nothing else.
class Comvor::PortalTokenService < Mfa::TokenService
  def verify_token
    decoded = decode_token
    return nil unless decoded[:portal_totp] == true

    User.find_by(id: decoded[:user_id])
  end

  private

  def build_payload
    super.merge(portal_totp: true)
  end
end
