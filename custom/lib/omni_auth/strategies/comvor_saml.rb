# frozen_string_literal: true

# SAML sign-in that trusts only the Comvor portal (Comvor::PortalIdp).
#
# The identity provider's address, entity id and certificate come from the
# portal, never from tenant data; an account's Comvor::SamlSetting row only
# switches SSO on for it. The service provider name and return address are
# computed from account_id, the same way comvor-api provisions them.
#
# Every callback also checks, beyond ruby-saml's own validation, that the
# audience, destination and issuer are exactly the expected values, and that
# the assertion was not seen before. The replay cache lives in Redis because
# the portal's POST arrives cross-site, without the session cookie.
#
# Required from custom/config/initializers/comvor_saml.rb and kept out of
# autoloading: middleware is built once, so it must not be reloadable.
class OmniAuth::Strategies::ComvorSaml < OmniAuth::Strategies::SAML
  # users.provider stays 'saml' for every SAML user, whichever strategy
  # signed them in; comvor_saml is only the route name.
  USER_PROVIDER = 'saml'
  ACCOUNT_ID_ENV = 'comvor_saml.account_id'
  SESSION_ACCOUNT_ID = 'comvor_saml_account_id'
  ALLOWED_CLOCK_DRIFT = 30.seconds
  SIGNATURE_ERROR = 'Invalid Signature on SAML Response'
  REPLAY_KEY_PREFIX = 'comvor:saml:assertion:'
  EMAIL_NAME_ID_FORMAT = 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress'

  class UnavailableError < StandardError
    def initialize(msg = 'saml_unavailable')
      super
    end
  end

  SETUP = lambda do |env|
    request = Rack::Request.new(env)
    strategy = env['omniauth.strategy']
    account_id = (request.params['account_id'].presence || request.session[SESSION_ACCOUNT_ID]).to_s
    raise UnavailableError unless account_id.match?(/\A[1-9]\d*\z/) && Comvor::SamlSso.available?
    # The request phase only sends the browser to the portal, so it answers
    # alike for every account and tells nobody which ones have SSO. Whether
    # this account may sign in is decided when the portal's answer comes back.
    raise UnavailableError unless strategy.on_request_path? || Comvor::SamlSso.enabled_for?(Account.find_by(id: account_id))

    request.session[SESSION_ACCOUNT_ID] = account_id if strategy.on_request_path?
    env[ACCOUNT_ID_ENV] = account_id.to_i
    strategy.options.merge!(
      idp_sso_service_url: Comvor::PortalIdp.sso_url,
      idp_entity_id: Comvor::PortalIdp.entity_id,
      idp_cert_multi: nil,
      sp_entity_id: Comvor::PortalIdp.sp_entity_id_for(account_id),
      assertion_consumer_service_url: "#{ENV.fetch('FRONTEND_URL', nil)}/omniauth/comvor_saml/callback?account_id=#{account_id}",
      name_identifier_format: EMAIL_NAME_ID_FORMAT,
      # web or mobile, echoed back by the portal: where the signed-in user goes.
      idp_sso_service_url_runtime_params: { RelayState: 'RelayState' },
      allowed_clock_drift: ALLOWED_CLOCK_DRIFT.to_i,
      security: OneLogin::RubySaml::Settings::DEFAULTS[:security].merge(strict_audience_validation: true, want_name_id: true)
    )
  end

  option :name, 'comvor_saml'
  option :setup, SETUP

  extra { { account_id: env[ACCOUNT_ID_ENV] } }

  def auth_hash
    super.tap { |hash| hash.provider = USER_PROVIDER }
  end

  # Every refusal lands on the app's OmniAuth failure route, which the
  # callbacks controller answers with the login page's SAML error, rather
  # than on the Devise sign-in page the installation's on_failure sends to.
  # The RelayState goes along, so the mobile app gets its answer.
  def fail!(message_key, exception = nil)
    env['omniauth.error'] = exception
    env['omniauth.error.type'] = message_key.to_sym
    env['omniauth.error.strategy'] = self
    log :error, "Authentication failure! #{message_key}: #{exception&.class}, #{exception&.message}"

    relay_state = request.params['RelayState']
    mobile = Comvor::MobileApp.mobile_relay_state?(relay_state) ? "&RelayState=#{relay_state}" : ''
    redirect("#{script_name}#{path_prefix}/failure?message=#{Rack::Utils.escape(message_key)}&strategy=#{name}#{mobile}")
  end

  private

  # Replaces omniauth-saml's version: the certificates come from the portal,
  # the checks below run before anything is trusted, and nothing is written
  # to the session (the cross-site POST has none to keep).
  def handle_response(raw_response, opts, settings)
    settings.idp_cert_multi = { signing: Comvor::PortalIdp.certificates }
    response = validated_response(raw_response, opts, settings)
    verify_exact_values!(response, settings)
    claim_assertion!(response)

    @name_id = response.name_id
    @session_index = response.sessionindex
    @attributes = response.attributes
    @response_object = response
    yield
  rescue Comvor::PortalIdp::MetadataError => e
    raise ValidationError, "portal metadata unreadable: #{e.message}"
  end

  def validated_response(raw_response, opts, settings)
    validate_response(raw_response, opts, settings)
  rescue OneLogin::RubySaml::ValidationError => e
    raise unless e.message == SIGNATURE_ERROR

    # The portal may have rotated its key inside the cache window.
    fresh = Comvor::PortalIdp.refetch_certificates
    raise if fresh.nil? || fresh == settings.idp_cert_multi[:signing]

    settings.idp_cert_multi = { signing: fresh }
    validate_response(raw_response, opts, settings)
  end

  def validate_response(raw_response, opts, settings)
    OneLogin::RubySaml::Response.new(raw_response, opts.merge(settings: settings)).tap do |response|
      response.soft = false
      response.is_valid?
    end
  end

  # ruby-saml lets a missing Destination through, matches the destination
  # and issuer ignoring the port, and accepts an audience list that merely
  # includes ours. The portal always sends exactly these values.
  def verify_exact_values!(response, settings)
    raise ValidationError, 'SAML response has no matching Destination' unless response.destination == settings.assertion_consumer_service_url
    raise ValidationError, 'SAML response issuer is not the Comvor portal' unless response.issuers == [settings.idp_entity_id]
    raise ValidationError, 'SAML assertion audience is not this account' unless response.audiences.uniq == [settings.sp_entity_id]
    # Users are matched by the NameID, so it has to be an email address.
    raise ValidationError, 'SAML NameID is not an email address' unless response.name_id_format == EMAIL_NAME_ID_FORMAT
  end

  # Records the assertion ID until the assertion can no longer be accepted,
  # and refuses one already recorded. Without Redis there is no way to tell,
  # so sign-in is refused.
  def claim_assertion!(response)
    raise ValidationError, 'SAML assertion has no ID' if response.assertion_id.blank?

    ttl = (replay_window_end(response) + ALLOWED_CLOCK_DRIFT - Time.current).ceil
    raise ValidationError, 'SAML assertion has expired' unless ttl.positive?

    claimed = Redis::Alfred.set("#{REPLAY_KEY_PREFIX}#{response.assertion_id}", 1, nx: true, ex: ttl)
    raise ValidationError, 'SAML assertion was already used' unless claimed
  rescue Redis::BaseError, ConnectionPool::Error, Timeout::Error => e
    raise ValidationError, "SAML replay cache unavailable: #{e.class}"
  end

  # The later of the signed assertion's NotOnOrAfter times. An assertion
  # whose Conditions has none could be replayed forever, so it is refused.
  def replay_window_end(response)
    raise ValidationError, 'SAML assertion has no NotOnOrAfter' if response.not_on_or_after.nil?

    confirmations = response.send(:xpath_from_signed_assertion, '/a:Subject/a:SubjectConfirmation/a:SubjectConfirmationData')
    times = [response.not_on_or_after] + confirmations.filter_map { |node| node.attributes['NotOnOrAfter'] }.map { |value| Time.zone.parse(value) }
    times.compact.max
  end

  # Every other path under /omniauth/comvor_saml is the app's, without the
  # setup: no SP metadata is served (comvor-api provisions the portal's side),
  # so it cannot tell which accounts have SSO, and sign-out goes through the
  # portal (Comvor::PortalIdp), not SAML single logout.
  def other_phase
    call_app!
  end
end
