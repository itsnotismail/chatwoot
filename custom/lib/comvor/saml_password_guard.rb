# frozen_string_literal: true

# A saml user's credentials live in the Comvor portal alone, so no path may
# give them a Chatwoot password: one would sign in around the portal's
# second factor. Shared by the controllers that refuse it.
module Comvor::SamlPasswordGuard
  module_function

  def saml?(user)
    user&.provider == 'saml'
  end

  def refusal
    I18n.t('messages.reset_password_saml_user')
  end
end
