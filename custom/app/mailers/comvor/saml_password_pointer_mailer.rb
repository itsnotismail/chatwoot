# frozen_string_literal: true

# Sent in place of a Chatwoot reset email to a user whose sign-in the
# Comvor portal manages: their password is reset at the portal.
class Comvor::SamlPasswordPointerMailer < ApplicationMailer
  def pointer(user, reset_url)
    @user = user
    @reset_url = reset_url
    mail(to: user.email, subject: I18n.t('comvor.saml_password_pointer.subject'))
  end
end
