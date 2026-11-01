# frozen_string_literal: true

# The fork's calls INTO comvor-api's fork-facing routes
# (internal/portal/api/fork_verify_handler.go, fork_verify_totp_handler.go):
# a JSON POST that proves itself with the shared secret and forwards the end
# user's IP, the route's only usable rate-limit key. comvor-api mounts the
# routes only when PORTAL_FORK_SHARED_SECRET is set, so both halves must be.
#
# Every failure (transport, non-200, a body that is not JSON) is nil, so the
# callers fail closed. Nothing sent or received is ever logged.
module Comvor::PortalFork
  OPEN_TIMEOUT = 3
  READ_TIMEOUT = 5

  module_function

  # The same trust rule as SAML sign-in: the portal is configured and, in
  # production, reached over HTTPS.
  def enabled?
    Comvor::PortalIdp.secure? && secret.present?
  end

  # The parsed JSON body of a 200 answer, or nil.
  def post(path, body, client_ip:)
    uri = URI.parse("#{Comvor::PortalIdp.base_url}#{path}")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
      http.post(uri.request_uri, body.to_json, 'Content-Type' => 'application/json',
                                               'X-Comvor-Portal-Secret' => secret, 'X-Comvor-Client-IP' => client_ip.to_s)
    end
    return warn_failure(path, "status #{response.code}") unless response.is_a?(Net::HTTPOK)

    parsed = JSON.parse(response.body.to_s)
    parsed.is_a?(Hash) ? parsed : warn_failure(path, 'a body that is not an object')
  rescue JSON::ParserError
    warn_failure(path, 'a body that is not JSON')
  rescue SocketError, SystemCallError, Timeout::Error, IOError, Net::ProtocolError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
         URI::InvalidURIError, OpenSSL::SSL::SSLError, Zlib::Error => e
    warn_failure(path, e.class.name)
  end

  def secret
    ENV.fetch('PORTAL_FORK_SHARED_SECRET', '').to_s
  end

  def warn_failure(path, reason)
    Rails.logger.warn("Comvor portal #{path} failed closed: #{reason}")
    nil
  end
end
