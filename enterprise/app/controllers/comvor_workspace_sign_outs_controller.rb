# Comvor: ends this browser's workspace session when the person signs out of the Comvor portal.
#
# Logout used to work one way only. Signing out of the workspace sends SAML users through the portal's
# single-logout (DeviseOverrides::SessionsController#capture_saml_logout_url), but signing out of the portal
# left the workspace session in place. On a shared shop phone the next person signed in to the portal,
# tapped "Open your workspace", and landed in the previous person's inbox: seen live as an agent landing in
# the owner's administrator session (app review 2026-10-17, L13).
#
# The portal now finishes its own sign-out by sending the browser here. The session lives in the
# cw_d_session_info cookie on this host, which only this host can clear, so this endpoint revokes the
# token it names and expires the cookies, then returns to the portal. A GET that only ends a session, the
# same shape as the portal's own /portal/saml/logout. return_to must be on the portal's origin, taken from
# the accounts' SAML settings (the IdP is the portal), so this is never an open redirect.
class ComvorWorkspaceSignOutsController < ApplicationController
  SESSION_COOKIES = %w[cw_d_session_info auth_data user].freeze

  def show
    revoke_session_token
    SESSION_COOKIES.each { |name| response.delete_cookie(name, path: '/') }
    redirect_to(safe_return_to || '/app/login', allow_other_host: true)
  end

  private

  def revoke_session_token
    session_info = parsed_session_cookie
    user = User.find_by(uid: session_info['uid'].to_s)
    client = session_info['client']
    return unless user&.tokens&.key?(client)

    user.tokens.delete(client)
    user.save!(validate: false)
  end

  def parsed_session_cookie
    JSON.parse(cookies['cw_d_session_info'].presence || '{}')
  rescue JSON::ParserError
    {}
  end

  def safe_return_to
    target = URI.parse(params[:return_to].to_s)
    return unless %w[http https].include?(target.scheme) && target.host

    target.to_s if portal_origins.include?(origin_of(target))
  rescue URI::InvalidURIError
    nil
  end

  def portal_origins
    AccountSamlSettings.where.not(sso_url: [nil, '']).pluck(:sso_url).filter_map do |url|
      origin_of(URI.parse(url))
    rescue URI::InvalidURIError
      nil
    end
  end

  def origin_of(uri)
    return unless uri.scheme && uri.host

    "#{uri.scheme}://#{uri.host}:#{uri.port}"
  end
end
