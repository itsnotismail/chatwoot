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
    params = { email: email }
    params[:password] = password if password
    with_modified_env(portal_env) { post :create, params: params }
  end

  def rendered_refusal
    { status: response.status, body: response.parsed_body }
  end

  # The response an email nobody has ever heard of earns, with delegation on.
  # Every delegated refusal has to be indistinguishable from this one.
  def unknown_email_refusal
    sign_in_with_portal_password(email: 'nobody@example.test')
    rendered_refusal
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
      before { stub_verify({ ok: false, totp_required: false }) }

      it 'returns the generic bad credentials refusal, not a saml specific one' do
        sign_in_with_portal_password

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body['errors']).to eq([I18n.t('devise_token_auth.sessions.bad_credentials')])
        expect(response.parsed_body).not_to have_key('message')
        expect(response.parsed_body['errors']).not_to include(I18n.t('messages.login_saml_user'))
        expect(response.headers['access-token']).to be_nil
      end

      # Pins the property rather than a string: a wrong password for a
      # provisioned SAML agent must not be tellable apart from an email nobody
      # has ever heard of, or the endpoint becomes an account-enumeration oracle.
      it 'is byte for byte indistinguishable from a login for an email that does not exist' do
        sign_in_with_portal_password
        delegated_rejection = rendered_refusal

        expect(delegated_rejection).to eq(unknown_email_refusal)
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
        expect(response.parsed_body['errors']).to eq([I18n.t('devise_token_auth.sessions.bad_credentials')])
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

      # Mirror image of the blank-password case above: with delegation off the
      # SAML message is still correct advice, and today's payload survives
      # verbatim. That is what makes the dark rollout provably inert.
      it 'keeps the saml refusal for a blank password too' do
        post :create, params: { email: saml_user.email }

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

    # Omitting a field is an easier leak to stumble into than mistyping one, so
    # the blank-password branch has to land on the same generic refusal.
    context 'with no password supplied' do
      it 'is indistinguishable from a login for an email that does not exist' do
        with_modified_env(portal_env) { post :create, params: { email: saml_user.email } }
        blank_password_refusal = rendered_refusal

        expect(blank_password_refusal).to eq(unknown_email_refusal)
      end

      it 'never asks the portal to verify an empty credential' do
        with_modified_env(portal_env) { post :create, params: { email: saml_user.email, password: '' } }

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
