# Comvor: mints a one-time mobile SSO deep link for (account_id, email) on
# behalf of the portal, so the portal's /workspace page can offer a direct
# `chatwootapp://` href that signs the agent straight into the official mobile
# app. See comvor-api docs/superpowers/specs/2026-07-25-mobile-agent-access-phase-a-design.md.
#
# Lives under enterprise/ because SamlUserBuilder is enterprise-only.
#
# Inherits ApplicationController, NOT Api::BaseController: the latter forces
# authenticate_user!, and this endpoint authenticates a *service*, not a user.
# ApplicationController already skips verify_authenticity_token. (The OmniAuth
# request-phase CSRF check that defeats a cross-origin POST to
# /api/v1/auth/saml_login does not apply here — this endpoint never enters the
# OmniAuth request phase.)
class Internal::PortalAgentSessionsController < ApplicationController
  before_action :authenticate_portal!

  def create
    return render_error('email required', :bad_request) if email.blank?

    account = Account.find_by(id: params[:account_id])
    return render_error('account not found', :not_found) if account.nil?
    return render_error('saml not enabled for account', :forbidden) unless saml_usable?(account)

    user = SamlUserBuilder.new(auth_hash, account.id).perform
    return render_error('user could not be provisioned', :unprocessable_entity) unless user&.persisted?

    # The deep link is a live credential: never logged, never persisted here.
    render json: { deep_link: user.generate_mobile_sso_deep_link }, status: :ok
  rescue SamlUserBuilder::AuthenticationFailed
    # Raised when the email resolves to a user who is NOT a member of the
    # requested account. This is the guard that stops one tenant's portal from
    # minting a session for another tenant's user — do not swallow it.
    render_error('user not authorized for account', :forbidden)
  end

  private

  # Absent secret means the feature was never configured: report 404 so the
  # endpoint does not even advertise its existence. Mirrors how the portal's
  # SAML IdP unmounts when its signing cert env is absent.
  def authenticate_portal!
    secret = ENV.fetch('PORTAL_FORK_SHARED_SECRET', nil)
    return render_error('not found', :not_found) if secret.blank?

    presented = request.headers['X-Comvor-Portal-Secret'].to_s
    return if ActiveSupport::SecurityUtils.secure_compare(secret, presented)

    render_error('unauthorized', :unauthorized)
  end

  # Mirrors exactly the pair Api::V1::AuthController#find_account_with_saml
  # checks, so this deep link is precisely as capable as web SSO and no more.
  # Without the check, minting against a non-SAML account would create a
  # provider:'saml' user there and the reset lockdown would then also block that
  # user's password login — a lockout with no SSO path to recover.
  def saml_usable?(account)
    account.feature_enabled?('saml') && account.saml_enabled?
  end

  def email
    @email ||= params[:email].to_s.strip.downcase
  end

  # Mirrors what the portal IdP actually asserts (comvor-api
  # internal/portal/samlidp/samlidp.go: NameID = email, attributes `email` and
  # `name`), so a user minted here is byte-for-byte the user SSO would build.
  def auth_hash
    { 'uid' => email, 'info' => { 'email' => email, 'name' => params[:name].presence } }
  end

  def render_error(message, status)
    render json: { error: message }, status: status
  end
end
