require 'rails_helper'

RSpec.describe DeviseOverrides::SessionsController, type: :controller do
  include Devise::Test::ControllerHelpers

  let(:portal_env) do
    { COMVOR_PORTAL_API_URL: 'https://api.comvor.test', PORTAL_FORK_SHARED_SECRET: 'shhh' }
  end
  let(:verify_url) { 'https://api.comvor.test/portal/api/v1/internal/fork/verify-password' }
  # The Chatwoot-side password for a provider:'saml' user is random and stale.
  # Every delegated example signs in with a DIFFERENT password on purpose, so a
  # green result cannot have come from DeviseTokenAuth's own digest check.
  let(:saml_user) { create(:user, provider: 'saml', password: 'ChatwootSideOnly1!') }
  let(:portal_password) { 'PortalSide1!' }

  before do
    request.env['devise.mapping'] = Devise.mappings[:user]
  end

  def stub_verify(body, status: 200)
    stub_request(:post, verify_url).to_return(status: status, body: body.to_json)
  end

  def sign_in_with_portal_password(email: saml_user.email, password: portal_password)
    with_modified_env(portal_env) { post :create, params: { email: email, password: password } }
  end

  describe 'POST #create with portal password delegation' do
    context 'when the portal verifies the password' do
      before { stub_verify({ ok: true, totp_required: false }) }

      it 'signs the saml user in without falling through to devise token auth' do
        expect { sign_in_with_portal_password }.to change { saml_user.reload.tokens.count }.by(1)

        expect(response).to have_http_status(:success)
        expect(response.headers['access-token']).to be_present
        # The proof: the submitted password is not the user's Chatwoot password,
        # so `super` / DeviseTokenAuth could not have authenticated this.
        expect(saml_user.reload.valid_password?(portal_password)).to be(false)
      end

      it 'forwards the end user ip, not the fork address, to the portal' do
        request.env['REMOTE_ADDR'] = '203.0.113.9'

        sign_in_with_portal_password

        expect(a_request(:post, verify_url).with(headers: { 'X-Comvor-Client-IP' => '203.0.113.9' })).to have_been_made
      end

      it 'writes a sign_in audit event' do
        account = create(:account)
        create(:account_user, user: saml_user, account: account)

        expect { sign_in_with_portal_password }.to change { saml_user.audits.where(action: 'sign_in').count }.by(1)
      end

      it 'refuses an inactive user' do
        saml_user.update!(confirmed_at: nil)

        sign_in_with_portal_password

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body['message']).to eq(I18n.t('messages.login_saml_user'))
      end
    end

    context 'when the chatwoot user has mfa enabled' do
      before do
        stub_verify({ ok: true, totp_required: false })
        saml_user.update!(otp_required_for_login: true)
      end

      it 'demands the second factor instead of issuing a session' do
        sign_in_with_portal_password

        expect(response).to have_http_status(:partial_content)
        expect(response.parsed_body['mfa_required']).to be(true)
        expect(response.parsed_body['mfa_token']).to be_present
        expect(response.headers['access-token']).to be_nil
      end
    end

    context 'when the portal rejects the password' do
      it 'returns the existing saml refusal' do
        stub_verify({ ok: false, totp_required: false })

        sign_in_with_portal_password

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body['message']).to eq(I18n.t('messages.login_saml_user'))
        expect(response.headers['access-token']).to be_nil
      end
    end

    context 'when the portal reports a second factor' do
      it 'points the user at their comvor workspace' do
        stub_verify({ ok: true, totp_required: true })

        sign_in_with_portal_password

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body['message']).to eq(I18n.t('messages.login_portal_totp_user'))
        expect(response.headers['access-token']).to be_nil
      end
    end

    context 'when the portal is unreachable' do
      it 'fails closed with a 401 rather than a 500' do
        stub_request(:post, verify_url).to_timeout

        sign_in_with_portal_password

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body['message']).to eq(I18n.t('messages.login_saml_user'))
      end
    end

    context 'when delegation is disabled' do
      it 'reproduces the pre-phase-b refusal without calling the portal' do
        post :create, params: { email: saml_user.email, password: portal_password }

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body['message']).to eq(I18n.t('messages.login_saml_user'))
        expect(response.parsed_body['errors']).to eq([I18n.t('messages.login_saml_user')])
        expect(a_request(:post, verify_url)).not_to have_been_made
      end

      it 'still refuses a saml user when only the portal url is configured' do
        with_modified_env(COMVOR_PORTAL_API_URL: 'https://api.comvor.test') do
          post :create, params: { email: saml_user.email, password: portal_password }
        end

        expect(response).to have_http_status(:unauthorized)
        expect(a_request(:post, verify_url)).not_to have_been_made
      end
    end

    context 'with no password supplied' do
      it 'refuses without calling the portal' do
        with_modified_env(portal_env) { post :create, params: { email: saml_user.email } }

        expect(response).to have_http_status(:unauthorized)
        expect(a_request(:post, verify_url)).not_to have_been_made
      end
    end
  end

  describe 'POST #create for paths delegation must not touch' do
    it 'leaves a non-saml user on the standard devise path' do
      user = create(:user, password: 'Test@123456')

      with_modified_env(portal_env) { post :create, params: { email: user.email, password: 'Test@123456' } }

      expect(response).to have_http_status(:success)
      expect(a_request(:post, verify_url)).not_to have_been_made
    end

    it 'leaves the sso_auth_token carve-out alone' do
      sso_token = saml_user.generate_sso_auth_token

      with_modified_env(portal_env) { post :create, params: { email: saml_user.email, sso_auth_token: sso_token } }

      expect(response).to have_http_status(:success)
      expect(a_request(:post, verify_url)).not_to have_been_made
    end
  end
end
