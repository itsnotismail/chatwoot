# frozen_string_literal: true

# Offers SAML sign-in whatever the pricing plan, when this installation signs
# in through the Comvor portal (Comvor::SamlSso): the portal is the identity
# provider, and each account switches it on with its settings row.
module Custom::DashboardController
  private

  def allowed_login_methods
    methods = super
    methods << 'saml' if methods.exclude?('saml') && Comvor::SamlSso.available?
    methods
  end
end
