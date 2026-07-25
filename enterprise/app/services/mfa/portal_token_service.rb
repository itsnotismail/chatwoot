# Comvor Phase C: the MFA challenge token for an agent whose second factor lives
# in the Comvor portal (comvor-api) rather than in Chatwoot's own otp columns.
#
# Deliberately a separate token flavour from Mfa::TokenService rather than a flag
# read off the user. A provider:'saml' agent can ALSO hold Chatwoot-side MFA —
# Phase B routes exactly those users to `handle_mfa_required` — so
# `user.provider` cannot tell you which challenge was issued. The `portal_totp`
# claim can, and it is the only thing the controller branches on: a
# Chatwoot-flavoured token is never accepted here, and a portal one is never
# accepted by Mfa::TokenService's caller path.
#
# Same signing key, algorithm and 5-minute expiry as Mfa::TokenService, so the
# app cannot tell the two apart and needs no change.
class Mfa::PortalTokenService < BaseTokenService
  pattr_initialize [:user, :token]

  PORTAL_MFA_TOKEN_EXPIRY = 5.minutes

  def generate_token
    @payload = build_payload
    super
  end

  # Returns the User only for a token that actually carries the portal claim.
  # A Chatwoot-flavoured mfa_token decodes fine here — same key, same algorithm —
  # so the claim check is what stops one kind of challenge being answered by the
  # other backend.
  def verify_token
    decoded = decode_token
    return nil if decoded.blank?
    return nil unless decoded[:portal_totp]

    User.find(decoded[:user_id])
  rescue ActiveRecord::RecordNotFound
    nil
  end

  private

  def build_payload
    {
      user_id: user.id,
      exp: PORTAL_MFA_TOKEN_EXPIRY.from_now.to_i,
      portal_totp: true
    }
  end
end
