# frozen_string_literal: true

# Sign-in and sign-out for users the Comvor portal manages (provider 'saml').
#
# Sign-in: a saml user's Chatwoot password is never a credential. With portal
# delegation on (Comvor::PortalFork), the password is checked by comvor-api
# instead; a second factor the portal owes is answered through the app's MFA
# screen with a portal-flavoured challenge (Comvor::PortalTokenService). That
# challenge is answered by the portal alone: it never goes on to super, where
# Chatwoot's own MFA check (the local factor) would accept a local code. With
# delegation off, saml users get the SAML login refusal. The one exception
# is a valid sso_auth_token, the portal's own sign-in hand-off.
#
# Rejections look exactly like an unknown email's, so the endpoint does not
# tell which emails belong to portal users.
#
# Sign-out: a saml user is handed the portal's single-logout URL, built from
# COMVOR_PORTAL_API_URL alone, so the portal session ends with the Chatwoot one.
module Custom::DeviseOverrides::SessionsController
  COMVOR_PORTAL_LOGOUT_PATH = '/portal/saml/logout'

  def create
    portal_challenge_user = comvor_portal_challenge_user
    return comvor_answer_portal_challenge(portal_challenge_user) if portal_challenge_user
    return super if params[:mfa_token].present? || sso_authentication_request?

    user = comvor_saml_user_signing_in
    return super if user.nil?
    return comvor_render_saml_login_error unless Comvor::PortalPasswordVerifier.enabled?

    comvor_sign_in_with_portal_password(user)
  end

  # destroy tears down @resource before it renders, so the URL is worked out
  # first.
  def destroy
    @comvor_saml_logout_url = comvor_saml_logout_url(@resource)
    super
  end

  def render_destroy_success
    return super if @comvor_saml_logout_url.blank?

    render json: { success: true, saml_logout_url: @comvor_saml_logout_url }, status: :ok
  end

  private

  # The user a portal challenge names, when the token carries the portal claim.
  def comvor_portal_challenge_user
    return nil if params[:mfa_token].blank?

    Comvor::PortalTokenService.new(token: params[:mfa_token]).verify_token
  end

  # Found the way sign-in finds the user (Devise strips and downcases the
  # email), so no spelling of the address gets past the check.
  def comvor_saml_user_signing_in
    email = params[:email].to_s.strip
    return nil if email.blank?

    user = User.from_email(email)
    user if comvor_saml?(user)
  end

  def comvor_saml?(user)
    user&.provider == 'saml'
  end

  def comvor_sign_in_with_portal_password(user)
    # Never asks the portal about an empty credential, and answers as for an
    # unknown email.
    return render_create_error_bad_credentials if params[:password].blank?

    verdict = Comvor::PortalPasswordVerifier.new(email: user.email, password: params[:password], client_ip: request.remote_ip).perform
    return render_create_error_bad_credentials if verdict == :rejected
    return comvor_render_saml_login_error unless user.active_for_authentication?
    return comvor_render_portal_challenge(user) if verdict == :totp_required
    return handle_mfa_required(user) if user.mfa_enabled?

    comvor_sign_in(user)
  end

  def comvor_render_portal_challenge(user)
    render json: { mfa_required: true, mfa_token: Comvor::PortalTokenService.new(user: user).generate_token }, status: :partial_content
  end

  def comvor_answer_portal_challenge(user)
    unless Comvor::PortalPasswordVerifier.enabled? && comvor_saml?(user) && user.active_for_authentication?
      return render_mfa_error('errors.mfa.invalid_token', :unauthorized)
    end

    code = params[:otp_code].presence || params[:backup_code].presence
    return render_mfa_error('errors.mfa.invalid_code') if code.blank?

    verified = Comvor::PortalTotpVerifier.new(email: user.email, code: code, client_ip: request.remote_ip).perform
    return render_mfa_error('errors.mfa.invalid_code') unless verified

    comvor_sign_in(user)
  end

  def comvor_sign_in(user)
    @resource = user
    @token = @resource.create_token
    @resource.save!
    sign_in(:user, @resource, store: false, bypass: false)
    render_create_success
  end

  def comvor_render_saml_login_error
    message = I18n.t('messages.login_saml_user')
    render json: { success: false, message: message, errors: [message] }, status: :unauthorized
  end

  def comvor_saml_logout_url(user)
    return nil unless comvor_saml?(user) && Comvor::PortalIdp.secure?

    "#{Comvor::PortalIdp.base_url}#{COMVOR_PORTAL_LOGOUT_PATH}"
  end
end
