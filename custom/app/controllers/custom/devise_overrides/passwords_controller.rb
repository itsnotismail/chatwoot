# frozen_string_literal: true

# Refuses both halves of the Devise password reset for a saml user: the
# request (no reset email is sent) and the completion (a reset token minted
# earlier cannot set a password either).
module Custom::DeviseOverrides::PasswordsController
  def create
    return comvor_refuse_saml_reset if Comvor::SamlPasswordGuard.saml?(User.from_email(params[:email].to_s.strip))

    super
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
