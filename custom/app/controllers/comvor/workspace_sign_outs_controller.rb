# frozen_string_literal: true

# GET /comvor/sign_out: where the portal finishes its own sign-out (and
# where its "Open your workspace" links go first), so the workspace session
# ends too. Without it, signing out of the portal left the workspace signed
# in, and on a shared phone the next person landed in the previous person's
# inbox.
#
# The session lives in the browser's cw_d_session_info cookie (the token
# headers the SPA keeps) and in the user's tokens, which is where
# devise_token_auth keeps them; its own sign-out revokes the token and resets
# the session, and so does this. The token is revoked only when the cookie
# proves it, so a made-up cookie cannot sign anyone out.
#
# return_to is where the browser goes afterwards: a path on this host, or an
# address on one of the portal's origins (Comvor::PortalOrigins.allowed),
# matched exactly. Anything else goes to the sign-in page.
class Comvor::WorkspaceSignOutsController < ApplicationController
  SESSION_COOKIES = %w[cw_d_session_info auth_data user].freeze
  FALLBACK = '/app/login'
  MAX_RETURN_TO = 2048
  # A path on this host: one slash, not two or a backslash (a browser reads
  # both as another host), no encoded slash or backslash, no whitespace or
  # control character.
  LOCAL_PATH = %r{\A/(?![/\\])[^\\[:space:][:cntrl:]]*\z}
  ENCODED_SLASH = /%(?:2f|5c)/i

  def show
    revoke_token
    end_session
    response.headers['Cache-Control'] = 'no-store'
    redirect_to return_target, allow_other_host: true
  end

  private

  def revoke_token
    info = session_info
    user = User.find_by(uid: info['uid'].to_s) if info
    client = info && info['client'].to_s
    return unless user && client.present? && user.valid_token?(info['access-token'].to_s, client)

    user.tokens.delete(client)
    user.save!
  end

  def session_info
    parsed = JSON.parse(cookies['cw_d_session_info'].to_s)
    parsed if parsed.is_a?(Hash)
  rescue JSON::ParserError
    nil
  end

  def end_session
    reset_session
    # Expired outright: a cookie the request did not carry still gets cleared.
    SESSION_COOKIES.each { |name| response.delete_cookie(name, path: '/') }
    cookies.delete(DeviseTokenAuth.cookie_name, domain: DeviseTokenAuth.cookie_attributes[:domain]) if DeviseTokenAuth.cookie_enabled
  end

  def return_target
    target = params[:return_to]
    return FALLBACK unless target.is_a?(String) && target.length <= MAX_RETURN_TO

    local_path?(target) ? target : portal_address(target) || FALLBACK
  end

  def local_path?(target)
    target.match?(LOCAL_PATH) && !target.match?(ENCODED_SLASH)
  end

  # The address when its origin is one of the portal's, exactly. The
  # authority is checked for what hides a second host in it: userinfo (@),
  # encoding (%), a backslash or whitespace.
  def portal_address(target)
    authority = target.sub(%r{\A[a-z][a-z0-9+.-]*://}i, '').split(%r{[/?#]}, 2).first.to_s
    return nil if authority.match?(/[@%\\[:space:][:cntrl:]]/) || target.match?(/[\\[:space:][:cntrl:]]/)

    origin = Comvor::PortalOrigins.of(target)
    return nil unless origin && Comvor::PortalOrigins.allowed.include?(origin)

    URI.parse(target).tap { |uri| uri.scheme = uri.scheme.downcase }.tap { |uri| uri.host = uri.host.downcase }.to_s
  rescue URI::InvalidURIError
    nil
  end
end
