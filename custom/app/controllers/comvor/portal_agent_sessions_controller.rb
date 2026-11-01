# frozen_string_literal: true

# POST /internal/portal/agent_session: comvor-api (the portal) asks for a
# one-time mobile sign-in link for a member of an account, creating the user
# the way SAML sign-in would for a first-time agent. Answers
# { deep_link: 'chatwootapp://auth/saml?...' }, a live credential that is
# never logged. Authenticated by PORTAL_FORK_SHARED_SECRET, not a user
# session, so it is outside the API's authenticate_user!.
#
# The answers are the ones the endpoint has always given, in this order:
# 404 while no secret is set (the endpoint is dark), 401 for a missing or
# wrong secret, 400 for a blank email, 404 for an account id that is not a
# plain positive number or names no account, 403 when SAML sign-in is off
# for the installation or the account (the deep link is no more capable than
# web SSO), 403 for an email that belongs to a user outside the account, 422
# when the user cannot be created.
class Comvor::PortalAgentSessionsController < ActionController::API
  SECRET_HEADER = 'X-Comvor-Portal-Secret'
  ACCOUNT_ID = /\A[1-9]\d{0,17}\z/

  before_action :require_portal_secret
  before_action :fetch_email
  before_action :fetch_account
  before_action :require_saml

  def create
    user = Comvor::SamlUserBuilder.new(email: @email, account_id: @account.id, name: name_param).perform
    response.headers['Cache-Control'] = 'no-store'
    render json: { deep_link: user.generate_mobile_sso_deep_link }
  rescue Comvor::SamlUserBuilder::AuthenticationFailed
    render json: { error: 'user not authorized for account' }, status: :forbidden
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    render json: { error: 'user could not be provisioned' }, status: :unprocessable_entity
  end

  private

  def require_portal_secret
    return render json: { error: 'not found' }, status: :not_found if Comvor::PortalFork.secret.blank?

    render json: { error: 'unauthorized' }, status: :unauthorized unless Comvor::PortalFork.secret_matches?(request.headers[SECRET_HEADER])
  end

  def fetch_email
    @email = params[:email].is_a?(String) ? params[:email].strip.downcase : ''
    render json: { error: 'email required' }, status: :bad_request if @email.blank?
  end

  # Only an integer or a string of digits is an id; anything else, such as a
  # JSON object or "1e3", names no account.
  def fetch_account
    id = params[:account_id]
    id = id.to_s if id.is_a?(Integer)
    @account = Account.find_by(id: id) if id.is_a?(String) && id.match?(ACCOUNT_ID)
    render json: { error: 'account not found' }, status: :not_found if @account.nil?
  end

  def require_saml
    return if Comvor::SamlSso.switched_on? && Comvor::SamlSso.configured_for?(@account)

    render json: { error: 'saml not enabled for account' }, status: :forbidden
  end

  def name_param
    params[:name].is_a?(String) ? params[:name].strip.presence : nil
  end
end
