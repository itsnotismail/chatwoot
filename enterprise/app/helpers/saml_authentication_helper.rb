module SamlAuthenticationHelper
  def saml_user_attempting_password_auth?(email, sso_auth_token: nil)
    return false if email.blank?

    user = User.from_email(email)
    return false unless user&.provider == 'saml'

    return false if sso_auth_token.present? && user.valid_sso_auth_token?(sso_auth_token)

    true
  end

  # Comvor Phase B: the second carve-out from the refusal above. A
  # provider:'saml' agent MAY sign in with a password after all — as long as the
  # password is checked by the portal rather than against Chatwoot's own digest,
  # which for these users is a random value nobody holds.
  #
  # Deliberately a pure predicate, and deliberately narrow: it answers only
  # whether delegation is configured at all. Which refusal a rejected request
  # earns, and whether there is even a credential worth sending, are the
  # controller's decisions — and the verification call itself is I/O, so it lives
  # there too. That keeps this helper free of network access.
  def portal_password_delegation_available?
    Internal::PortalPasswordVerifier.enabled?
  end
end
