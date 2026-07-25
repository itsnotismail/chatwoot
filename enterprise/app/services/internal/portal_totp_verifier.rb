# Comvor Phase C: verifies a second factor against the Comvor portal
# (comvor-api) for an agent whose TOTP secret and recovery codes live there.
# Sibling of Internal::PortalPasswordVerifier and deliberately identical in
# shape. See comvor-api
# docs/superpowers/plans/2026-07-26-mobile-agent-access-phase-c.md.
#
# The portal decides what `code` is: it tries TOTP first and a recovery code
# second, and answers with one undifferentiated {ok: false} for every failure, so
# nothing here reveals which mechanism was attempted.
#
# The code is a live credential. It travels in the JSON body only — never in a
# URL, a query string or a log line — and the response body is never logged
# either. `otp_code` and `backup_code` are already in
# config/initializers/filter_parameter_logging.rb, which keeps the inbound
# request line clean too.
class Internal::PortalTotpVerifier
  VERIFY_PATH = '/portal/api/v1/internal/fork/verify-totp'.freeze
  # A slow portal must not hang the MFA form, so both timeouts are explicit and
  # short. HTTParty's defaults are effectively unbounded.
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 5

  # client_ip must be the END USER's address (request.remote_ip), not the fork's
  # own: comvor-api rate-limits code attempts on this forwarded header — tightly,
  # because a 6-digit code is a 10^6 space — and keying it on the fork's single
  # address would put every attempt on the planet in one bucket.
  def initialize(email:, code:, client_ip:)
    @email = email
    @code = code
    @client_ip = client_ip
  end

  # => true | false
  #
  # Fails closed. Any non-200, transport error, timeout, unparseable body or
  # anything other than a literal `true` is a rejection, so a portal outage
  # refuses the second factor rather than 500ing the form or — far worse —
  # signing anybody in.
  def perform
    response = post_verification
    return false unless response.code == 200

    JSON.parse(response.body.to_s)['ok'] == true
  rescue StandardError => e
    # Class only: the exception message can echo the request, and the body can
    # carry the code.
    Rails.logger.warn("[PORTAL_TOTP_VERIFIER] verification failed: #{e.class}")
    false
  end

  private

  def post_verification
    HTTParty.post(
      verify_url,
      body: { email: @email, code: @code }.to_json,
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
