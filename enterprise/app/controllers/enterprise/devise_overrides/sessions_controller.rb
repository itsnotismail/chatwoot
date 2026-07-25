module Enterprise::DeviseOverrides::SessionsController
  include SamlAuthenticationHelper

  def create
    return super unless saml_user_attempting_password_auth?(params[:email], sso_auth_token: params[:sso_auth_token])

    # Comvor Phase B: with delegation off (COMVOR_PORTAL_API_URL blank) or no
    # password supplied, this is the pre-Phase-B refusal, unchanged.
    return render_saml_login_error unless portal_password_delegation_available?(params[:password])

    case portal_password_verifier.perform
    when :ok then sign_in_portal_verified_user
    when :totp_required then render_portal_totp_error
    else render_saml_login_error
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
  def sign_in_portal_verified_user
    user = User.from_email(params[:email])
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

  def render_saml_login_error
    render json: {
      success: false,
      message: I18n.t('messages.login_saml_user'),
      errors: [I18n.t('messages.login_saml_user')]
    }, status: :unauthorized
  end

  # The portal reports totp_required only AFTER the password has verified, so
  # this is not an oracle. Phase C is what makes these users work.
  def render_portal_totp_error
    render json: {
      success: false,
      message: I18n.t('messages.login_portal_totp_user'),
      errors: [I18n.t('messages.login_portal_totp_user')]
    }, status: :unauthorized
  end
end
