# Comvor: request headers that must never reach Sentry.
#
# `send_default_pii = true` below makes sentry-ruby attach the request's headers
# to every captured event, and Rails' `filter_parameters` does NOT cover headers
# — it redacts params only. So without this list, an unhandled exception on an
# authenticated endpoint ships that request's credentials to a third party.
#
# X-Comvor-Portal-Secret is the one that matters most: it authenticates
# comvor-api -> fork calls, and whoever holds it can mint a Chatwoot session for
# ANY email in ANY SAML-enabled account (see
# enterprise/app/controllers/internal/portal_agent_sessions_controller.rb). That
# is a blast radius closer to PLATFORM_API_TOKEN than to one user's
# api_access_token, and a single key serves both directions.
#
# Matched case-insensitively: sentry-ruby normalises Rack's HTTP_* env keys to
# canonical dash-case (HTTP_API_ACCESS_TOKEN -> "Api-Access-Token"), so matching
# the raw spelling alone would silently miss them. Verified by hand against
# Sentry::RequestInterface (sentry-ruby 5.19).
COMVOR_SENTRY_FILTERED_HEADERS = %w[
  x-comvor-portal-secret
  api-access-token
  authorization
].freeze

if ENV['SENTRY_DSN'].present?
  Sentry.init do |config|
    config.dsn = ENV['SENTRY_DSN']
    config.enabled_environments = %w[staging production]

    # To activate performance monitoring, set one of these options.
    # We recommend adjusting the value in production:
    config.traces_sample_rate = 0.1 if ENV['ENABLE_SENTRY_TRANSACTIONS']

    config.excluded_exceptions += ['Rack::Timeout::RequestTimeoutException', 'MutexApplicationJob::LockAcquisitionError']

    # to track post data in sentry
    config.send_default_pii = true unless ENV['DISABLE_SENTRY_PII']

    # Redact credentials before the event leaves the process.
    #
    # Cookies are redacted WHOLESALE rather than by name. sentry-ruby does not
    # leave them in the Cookie header — it parses them into a separate
    # `request.cookies` hash, which with send_default_pii is fully populated in
    # plaintext. Both session cookies that reach this app are hijackable:
    # cw_d_session_info (Chatwoot's own) and comvor_session (the PORTAL's,
    # scoped to .comvor.com and therefore sent to chat.comvor.com too). A
    # cookie value is essentially never the thing that explains a stack trace,
    # so blanket redaction costs nothing and needs no denylist to keep current.
    #
    # Rescued because a raising before_send drops the event entirely, and an
    # error-reporting hook must never be the reason an error goes unreported.
    config.before_send = lambda do |event, _hint|
      begin
        request = event.respond_to?(:request) ? event.request : nil

        headers = request&.headers
        headers&.each_key do |name|
          headers[name] = '[FILTERED]' if COMVOR_SENTRY_FILTERED_HEADERS.include?(name.to_s.downcase)
        end

        cookies = request.respond_to?(:cookies) ? request.cookies : nil
        cookies&.each_key { |name| cookies[name] = '[FILTERED]' }
      rescue StandardError => e
        Rails.logger.warn("[Sentry] credential scrub failed: #{e.class}")
      end
      event
    end
  end
end
