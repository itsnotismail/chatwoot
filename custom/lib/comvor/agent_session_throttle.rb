# frozen_string_literal: true

# Rate limits for POST /internal/portal/agent_session (registered with
# Rack::Attack in custom/config/initializers/comvor_rack_attack.rb). They
# run in middleware before the endpoint's own checks, on input a stranger
# controls, so nothing here may raise.
#
# Two limits, both per minute:
# - PER_KEY_LIMIT for one (account, email): the portal limits a user to 20 a
#   minute, so this is the backstop for anything that bypasses the portal. It
#   is keyed on the identity and never the IP: every real request comes from
#   the one comvor-api instance, so an IP key would lump all merchants into
#   one bucket (and the trusted-IP safelist skips every throttle for
#   loopback). It counts every request, so a caller without the secret can
#   also use up a key.
# - GLOBAL_LIMIT for the whole endpoint, whatever the identity: with the
#   secret, a caller could otherwise try any number of fresh (account, email)
#   pairs to find which are valid, or mint links for every account in turn.
#   300 a minute is 5 a second. One mint is one staff member opening the
#   portal's workspace page (it refreshes at most once a minute per tab),
#   so even a shift change of a few hundred staff in one minute stays under
#   it, while a leaked secret is held to 432,000 pairs a day. Only requests
#   that present the right secret count, so a stranger flooding the path
#   cannot lock the portal out of its own endpoint.
module Comvor::AgentSessionThrottle
  PATH = '/internal/portal/agent_session'
  SECRET_ENV_KEY = 'HTTP_X_COMVOR_PORTAL_SECRET'
  PER_KEY_LIMIT = 30
  GLOBAL_LIMIT = 300
  PERIOD = 1.minute
  UNKEYABLE = 'unkeyable'

  module_function

  # The routes answer this path with a trailing slash, doubled slashes and a
  # format (.json) too, so those count as the same endpoint.
  def agent_session?(req)
    req.post? && req.path.to_s.squeeze('/').chomp('/').sub(%r{\.[^/]*\z}, '') == PATH
  end

  # One bucket per account and email as the endpoint reads them. Anything that
  # cannot be keyed (a body that does not parse, no account, no email) shares
  # a single bucket instead of going unthrottled.
  def key(req)
    return unless agent_session?(req)

    params = ActionDispatch::Request.new(req.env).params
    account_id = params['account_id'].presence
    email = params['email'].to_s.downcase.gsub(/\s+/, '').presence
    account_id.present? && email.present? ? "#{account_id}:#{email}" : UNKEYABLE
  rescue StandardError
    # Bad JSON, invalid UTF-8 and a malformed query string each raise a
    # different error, and one escaping would turn a malformed POST into a 500
    # from inside the middleware.
    UNKEYABLE
  end

  # A single bucket for every request that presents the portal secret.
  def global_key(req)
    'all' if agent_session?(req) && Comvor::PortalFork.secret_matches?(req.get_header(SECRET_ENV_KEY))
  end
end
