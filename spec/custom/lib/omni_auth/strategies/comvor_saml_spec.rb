require 'rails_helper'
require_relative '../../../support/comvor_saml_helpers'

RSpec.describe OmniAuth::Strategies::ComvorSaml do
  include ComvorSamlHelpers

  let(:portal) { ComvorSamlHelpers::PORTAL }
  let(:metadata_url) { "#{portal}/portal/saml/metadata" }
  let(:account) { create(:account) }
  let(:portal_keys) { ComvorSamlHelpers.key_and_certificate }
  let(:key) { portal_keys.first }
  let(:cert) { portal_keys.last }
  let(:reached) { [] }
  let(:app) { ->(env) { reached << env and [200, {}, ['app']] } }

  around do |example|
    test_mode = OmniAuth.config.test_mode
    on_failure = OmniAuth.config.on_failure
    OmniAuth.config.test_mode = false
    # The app's failure endpoint needs a Rails session; here a refusal only
    # has to be visible in the env.
    OmniAuth.config.on_failure = ->(_env) { [302, { 'Location' => '/omniauth/failure' }, []] }
    with_modified_env(COMVOR_PORTAL_API_URL: portal, FRONTEND_URL: ComvorSamlHelpers::FRONTEND) { example.run }
  ensure
    OmniAuth.config.test_mode = test_mode
    OmniAuth.config.on_failure = on_failure
  end

  before do
    stub_request(:get, metadata_url).to_return(status: 200, body: ComvorSamlHelpers.metadata_xml(cert))
    Redis::Alfred.delete(Comvor::PortalIdp::REFETCH_LOCK_KEY)
    create_setting(account)
  end

  def create_setting(for_account)
    for_account.enable_features!('saml')
    # The row only switches SSO on; the strategy reads nothing else from it.
    Comvor::SamlSetting.new(account: for_account, sso_url: "#{portal}/portal/saml/sso", idp_entity_id: metadata_url,
                            sp_entity_id: "comvor-chatwoot-account-#{for_account.id}", certificate: cert.to_pem).save!(validate: false)
  end

  def strategy_call(path, params: {})
    env = Rack::MockRequest.env_for(path, method: 'POST', params: params)
    env['rack.session'] = {}
    status, headers, = described_class.new(app).call(env)
    [status, headers, env]
  end

  def callback_with_relay_state(relay_state)
    strategy_call("/omniauth/comvor_saml/callback?account_id=#{account.id}", params: { 'SAMLResponse' => signed, 'RelayState' => relay_state })
  end

  def callback(saml_response, account_id: account.id)
    strategy_call("/omniauth/comvor_saml/callback?account_id=#{account_id}", params: { 'SAMLResponse' => saml_response })
  end

  def signed(**overrides)
    ComvorSamlHelpers.saml_response(key: key, cert: cert, account_id: account.id, **overrides)
  end

  def expect_accepted(result)
    env = result.last
    expect(env['omniauth.error']).to be_nil, -> { "refused: #{env['omniauth.error']&.message}" }
    expect(reached.size).to eq(1)
    env['omniauth.auth']
  end

  def expect_refused(result, message = nil)
    env = result.last
    expect(reached).to be_empty
    expect(env['omniauth.error']).to be_present
    expect(env['omniauth.error'].message).to include(message) if message
    expect(env['omniauth.auth']).to be_nil
  end

  describe 'a response from the portal' do
    it 'reaches the app with the asserted email and the account' do
      auth = expect_accepted(callback(signed))

      expect(auth.uid).to eq('agent@example.com')
      expect(auth.extra.account_id).to eq(account.id)
    end

    it 'asserts provider saml, never comvor_saml' do
      expect(expect_accepted(callback(signed)).provider).to eq('saml')
    end

    it 'is accepted with only the assertion signed' do
      expect_accepted(callback(signed(sign_response: false)))
    end

    it 'is accepted with only the response signed' do
      expect_accepted(callback(signed(sign_assertion: false)))
    end
  end

  describe 'signature' do
    it 'refuses an unsigned response' do
      expect_refused(callback(signed(sign_assertion: false, sign_response: false)))
    end

    it 'refuses a response signed by a key the portal does not publish' do
      other_key, other_cert = ComvorSamlHelpers.key_and_certificate
      forged = ComvorSamlHelpers.saml_response(key: other_key, cert: other_cert, account_id: account.id)

      expect_refused(callback(forged))
    end

    it 'never reads the certificate from the settings row' do
      other_key, other_cert = ComvorSamlHelpers.key_and_certificate
      Comvor::SamlSetting.find_by(account_id: account.id).update_columns(certificate: other_cert.to_pem) # rubocop:disable Rails/SkipsModelValidations
      forged = ComvorSamlHelpers.saml_response(key: other_key, cert: other_cert, account_id: account.id)

      expect_refused(callback(forged))
    end

    it 'accepts a response signed by any certificate the metadata lists' do
      new_key, new_cert = ComvorSamlHelpers.key_and_certificate
      stub_request(:get, metadata_url).to_return(status: 200, body: ComvorSamlHelpers.metadata_xml(cert, new_cert))

      expect_accepted(callback(ComvorSamlHelpers.saml_response(key: new_key, cert: new_cert, account_id: account.id)))
      # Accepted on the first read, not rescued by the re-read after a failure.
      expect(a_request(:get, metadata_url)).to have_been_made.once
    end

    it 'refuses when the portal metadata cannot be read' do
      stub_request(:get, metadata_url).to_return(status: 503)

      expect_refused(callback(signed), 'portal metadata unreadable')
    end

    describe 'after the portal rotates its key inside the cache window' do
      let(:new_keys) { ComvorSamlHelpers.key_and_certificate }
      let(:rotated) { ComvorSamlHelpers.saml_response(key: new_keys.first, cert: new_keys.last, account_id: account.id) }

      before do
        allow(Comvor::PortalIdp).to receive(:certificates).and_return([cert.to_pem])
        stub_request(:get, metadata_url).to_return(status: 200, body: ComvorSamlHelpers.metadata_xml(new_keys.last))
      end

      it 're-reads the metadata once and accepts the new key' do
        expect_accepted(callback(rotated))
        expect(a_request(:get, metadata_url)).to have_been_made.once
      end

      it 're-reads it at most once per interval, however many bad signatures arrive' do
        other_key, other_cert = ComvorSamlHelpers.key_and_certificate
        3.times { expect_refused(callback(ComvorSamlHelpers.saml_response(key: other_key, cert: other_cert, account_id: account.id))) }

        expect(a_request(:get, metadata_url)).to have_been_made.once
      end
    end
  end

  describe 'audience' do
    it 'refuses an assertion for another account' do
      expect_refused(callback(signed(audiences: ['comvor-chatwoot-account-999999'])), 'audience')
    end

    it 'refuses an assertion that names no audience' do
      expect_refused(callback(signed(audiences: nil)))
    end

    it 'refuses an assertion that names another audience besides this account' do
      expect_refused(callback(signed(audiences: ["comvor-chatwoot-account-#{account.id}", 'https://other.example.com'])), 'audience')
    end

    it 'is the computed name, not what the settings row stores' do
      Comvor::SamlSetting.find_by(account_id: account.id).update_columns(sp_entity_id: 'stored-name') # rubocop:disable Rails/SkipsModelValidations

      expect_refused(callback(signed(audiences: ['stored-name'])))
      expect_accepted(callback(signed))
    end
  end

  describe 'return address' do
    it 'refuses a response addressed to another return address' do
      expect_refused(callback(signed(destination: ComvorSamlHelpers.acs_for(999_999))), 'was received at')
    end

    it 'refuses a response with no destination' do
      expect_refused(callback(signed(destination: nil)), 'Destination')
    end

    it 'refuses a response meant for the enterprise return address' do
      enterprise_acs = "#{ComvorSamlHelpers::FRONTEND}/omniauth/saml/callback?account_id=#{account.id}"

      expect_refused(callback(signed(destination: enterprise_acs, recipient: enterprise_acs)))
    end

    it 'refuses a response posted to another account than the one it was issued for' do
      other = create(:account)
      create_setting(other)

      expect_refused(callback(signed, account_id: other.id))
    end
  end

  describe 'issuer' do
    it 'refuses another issuer' do
      expect_refused(callback(signed(issuer: 'https://evil.example.com/metadata')))
    end

    it 'refuses the portal address on another port' do
      expect_refused(callback(signed(issuer: "#{portal}:8443/portal/saml/metadata")), 'issuer')
    end
  end

  describe 'time window' do
    it 'refuses an expired assertion' do
      response = signed(not_on_or_after: 2.minutes.from_now)

      travel 3.minutes do
        expect_refused(callback(response))
      end
    end

    it 'allows a little clock drift' do
      response = signed(not_on_or_after: 10.seconds.from_now, confirmation_not_on_or_after: 10.seconds.from_now)

      travel 20.seconds do
        expect_accepted(callback(response))
      end
    end

    it 'refuses an assertion that never expires' do
      expect_refused(callback(signed(not_on_or_after: nil, confirmation_not_on_or_after: nil)), 'NotOnOrAfter')
    end

    it 'refuses an assertion whose conditions never expire, even if its subject confirmation does' do
      expect_refused(callback(signed(not_on_or_after: nil, confirmation_not_on_or_after: 90.seconds.from_now)), 'NotOnOrAfter')
    end
  end

  describe 'NameID' do
    it 'refuses a NameID that is not an email address, since users are matched by it' do
      expect_refused(callback(signed(name_id_format: 'urn:oasis:names:tc:SAML:2.0:nameid-format:persistent')), 'NameID')
    end

    it 'refuses a NameID without a format' do
      expect_refused(callback(signed(name_id_format: nil)), 'NameID')
    end
  end

  describe 'replay' do
    it 'refuses the same assertion twice' do
      response = signed

      expect_accepted(callback(response))
      reached.clear
      expect_refused(callback(response), 'already used')
    end

    it 'remembers the assertion until its last NotOnOrAfter plus the drift' do
      allow(Redis::Alfred).to receive(:set).and_call_original
      assertion_id = "id-#{SecureRandom.hex(20)}"

      freeze_time do
        expect_accepted(callback(signed(assertion_id: assertion_id, not_on_or_after: 60.seconds.from_now,
                                        confirmation_not_on_or_after: 90.seconds.from_now)))
      end

      expect(Redis::Alfred).to have_received(:set)
        .with("#{described_class::REPLAY_KEY_PREFIX}#{assertion_id}", 1, nx: true, ex: 90 + described_class::ALLOWED_CLOCK_DRIFT.to_i)
    end

    it 'refuses sign-in when Redis is unreachable' do
      allow(Redis::Alfred).to receive(:set).and_raise(Redis::CannotConnectError)

      expect_refused(callback(signed), 'replay cache unavailable')
    end
  end

  describe 'setup' do
    it 'refuses an account without SAML settings' do
      expect_refused(callback(signed, account_id: create(:account).tap { |other| other.enable_features!('saml') }.id), 'saml_unavailable')
    end

    it 'refuses without an account id' do
      expect_refused(strategy_call('/omniauth/comvor_saml/callback', params: { 'SAMLResponse' => signed }), 'saml_unavailable')
    end

    it 'refuses an account without the saml feature' do
      account.disable_features!('saml')

      expect_refused(callback(signed), 'saml_unavailable')
    end

    it 'refuses when SAML sign-in is switched off for the installation' do
      allow(GlobalConfigService).to receive(:load).and_call_original
      allow(GlobalConfigService).to receive(:load).with('ENABLE_SAML_SSO_LOGIN', 'true').and_return('false')

      expect_refused(callback(signed), 'saml_unavailable')
      expect_refused(strategy_call("/omniauth/comvor_saml?account_id=#{account.id}"), 'saml_unavailable')
    end

    it 'sends a refusal to the failure page, with the mobile app named when the user came from it' do
      account.disable_features!('saml')

      status, headers, = callback_with_relay_state('mobile')

      expect(status).to eq(302)
      expect(headers['Location']).to eq('/omniauth/failure?message=saml_unavailable&strategy=comvor_saml&RelayState=mobile')
    end

    it 'refuses a portal reached over plain HTTP in production' do
      allow(Comvor::PortalIdp).to receive(:production?).and_return(true)

      with_modified_env(COMVOR_PORTAL_API_URL: 'http://portal.example.test') do
        expect_refused(callback(signed), 'saml_unavailable')
      end
    end
  end

  describe 'request phase' do
    def authn_request(location)
      query = Rack::Utils.parse_query(URI.parse(location).query)
      Nokogiri::XML(Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(Base64.decode64(query['SAMLRequest'])))
    end

    it 'sends the user to the portal naming this account and the comvor_saml return address' do
      status, headers, = strategy_call("/omniauth/comvor_saml?account_id=#{account.id}")

      expect(status).to eq(302)
      expect(headers['Location']).to start_with("#{portal}/portal/saml/sso?")
      request = authn_request(headers['Location'])
      expect(request.root['AssertionConsumerServiceURL']).to eq(ComvorSamlHelpers.acs_for(account.id))
      expect(request.at_xpath('//saml:Issuer', 'saml' => 'urn:oasis:names:tc:SAML:2.0:assertion').text)
        .to eq("comvor-chatwoot-account-#{account.id}")
    end

    it 'passes the RelayState on to the portal' do
      _, headers, = strategy_call("/omniauth/comvor_saml?account_id=#{account.id}&RelayState=mobile")

      expect(Rack::Utils.parse_query(URI.parse(headers['Location']).query)['RelayState']).to eq('mobile')
    end

    it 'answers alike for an account without the saml feature or settings' do
      other = create(:account)
      status, headers, env = strategy_call("/omniauth/comvor_saml?account_id=#{other.id}")

      expect(env['omniauth.error']).to be_nil
      expect(status).to eq(302)
      expect(headers['Location']).to start_with("#{portal}/portal/saml/sso?")
      expect(authn_request(headers['Location']).root['AssertionConsumerServiceURL']).to eq(ComvorSamlHelpers.acs_for(other.id))
    end
  end

  describe 'other paths' do
    it 'passes the SP metadata path on to the app, for an account with settings or without' do
      [account, create(:account)].each do |for_account|
        reached.clear
        _, _, env = strategy_call("/omniauth/comvor_saml/metadata?account_id=#{for_account.id}")

        expect(reached.size).to eq(1)
        expect(env['omniauth.error']).to be_nil
      end
    end
  end
end
