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

  # Comvor Phase C. Phase B refused a portal second factor outright; the fork now
  # carries it, by answering with an mfa challenge the app's existing MFA screen
  # already knows how to render, then verifying the code against the portal.
  describe 'POST #create with a portal second factor' do
    let(:totp_verify_url) { 'https://api.comvor.test/portal/api/v1/internal/fork/verify-totp' }
    let(:portal_mfa_token) { Mfa::PortalTokenService.new(user: saml_user).generate_token }

    def stub_totp(body, status: 200)
      stub_request(:post, totp_verify_url).to_return(status: status, body: body.to_json)
    end

    def submit_code(params)
      with_modified_env(portal_env) { post :create, params: params }
    end

    def signed_jwt(payload)
      JWT.encode(payload, Rails.application.secret_key_base, 'HS256')
    end

    context 'when the portal reports a second factor at the password step' do
      before { stub_verify({ ok: true, totp_required: true }) }

      it 'answers with a challenge in the same shape the chatwoot mfa path produces' do
        sign_in_with_portal_password

        expect(response).to have_http_status(:partial_content)
        expect(response.parsed_body['mfa_required']).to be(true)
        expect(response.parsed_body['mfa_token']).to be_present
      end

      it 'issues no session whatsoever alongside the challenge' do
        expect { sign_in_with_portal_password }.not_to(change { saml_user.reload.tokens.count })

        expect(response.headers['access-token']).to be_nil
        expect(response.parsed_body['data']).to be_nil
      end

      # The whole point of the separate flavour: the code that answers this
      # challenge must be routed to the portal, and nothing else may be.
      it 'mints a portal flavoured token, not a chatwoot one' do
        sign_in_with_portal_password
        minted = response.parsed_body['mfa_token']

        expect(Mfa::PortalTokenService.new(token: minted).verify_token).to eq(saml_user)
      end
    end

    context 'when the agent answers the challenge' do
      it 'signs the user in on a code the portal accepts' do
        stub_totp({ ok: true })

        expect { submit_code(mfa_token: portal_mfa_token, otp_code: '123456') }
          .to change { saml_user.reload.tokens.count }.by(1)

        expect(response).to have_http_status(:success)
        expect(response.headers['access-token']).to be_present
      end

      it 'sends the code with the identity from the token and the end user ip' do
        stub_totp({ ok: true })
        request.env['REMOTE_ADDR'] = '203.0.113.9'

        submit_code(mfa_token: portal_mfa_token, otp_code: '123456')

        expect(
          a_request(:post, totp_verify_url).with(
            body: { email: saml_user.email, code: '123456' }.to_json,
            headers: { 'X-Comvor-Portal-Secret' => 'shhh', 'X-Comvor-Client-IP' => '203.0.113.9' }
          )
        ).to have_been_made
      end

      # Losing an authenticator must not kill the app path, so the app's backup
      # code field is backed by the portal's recovery codes. The fork does not
      # care which is which — the portal tries TOTP then recovery.
      it 'accepts a recovery code supplied in the backup_code field' do
        stub_totp({ ok: true })

        submit_code(mfa_token: portal_mfa_token, backup_code: 'RECOVERY-1234')

        expect(response).to have_http_status(:success)
        expect(
          a_request(:post, totp_verify_url).with(body: { email: saml_user.email, code: 'RECOVERY-1234' }.to_json)
        ).to have_been_made
      end

      # Same key and same status as the OSS path renders for a bad code
      # (spec/controllers/devise_overrides/sessions_controller_spec.rb), so a
      # portal-backed failure is indistinguishable from a Chatwoot one.
      it 'refuses a code the portal rejects with the generic mfa error' do
        stub_totp({ ok: false })

        submit_code(mfa_token: portal_mfa_token, otp_code: '000000')

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']).to eq(I18n.t('errors.mfa.invalid_code'))
        expect(response.headers['access-token']).to be_nil
      end

      it 'never asks the portal to verify an empty code' do
        submit_code(mfa_token: portal_mfa_token)

        expect(response.parsed_body['error']).to eq(I18n.t('errors.mfa.invalid_code'))
        expect(a_request(:post, totp_verify_url)).not_to have_been_made
      end
    end

    context 'when the portal is unreachable at the code step' do
      it 'fails closed rather than erroring or signing anyone in' do
        stub_request(:post, totp_verify_url).to_timeout

        submit_code(mfa_token: portal_mfa_token, otp_code: '123456')

        expect(response.status).to be < 500
        expect(response.parsed_body['error']).to eq(I18n.t('errors.mfa.invalid_code'))
        expect(response.headers['access-token']).to be_nil
      end

      it 'fails closed on a non 200 answer' do
        stub_totp({ ok: true }, status: 500)

        submit_code(mfa_token: portal_mfa_token, otp_code: '123456')

        expect(response.status).to be < 500
        expect(response.parsed_body['error']).to eq(I18n.t('errors.mfa.invalid_code'))
        expect(response.headers['access-token']).to be_nil
      end
    end

    context 'with a challenge that is not a live portal one' do
      it 'refuses an expired challenge without calling the portal' do
        expired = signed_jwt(user_id: saml_user.id, exp: 1.minute.ago.to_i, portal_totp: true)

        submit_code(mfa_token: expired, otp_code: '123456')

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body['error']).to eq(I18n.t('errors.mfa.invalid_token'))
        expect(a_request(:post, totp_verify_url)).not_to have_been_made
      end

      # The claim is the only discriminator, so a token without it is not a
      # portal challenge no matter whose user id it names.
      it 'refuses a token whose portal claim has been stripped, without calling the portal' do
        claimless = signed_jwt(user_id: saml_user.id, exp: 5.minutes.from_now.to_i)

        submit_code(mfa_token: claimless, otp_code: '123456')

        expect(response.headers['access-token']).to be_nil
        expect(a_request(:post, totp_verify_url)).not_to have_been_made
      end

      # A chatwoot-flavoured token decodes with the same key, so only the claim
      # check keeps Chatwoot's own MFA path untouched.
      it 'leaves a chatwoot flavoured challenge entirely on the oss path' do
        chatwoot_token = Mfa::TokenService.new(user: saml_user).generate_token

        submit_code(mfa_token: chatwoot_token, otp_code: '000000')

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']).to eq(I18n.t('errors.mfa.invalid_code'))
        expect(a_request(:post, totp_verify_url)).not_to have_been_made
      end

      it 'ignores a portal challenge entirely when delegation is off' do
        token = portal_mfa_token

        post :create, params: { mfa_token: token, otp_code: '123456' }

        expect(response.headers['access-token']).to be_nil
        expect(a_request(:post, totp_verify_url)).not_to have_been_made
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
