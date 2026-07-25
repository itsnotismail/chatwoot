# Comvor Phase B: delegates the password check for a `provider:'saml'` agent to
# the Comvor portal (comvor-api), so an agent can sign in to the official
# Chatwoot mobile app with their portal credentials instead of being refused
# outright. See comvor-api
# docs/superpowers/plans/2026-07-26-mobile-agent-access-phase-b.md.
#
# Lives under enterprise/ because the SAML guard it serves is enterprise-only.
#
# This request carries a live credential. The password travels in the JSON body
# only — never in a URL, a query string or a log line — and the field stays named
# `password` so config/initializers/filter_parameter_logging.rb keeps filtering
# it. The response body is never logged either.
class Internal::PortalPasswordVerifier
  VERIFY_PATH = '/portal/api/v1/internal/fork/verify-password'.freeze
  # A slow portal must not hang the login form, so both timeouts are explicit
  # and short. HTTParty's defaults are effectively unbounded.
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 5

  # Blank COMVOR_PORTAL_API_URL is the off switch: with it unset, the guard
  # behaves byte for byte as it did before Phase B. That is what lets this ship
  # dark and roll back by unsetting one non-secret variable.
  def self.enabled?
    ENV['COMVOR_PORTAL_API_URL'].present? && ENV['PORTAL_FORK_SHARED_SECRET'].present?
  end

  # client_ip must be the END USER's address (request.remote_ip), not the fork's
  # own: comvor-api rate-limits password attempts on this forwarded header, and
  # keying it on the fork's single address would put every attempt on the planet
  # in one bucket.
  def initialize(email:, password:, client_ip:)
    @email = email
    @password = password
    @client_ip = client_ip
  end

  # => :ok | :totp_required | :rejected
  #
  # Fails closed. Any non-200, transport error, timeout or unparseable body is
  # :rejected, so a portal outage refuses the login rather than 500ing the form
  # or — far worse — signing anybody in.
  def perform
    response = post_verification
    return :rejected unless response.code == 200

    body = JSON.parse(response.body.to_s)
    return :rejected unless body['ok']

    body['totp_required'] ? :totp_required : :ok
  rescue StandardError => e
    # Class only: the exception message can echo the request, and the body can
    # carry the credential.
    Rails.logger.warn("[PORTAL_PASSWORD_VERIFIER] verification failed: #{e.class}")
    :rejected
  end

  private

  def post_verification
    HTTParty.post(
      verify_url,
      body: { email: @email, password: @password }.to_json,
      headers: {
        'X-Comvor-Portal-Secret' => ENV.fetch('PORTAL_FORK_SHARED_SECRET', ''),
        'X-Comvor-Client-IP' => @client_ip.to_s,
        'Content-Type' => 'application/json'
      },
      open_timeout: OPEN_TIMEOUT,
      read_timeout: READ_TIMEOUT
    )
  end

  def verify_url
    "#{ENV.fetch('COMVOR_PORTAL_API_URL', '').to_s.chomp('/')}#{VERIFY_PATH}"
  end
end
