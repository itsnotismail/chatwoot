require 'rails_helper'
require_relative '../support/comvor_saml_helpers'

# Both mobile apps take the SSO hand-off during the move from the official
# Chatwoot app (chatwootapp://) to Comvor Agent (comvor://); each request
# picks one (Comvor::MobileApp). Naming no app is today's behaviour, which
# the other specs in this folder pin.
RSpec.describe 'Choosing the mobile app for the SSO hand-off', type: :request do
  let(:secret) { 'portal-fork-shared-secret-for-specs' }
  let(:account) { create(:account) }

  def enable_sso(for_account)
    for_account.enable_features!('saml')
    Comvor::SamlSetting.new(account: for_account).save!(validate: false)
  end

  describe 'POST /internal/portal/agent_session' do
    let(:member) { create(:user, email: 'member@example.com', account: account) }

    around do |example|
      with_modified_env(PORTAL_FORK_SHARED_SECRET: secret) { example.run }
    end

    before do
      enable_sso(account)
      member
    end

    def mint(params)
      post '/internal/portal/agent_session', params: params, headers: { 'X-Comvor-Portal-Secret' => secret }, as: :json
    end

    it 'gives a comvor:// link for app comvor, with the double-encoded email and a live token' do
      mint({ account_id: account.id, email: member.email, app: 'comvor' })

      expect(response).to have_http_status(:ok)
      link = response.parsed_body.fetch('deep_link')
      expect(link).to start_with('comvor://auth/saml?')
      expect(link).to include('email=member%2540example.com')
      token = Rack::Utils.parse_query(URI.parse(link).query)['sso_auth_token']
      expect(member.reload.valid_sso_auth_token?(token)).to be(true)
    end

    it 'gives a chatwootapp:// link for app chatwoot' do
      mint({ account_id: account.id, email: member.email, app: 'chatwoot' })

      expect(response.parsed_body.fetch('deep_link')).to start_with('chatwootapp://auth/saml?')
    end

    it 'refuses an app it does not know, before looking at the account' do
      mint({ account_id: account.id, email: member.email, app: 'evilapp' })

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to eq('error' => 'unknown app')
    end

    it 'refuses an app that is not a string' do
      mint({ account_id: account.id, email: member.email, app: { 'scheme' => 'x' } })

      expect(response).to have_http_status(:bad_request)
    end

    it 'still asks for the secret first' do
      post '/internal/portal/agent_session', params: { account_id: account.id, email: member.email, app: 'evilapp' }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/auth/saml_login with target mobile_comvor' do
    let(:frontend) { 'http://www.example.com' }
    let(:user) { create(:user, email: 'user@example.com') }

    around do |example|
      with_modified_env(COMVOR_PORTAL_API_URL: 'https://portal.example.test', FRONTEND_URL: frontend) { example.run }
    end

    before do
      enable_sso(account)
      create(:account_user, user: user, account: account)
    end

    it 'carries the target on as the RelayState' do
      post '/api/v1/auth/saml_login', params: { email: user.email, target: 'mobile_comvor' }

      expect(response).to have_http_status(:temporary_redirect)
      expect(response.location).to eq("#{frontend}/auth/comvor_saml?account_id=#{account.id}&RelayState=mobile_comvor")
    end

    it 'sends a refusal back to Comvor Agent' do
      post '/api/v1/auth/saml_login', params: { email: 'nobody@example.com', target: 'mobile_comvor' }

      expect(response.location).to eq('comvor://auth/saml?error=saml-authentication-failed')
    end

    it 'treats a target it does not know as the web, as before' do
      post '/api/v1/auth/saml_login', params: { email: user.email, target: 'mobile_evil' }

      expect(response.location).to end_with('RelayState=web')
    end
  end

  describe 'the portal sign-in callback with RelayState mobile_comvor' do
    let(:portal) { ComvorSamlHelpers::PORTAL }
    let(:frontend) { ComvorSamlHelpers::FRONTEND }
    let(:portal_keys) { ComvorSamlHelpers.key_and_certificate }

    around do |example|
      test_mode = OmniAuth.config.test_mode
      OmniAuth.config.test_mode = false
      with_modified_env(COMVOR_PORTAL_API_URL: portal, FRONTEND_URL: frontend) { example.run }
    ensure
      OmniAuth.config.test_mode = test_mode
    end

    before do
      host! URI.parse(frontend).host
      https!
      stub_request(:get, "#{portal}/portal/saml/metadata").to_return(status: 200, body: ComvorSamlHelpers.metadata_xml(portal_keys.last))
      enable_sso(account)
    end

    def portal_post(for_account: account, relay_state: 'mobile_comvor')
      saml_response = ComvorSamlHelpers.saml_response(key: portal_keys.first, cert: portal_keys.last, account_id: for_account.id,
                                                      email: 'agent@example.com')
      post "/omniauth/comvor_saml/callback?account_id=#{for_account.id}", params: { SAMLResponse: saml_response, RelayState: relay_state }
    end

    it 'hands a member over to Comvor Agent with a comvor:// link carrying a one-time token' do
      member = create(:user, email: 'agent@example.com', account: account, provider: 'email')

      portal_post
      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to eq('no-store')
      href = Nokogiri::HTML(response.body).at('a.cta')['href']
      expect(href).to start_with('comvor://auth/saml?')
      expect(href).to include('email=agent%2540example.com')
      expect(member.valid_sso_auth_token?(Rack::Utils.parse_query(URI.parse(href).query)['sso_auth_token'])).to be(true)
    end

    it 'sends a strategy failure (an assertion not signed by the portal) back to Comvor Agent' do
      forged_keys = ComvorSamlHelpers.key_and_certificate
      saml_response = ComvorSamlHelpers.saml_response(key: forged_keys.first, cert: forged_keys.last, account_id: account.id,
                                                      email: 'agent@example.com')
      post "/omniauth/comvor_saml/callback?account_id=#{account.id}", params: { SAMLResponse: saml_response, RelayState: 'mobile_comvor' }

      expect(response.location).to end_with('&strategy=comvor_saml&RelayState=mobile_comvor')
      follow_redirect!
      expect(response.location).to eq('comvor://auth/saml?error=saml-authentication-failed')
    end

    it 'sends a failure because SSO was switched off back to Comvor Agent' do
      allow(GlobalConfigService).to receive(:load).and_call_original
      allow(GlobalConfigService).to receive(:load).with('ENABLE_SAML_SSO_LOGIN', 'true').and_return('false')

      portal_post
      follow_redirect!

      expect(response.location).to eq('comvor://auth/saml?error=saml-authentication-failed')
    end

    it 'sends a refused user back to Comvor Agent' do
      create(:user, email: 'agent@example.com', account: create(:account), provider: 'email')

      portal_post
      follow_redirect!

      expect(response.location).to eq('comvor://auth/saml?error=saml-authentication-failed')
    end
  end
end
