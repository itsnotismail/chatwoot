module Enterprise::DeviseOverrides::SessionsController
  include SamlAuthenticationHelper

  def create
    return super unless saml_user_attempting_password_auth?(params[:email], sso_auth_token: params[:sso_auth_token])

    # Comvor Phase B, delegation OFF (COMVOR_PORTAL_API_URL blank): the
    # pre-Phase-B refusal, byte for byte, blank password included. That is the
    # dark-rollout guarantee.
    return render_saml_login_error unless portal_password_delegation_available?

    # Comvor Phase C: the second leg of a challenge carries an mfa_token and a
    # code, not a password. Some clients resend the email alongside it, which
    # would otherwise land on the blank-password refusal below and break the MFA
    # screen. Hand it to the OSS controller, which routes it to
    # handle_mfa_verification (overridden below). Placed AFTER the delegation
    # check so that with delegation off this file behaves byte for byte as it
    # did before — a saml user cannot hold an mfa_token in that world anyway.
    return super if mfa_verification_request?

    # Delegation ON with nothing to verify. Refuse here rather than asking the
    # portal to check an empty credential — and refuse it the generic way,
    # because otherwise simply OMITTING the password field would still tell an
    # anonymous caller that this email is a provisioned SAML agent.
    return render_portal_rejected_error if params[:password].blank?

    case portal_password_verifier.perform
    when :ok then sign_in_portal_verified_user
    when :totp_required then render_portal_mfa_challenge
    else render_portal_rejected_error
    end
  end

  def render_create_success
    create_audit_event('sign_in')
    super
  end

  def destroy
    create_audit_event('sign_out')
    super
  end

  def create_audit_event(action)
    return unless @resource

    associated_type = 'Account'
    @resource.accounts.each do |account|
      @resource.audits.create(
        action: action,
        user_id: @resource.id,
        associated_id: account.id,
        associated_type: associated_type
      )
    end
  end

  private

  # Comvor Phase C: answers the second factor for a PORTAL-flavoured challenge,
  # and only for that. Anything else — a Chatwoot-flavoured mfa_token, a forged
  # or expired one, or any token at all while delegation is off — falls through
  # to `super`, so Chatwoot's own MFA path is completely untouched.
  def handle_mfa_verification
    user = portal_mfa_challenge_user
    return super if user.nil?

    # The app's MFA screen sends the authenticator code as otp_code and a
    # recovery code as backup_code. The portal tries TOTP first and a recovery
    # code second and answers with one undifferentiated rejection, so both
    # fields collapse into a single value here.
    code = params[:otp_code].presence || params[:backup_code].presence
    return render_mfa_error('errors.mfa.invalid_code') if code.blank?

    verified = Internal::PortalTotpVerifier.new(
      email: user.email,
      code: code,
      # The END USER's address; see Internal::PortalTotpVerifier.
      client_ip: request.remote_ip
    ).perform

    # Deliberately the same key AND the same default status Chatwoot's own MFA
    # path renders for a bad code, so a portal-backed failure is
    # indistinguishable from a Chatwoot one. The verifier fails closed, so a
    # portal outage lands here too: a refusal, never a 500 and never a session.
    return render_mfa_error('errors.mfa.invalid_code') unless verified

    sign_in_portal_verified_user(user)
  end

  # The portal claim is the ONLY discriminator. Not user.provider: a
  # provider:'saml' agent can hold Chatwoot-side MFA as well, and Phase B routes
  # exactly those users to handle_mfa_required, so the provider cannot tell you
  # which kind of challenge was issued. Reading it wrong would send a
  # Chatwoot-MFA user's code to the portal, or a portal user's code to Chatwoot.
  #
  # nil (=> `super`) whenever delegation is off, so the OSS path is byte for
  # byte today's in that world.
  def portal_mfa_challenge_user
    return nil unless portal_password_delegation_available?

    Mfa::PortalTokenService.new(token: params[:mfa_token]).verify_token
  end

  # Comvor Phase C: the portal verified the password and wants a second factor.
  # Answer with a portal-flavoured challenge in exactly the shape
  # handle_mfa_required produces, because that is what the app's MFA screen
  # already consumes. No session token is issued here.
  def render_portal_mfa_challenge
    user = User.from_email(params[:email])
    # No challenge can be minted without a user to mint it for. Falling back to
    # the Phase B refusal keeps this fail-closed rather than 500ing.
    return render_portal_totp_error if user.nil?

    render json: {
      mfa_required: true,
      mfa_token: Mfa::PortalTokenService.new(user: user).generate_token
    }, status: :partial_content
  end

  def portal_password_verifier
    Internal::PortalPasswordVerifier.new(
      # Normalised exactly as User.from_email normalises, so the identity the
      # portal checks is the identity the guard above resolved.
      email: params[:email].to_s.downcase,
      password: params[:password],
      # The END USER's address. comvor-api rate-limits password attempts on this
      # header; sending the fork's own address would collapse every attempt on
      # the planet into a single bucket.
      client_ip: request.remote_ip
    )
  end

  # Signs the portal-verified agent in here, directly.
  #
  # It must NOT fall through to `super`. DeviseTokenAuth would then validate the
  # password against Chatwoot's OWN encrypted_password, which for a
  # provider:'saml' user is a random value assigned at provisioning time and
  # never shared with anyone — so a credential the portal has just confirmed
  # would still be rejected. This mirrors the OSS controller's
  # `sign_in_mfa_user`, which issues the session itself for the same reason.
  # Phase C passes the user explicitly: the second leg of the challenge carries
  # an mfa_token, and the identity comes from the token's claim rather than from
  # an email field the client need not resend.
  def sign_in_portal_verified_user(user = User.from_email(params[:email]))
    return render_saml_login_error if user.nil? || !user.active_for_authentication?

    # Delegation runs before `super`, so without this the OSS controller's
    # Chatwoot-side MFA check would be skipped entirely. Never issue a token on
    # this path.
    return handle_mfa_required(user) if user.mfa_enabled?

    @resource = user
    @token = @resource.create_token
    @resource.save!

    sign_in(:user, @resource, store: false, bypass: false)
    render_create_success
  end

  # There are deliberately two refusal messages, and which one you get depends on
  # whether delegation is on:
  #
  # - Delegation OFF (render_saml_login_error): a password can never work for
  #   this user, so "sign in through your SAML provider" is the correct advice,
  #   and keeping that exact payload is what makes the dark rollout provably
  #   inert.
  # - Delegation ON (here): the form they just used DOES work — the credential
  #   was simply wrong, absent, or unverifiable. A SAML-specific reply would be
  #   both bad advice and an enumeration oracle, telling an anonymous caller that
  #   this email is a provisioned SAML agent, which Devise's refusal for an
  #   unknown email does not.
  #
  # So call DeviseTokenAuth's own bad-credentials render rather than any copy of
  # it: a mistyped password for a SAML agent then stays byte-for-byte
  # indistinguishable from an unknown email or any other failed login, and stays
  # that way if upstream ever changes the wording or the shape.
  def render_portal_rejected_error
    render_create_error_bad_credentials
  end

  def render_saml_login_error
    render json: {
      success: false,
      message: I18n.t('messages.login_saml_user'),
      errors: [I18n.t('messages.login_saml_user')]
    }, status: :unauthorized
  end

  # Phase C moved the happy path off this message — a portal second factor is now
  # answered with a challenge, not a refusal. It stays as the fail-closed answer
  # for the case where delegation is on, the portal wants a second factor, and
  # the fork cannot mint a challenge to carry it. The portal reports
  # totp_required only AFTER the password has verified, so it is not an oracle.
  def render_portal_totp_error
    render json: {
      success: false,
      message: I18n.t('messages.login_portal_totp_user'),
      errors: [I18n.t('messages.login_portal_totp_user')]
    }, status: :unauthorized
  end
end
