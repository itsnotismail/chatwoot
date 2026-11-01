# frozen_string_literal: true

# Refuses both halves of the Devise password reset for a saml user.
#
# The request answers exactly as for any other email, so it does not tell
# who signs in through the portal. No Chatwoot reset token is made; the
# user gets a pointer to the portal's own reset page instead (none when the
# portal is not configured). The completion refuses a reset token minted
# earlier, so it cannot set a password either.
module Custom::DeviseOverrides::PasswordsController
  def create
    user = User.from_email(params[:email].to_s.strip)
    return super unless Comvor::SamlPasswordGuard.saml?(user)

    reset_url = Comvor::PortalIdp.password_reset_url
    Comvor::SamlPasswordPointerMailer.pointer(user, reset_url).deliver_later if reset_url
    build_response(I18n.t('messages.reset_password'), 200)
  end

  def update
    return comvor_refuse_saml_reset if Comvor::SamlPasswordGuard.saml?(comvor_reset_token_user)

    super
  end

  private

  def comvor_reset_token_user
    return nil if params[:reset_password_token].blank?

    User.find_by(reset_password_token: Devise.token_generator.digest(User, :reset_password_token, params[:reset_password_token]))
  end

  def comvor_refuse_saml_reset
    message = Comvor::SamlPasswordGuard.refusal
    render json: { success: false, message: message, errors: [message] }, status: :forbidden
  end
end
