# frozen_string_literal: true

# Comvor: rate limits for the portal's mint endpoint, POST
# /internal/portal/agent_session (see Comvor::AgentSessionThrottle). The
# blocks and lambdas run per request, so the constants resolve after boot.
Rack::Attack.throttle('portal_agent_session/account_email',
                      limit: ->(_req) { Comvor::AgentSessionThrottle::PER_KEY_LIMIT },
                      period: ->(_req) { Comvor::AgentSessionThrottle::PERIOD }) do |req|
  Comvor::AgentSessionThrottle.key(req)
end

Rack::Attack.throttle('portal_agent_session/global',
                      limit: ->(_req) { Comvor::AgentSessionThrottle::GLOBAL_LIMIT },
                      period: ->(_req) { Comvor::AgentSessionThrottle::PERIOD }) do |req|
  Comvor::AgentSessionThrottle.global_key(req)
end
