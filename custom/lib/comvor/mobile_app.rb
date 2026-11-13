# frozen_string_literal: true

# Which mobile app a one-time SSO deep link opens, while both the official
# Chatwoot app (scheme chatwootapp://) and Comvor Agent (comvor://) are in
# use. The caller picks the app per request:
#
# - the portal's mint (POST /internal/portal/agent_session) sends app: 'comvor'
#   or 'chatwoot';
# - the SSO page (/app/login/sso?target=...) sends target 'mobile' or
#   'mobile_comvor', which rides through SAML as the RelayState.
#
# No app named means today's behaviour: the MOBILE_DEEP_LINK_BASE scheme,
# chatwootapp unless configured. The two named apps have fixed schemes, so
# a later switch of MOBILE_DEEP_LINK_BASE never strands either app.
module Comvor::MobileApp
  SCHEMES = { 'chatwoot' => 'chatwootapp', 'comvor' => 'comvor' }.freeze
  # RelayState (and SSO page target) => app; nil is the default app.
  MOBILE_RELAY_STATES = { 'mobile' => nil, 'mobile_comvor' => 'comvor' }.freeze

  module_function

  def known?(app)
    app.nil? || SCHEMES.key?(app)
  end

  # nil is the default app; a name outside SCHEMES is a caller's bug, never
  # quietly the default app's link.
  def scheme(app = nil)
    return GlobalConfigService.load('MOBILE_DEEP_LINK_BASE', 'chatwootapp') if app.nil?

    SCHEMES.fetch(app) { raise ArgumentError, "unknown mobile app: #{app.inspect}" }
  end

  def mobile_relay_state?(relay_state)
    MOBILE_RELAY_STATES.key?(relay_state)
  end

  def app_for_relay_state(relay_state)
    MOBILE_RELAY_STATES[relay_state]
  end

  def failure_link(app, error)
    "#{scheme(app)}://auth/saml?error=#{error}"
  end
end
