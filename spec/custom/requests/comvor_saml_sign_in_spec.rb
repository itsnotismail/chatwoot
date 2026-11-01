require 'rails_helper'
require_relative '../support/comvor_saml_helpers'

# The whole portal sign-in, through the real middleware and controllers: the
# portal's POST to the return address, the 303 hop, and the sign-in.
RSpec.describe 'Comvor portal SAML sign-in', type: :request do
  let(:portal) { ComvorSamlHelpers::PORTAL }
  let(:frontend) { ComvorSamlHelpers::FRONTEND }
  let(:account) { create(:account) }
  let(:portal_keys) { ComvorSamlHelpers.key_and_certificate }
  let(:refused_on_web) { "#{frontend}/app/login?error=saml-authentication-failed" }

  around do |example|
    test_mode = OmniAuth.config.test_mode
    OmniAuth.config.test_mode = false
    with_modified_env(COMVOR_PORTAL_API_URL: portal, FRONTEND_URL: frontend) { example.run }
  ensure
    OmniAuth.config.test_mode = test_mode
  end

  before do
    # The app's own host: the sign-in redirects to FRONTEND_URL.
    host! URI.parse(frontend).host
    https!
    stub_request(:get, "#{portal}/portal/saml/metadata").to_return(status: 200, body: ComvorSamlHelpers.metadata_xml(portal_keys.last))
    enable_sso(account)
  end

  def enable_sso(for_account)
    for_account.enable_features!('saml')
    Comvor::SamlSetting.new(account: for_account).save!(validate: false)
  end

  def portal_post(email: 'agent@example.com', relay_state: 'web', for_account: account)
    saml_response = ComvorSamlHelpers.saml_response(key: portal_keys.first, cert: portal_keys.last, account_id: for_account.id, email: email)
    post "/omniauth/comvor_saml/callback?account_id=#{for_account.id}", params: { SAMLResponse: saml_response, RelayState: relay_state }
  end

  def sign_in_through_portal(**args)
    portal_post(**args)
    expect(response).to have_http_status(:see_other)
    expect(response.location).to eq("#{frontend}/auth/comvor_saml/callback")
    follow_redirect!
  end

  def signed_in_as?(user)
    query = Rack::Utils.parse_query(URI.parse(response.location).query)
    # The email is encoded twice, as the community callback always has.
    response.location.start_with?("#{frontend}/app/login?") && CGI.unescape(query['email']) == user.email &&
      user.valid_sso_auth_token?(query['sso_auth_token'])
  end

  describe 'an existing member' do
    let!(:member) { create(:user, email: 'agent@example.com', account: account, provider: 'email') }

    it 'is signed in on the web and becomes a SAML user' do
      sign_in_through_portal

      expect(signed_in_as?(member)).to be(true)
      expect(member.reload.provider).to eq('saml')
    end

    it 'is handed over to the mobile app with a one-time token in the deep link' do
      sign_in_through_portal(relay_state: 'mobile')

      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to eq('no-store')
      deep_link = response.body[%r{chatwootapp://auth/saml\?[^"]+}]
      token = Rack::Utils.parse_query(URI.parse(CGI.unescapeHTML(deep_link)).query)['sso_auth_token']
      expect(member.valid_sso_auth_token?(token)).to be(true)
    end

    it 'shows the hand-off page from custom/, with its own strings and the deep link as the button' do
      sign_in_through_portal(relay_state: 'mobile')

      page = Nokogiri::HTML(response.body)
      expect(page.at('h1').text).to eq("You're signed in")
      expect(page.at('a.cta').text).to eq('Open the app')
      expect(page.at('a.cta')['href']).to start_with('chatwootapp://auth/saml?')
      expect(response.body).not_to include('translation missing')
    end
  end

  describe 'an unknown email' do
    it 'becomes a confirmed SAML agent of the account and is signed in' do
      sign_in_through_portal(email: 'new.agent@example.com')

      user = User.from_email('new.agent@example.com')
      expect(signed_in_as?(user)).to be(true)
      expect(user).to have_attributes(provider: 'saml', confirmed?: true)
      expect(AccountUser.find_by(user: user, account: account).role).to eq('agent')
    end
  end

  describe 'an existing user who is no member of the account' do
    let!(:outsider) { create(:user, email: 'agent@example.com', account: create(:account), provider: 'email') }

    it 'is refused, and neither joins the account nor becomes a SAML user' do
      sign_in_through_portal

      expect(response.location).to eq(refused_on_web)
      expect(outsider.reload.provider).to eq('email')
      expect(outsider.accounts).not_to include(account)
    end

    it 'is sent back to the mobile app refused' do
      sign_in_through_portal(relay_state: 'mobile')

      expect(response.location).to eq('chatwootapp://auth/saml?error=saml-authentication-failed')
    end
  end

  describe 'the account an assertion was validated for' do
    let(:other_account) { create(:account).tap { |other| enable_sso(other) } }

    it 'is the one a new user joins, whatever the follow-up request names' do
      portal_post(email: 'new.agent@example.com')
      get "/auth/comvor_saml/callback?account_id=#{other_account.id}"

      user = User.from_email('new.agent@example.com')
      expect(user.accounts).to eq([account])
    end

    it 'is the one whose SSO is checked again at sign-in, whatever the follow-up request names' do
      portal_post(email: 'new.agent@example.com')
      account.disable_features!('saml')
      get "/auth/comvor_saml/callback?account_id=#{other_account.id}"

      expect(response.location).to eq(refused_on_web)
      expect(User.from_email('new.agent@example.com')).to be_nil
    end

    it 'is the one membership is checked against, whatever the follow-up request names' do
      outsider = create(:user, email: 'agent@example.com', account: other_account)

      portal_post
      get "/auth/comvor_saml/callback?account_id=#{other_account.id}"

      expect(response.location).to eq(refused_on_web)
      expect(outsider.reload.accounts).to eq([other_account])
    end
  end

  it 'refuses the follow-up request on its own' do
    get '/auth/comvor_saml/callback'

    expect(response.location).to eq(refused_on_web)
  end

  describe 'switched off after the user left for the portal' do
    def expect_refused_at_callback
      portal_post(email: 'new.agent@example.com')

      expect(response.location).to eq('/omniauth/failure?message=saml_unavailable&strategy=comvor_saml')
      follow_redirect!
      expect(response.location).to eq(refused_on_web)
      expect(User.from_email('new.agent@example.com')).to be_nil
    end

    it 'for the installation' do
      allow(GlobalConfigService).to receive(:load).and_call_original
      allow(GlobalConfigService).to receive(:load).with('ENABLE_SAML_SSO_LOGIN', 'true').and_return('false')

      expect_refused_at_callback
    end

    it 'for the account' do
      account.disable_features!('saml')

      expect_refused_at_callback
    end
  end

  describe 'the hand-off across the 303 hop' do
    let!(:member) { create(:user, email: 'agent@example.com', account: account) }
    let(:handoff_key) { "#{Comvor::SamlSignInHandoff::KEY_PREFIX}fixed-nonce" }

    before do
      allow(SecureRandom).to receive(:urlsafe_base64).and_call_original
      allow(SecureRandom).to receive(:urlsafe_base64).with(32).and_return('fixed-nonce')
    end

    it 'signs in once: replaying the session cookie set on the hop is refused' do
      portal_post
      hop_cookie = cookies['_chatwoot_session']
      follow_redirect!
      expect(signed_in_as?(member)).to be(true)

      cookies['_chatwoot_session'] = hop_cookie
      get '/auth/comvor_saml/callback'

      expect(response.location).to eq(refused_on_web)
    end

    it 'keeps only a nonce in the session' do
      portal_post

      expect(session['comvor_saml.sign_in']).to eq('fixed-nonce')
    end

    it 'lasts two minutes, and is refused once it has expired' do
      allow(Redis::Alfred).to receive(:set).and_call_original

      portal_post
      expect(Redis::Alfred).to have_received(:set).with(handoff_key, anything, ex: 120)
      Redis::Alfred.delete(handoff_key)
      follow_redirect!

      expect(response.location).to eq(refused_on_web)
    end

    it 'is refused when SSO is switched off for the account between the hop and the sign-in' do
      portal_post(email: 'new.agent@example.com')
      account.disable_features!('saml')
      follow_redirect!

      expect(response.location).to eq(refused_on_web)
      expect(User.from_email('new.agent@example.com')).to be_nil
    end

    it 'is refused when SAML sign-in is switched off for the installation between the hop and the sign-in' do
      portal_post
      allow(GlobalConfigService).to receive(:load).and_call_original
      allow(GlobalConfigService).to receive(:load).with('ENABLE_SAML_SSO_LOGIN', 'true').and_return('false')
      follow_redirect!

      expect(response.location).to eq(refused_on_web)
    end

    it 'is refused when Redis cannot keep it' do
      allow(Redis::Alfred).to receive(:set).and_call_original
      allow(Redis::Alfred).to receive(:set).with(handoff_key, anything, ex: 120).and_raise(Redis::CannotConnectError)

      portal_post

      expect(response.location).to eq(refused_on_web)
      expect(session['comvor_saml.sign_in']).to be_nil
    end

    it 'is refused when Redis cannot be read at sign-in' do
      portal_post
      allow($alfred).to receive(:with).and_raise(Redis::CannotConnectError) # rubocop:disable Style/GlobalVars
      follow_redirect!

      expect(response.location).to eq(refused_on_web)
    end
  end

  it 'refuses, rather than failing, when the user cannot be saved' do
    allow(User).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

    sign_in_through_portal(email: 'new.agent@example.com')

    expect(response.location).to eq(refused_on_web)
  end

  describe 'the request phase' do
    def portal_redirect_for(for_account)
      post "/auth/comvor_saml?account_id=#{for_account.id}&RelayState=mobile"
      expect(response).to have_http_status(:temporary_redirect)
      follow_redirect!
      expect(response).to have_http_status(:found)
      URI.parse(response.location)
    end

    it 'sends the browser to the portal, passing the RelayState on' do
      location = portal_redirect_for(account)

      expect("#{location.scheme}://#{location.host}#{location.path}").to eq("#{portal}/portal/saml/sso")
      expect(Rack::Utils.parse_query(location.query)['RelayState']).to eq('mobile')
    end

    it 'answers alike for an account without SSO, so it tells nobody which accounts have it' do
      with_sso = portal_redirect_for(account)
      without_sso = portal_redirect_for(create(:account))

      expect([without_sso.host, without_sso.path]).to eq([with_sso.host, with_sso.path])
      expect(Rack::Utils.parse_query(without_sso.query).keys).to eq(Rack::Utils.parse_query(with_sso.query).keys)
    end
  end

  it 'serves no SP metadata, for an account with SSO or without' do
    [account, create(:account)].each do |for_account|
      get "/omniauth/comvor_saml/metadata?account_id=#{for_account.id}"
      expect(response).to have_http_status(:not_found)
    end
  end
end
