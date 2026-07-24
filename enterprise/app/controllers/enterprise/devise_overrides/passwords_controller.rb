module Enterprise::DeviseOverrides::PasswordsController
  include SamlAuthenticationHelper

  def create
    if saml_user_attempting_password_auth?(params[:email])
      render_saml_reset_forbidden
      return
    end

    super
  end

  # Comvor: the official mobile app completes resets against PUT /auth/password;
  # we cannot re-point its binary, so the decline lives server-side. Portal is
  # the only credential authority for provider='saml' users (their Chatwoot
  # password is random and unusable anyway).
  def update
    return render_saml_reset_forbidden if saml_user_for_reset_token?

    super
  end

  private

  def saml_user_for_reset_token?
    token = params[:reset_password_token]
    return false if token.blank?

    User.with_reset_password_token(token)&.provider == 'saml'
  end

  def render_saml_reset_forbidden
    render json: {
      success: false,
      message: I18n.t('messages.reset_password_saml_user'),
      errors: [I18n.t('messages.reset_password_saml_user')]
    }, status: :forbidden
  end
end
