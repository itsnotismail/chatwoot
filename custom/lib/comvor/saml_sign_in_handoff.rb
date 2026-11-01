# frozen_string_literal: true

# Carries a validated portal sign-in across the 303 hop from the SAML
# callback to the sign-in request. The payload stays in Redis under a random
# nonce; the browser's session only holds the nonce. A claim reads and
# deletes the entry atomically, so a nonce signs in once, and only within
# TTL: replaying the session cookie set on the hop finds nothing.
#
# Without Redis there is no way to honour that, so both sides raise
# Unavailable and sign-in is refused.
module Comvor::SamlSignInHandoff
  KEY_PREFIX = 'comvor:saml:sign_in:'
  TTL = 2.minutes

  class Unavailable < StandardError; end

  module_function

  def store(payload)
    nonce = SecureRandom.urlsafe_base64(32)
    Redis::Alfred.set("#{KEY_PREFIX}#{nonce}", payload.to_json, ex: TTL.to_i)
    nonce
  rescue Redis::BaseError, ConnectionPool::Error, Timeout::Error => e
    raise Unavailable, e.class.name
  end

  # The payload stored under nonce, or nil when there is none (never stored,
  # already claimed, or expired). GET and DEL run in one MULTI, which
  # redis-namespace (Redis::Alfred) namespaces; it does not know GETDEL.
  def claim(nonce)
    return if nonce.blank?

    key = "#{KEY_PREFIX}#{nonce}"
    value, = $alfred.with do |conn| # rubocop:disable Style/GlobalVars
      conn.multi do |tx|
        tx.get(key)
        tx.del(key)
      end
    end
    value && JSON.parse(value)
  rescue Redis::BaseError, ConnectionPool::Error, Timeout::Error => e
    raise Unavailable, e.class.name
  end
end
