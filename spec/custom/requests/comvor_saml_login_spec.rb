require 'rails_helper'

# The SSO page's form. The generic answers are the ones today's endpoint
# gives (recorded against it in E mode before this was built), so an
# outsider cannot tell an account or an email exists.
RSpec.describe 'POST /api/v1/auth/saml_login', type: :request do
  let(:frontend) { 'http://www.example.com' }
  let(:account) { create(:account) }
  let(:user) { create(:user, email: 'user@example.com') }
  let(:web_failure) { "#{frontend}/app/login/sso?error=saml-authentication-failed" }
  let(:mobile_failure) { 'chatwootapp://auth/saml?error=saml-authentication-failed' }

  around do |example|
    with_modified_env(COMVOR_PORTAL_API_URL: 'https://portal.example.test', FRONTEND_URL: frontend) { example.run }
  end

  before do
    account.enable_features!('saml')
    create(:account_user, user: user, account: account)
    Comvor::SamlSetting.new(account: account).save!(validate: false)
  end

  def saml_login(**params)
    post '/api/v1/auth/saml_login', params: params
  end

  def expect_generic_refusal(**params)
    saml_login(email: user.email, **params)
    expect(response).to have_http_status(:found)
    expect(response.location).to eq(params[:target] == 'mobile' ? mobile_failure : web_failure)
  end

  it 'is served by the Comvor controller, not the one config/routes.rb names' do
    saml_login(email: user.email)

    expect(controller).to be_a(Comvor::SamlLoginsController)
  end

  it 'sends a member to the comvor_saml strategy for the account, with 307 so the form token goes along' do
    saml_login(email: user.email)

    expect(response).to have_http_status(:temporary_redirect)
    expect(response.location).to eq("#{frontend}/auth/comvor_saml?account_id=#{account.id}&RelayState=web")
  end

  it 'names the mobile app as where the user goes back to' do
    saml_login(email: user.email.upcase, target: 'mobile')

    expect(response).to have_http_status(:temporary_redirect)
    expect(response.location).to eq("#{frontend}/auth/comvor_saml?account_id=#{account.id}&RelayState=mobile")
  end

  it 'chooses an account with SSO switched on among the user\'s accounts' do
    create(:account_user, user: user, account: create(:account))

    saml_login(email: user.email)

    expect(response.location).to include("account_id=#{account.id}&")
  end

  it 'answers bad request without an email' do
    saml_login(email: '')

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body).to eq('error' => 'Please enter a valid email address')
  end

  describe 'the same answer for everyone else' do
    it 'for an unknown email' do
      saml_login(email: 'nobody@example.com')
      expect(response).to have_http_status(:found)
      expect(response.location).to eq(web_failure)
    end

    it 'for an unknown email from the mobile app' do
      saml_login(email: 'nobody@example.com', target: 'mobile')
      expect(response.location).to eq(mobile_failure)
    end

    it 'for a user who is no member of an account with SSO' do
      AccountUser.where(user: user).destroy_all
      create(:account_user, user: user, account: create(:account))

      expect_generic_refusal
    end

    it 'for an account without the saml feature' do
      account.disable_features!('saml')

      expect_generic_refusal
      expect_generic_refusal(target: 'mobile')
    end

    it 'for an account without SAML settings' do
      Comvor::SamlSetting.where(account: account).delete_all

      expect_generic_refusal
    end

    it 'when SAML sign-in is switched off for the installation' do
      allow(GlobalConfigService).to receive(:load).and_call_original
      allow(GlobalConfigService).to receive(:load).with('ENABLE_SAML_SSO_LOGIN', 'true').and_return('false')

      expect_generic_refusal
    end

    it 'when the installation has no portal' do
      with_modified_env(COMVOR_PORTAL_API_URL: nil) { expect_generic_refusal }
    end
  end
end
