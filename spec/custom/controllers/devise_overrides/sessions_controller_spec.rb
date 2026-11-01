# frozen_string_literal: true

# Ported from spec/enterprise/controllers/enterprise/devise_overrides/sessions_controller_spec.rb
# (Comvor's portal password delegation and portal second factor, every
# example and assertion kept), so they hold with enterprise/ removed. The
# examples after the port are new: they pin the rules a clean-room rebuild
# must keep (see goals/off-enterprise/spec.md, behaviours C and G).
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
        skip 'audit events are enterprise, absent in CE mode' unless saml_user.respond_to?(:audits)

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
    let(:portal_mfa_token) { Comvor::PortalTokenService.new(user: saml_user).generate_token }

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

        expect(Comvor::PortalTokenService.new(token: minted).verify_token).to eq(saml_user)
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

  # A saml user's Chatwoot password is never a credential, whatever the
  # delegation switch says. These sign in with the user's REAL Chatwoot
  # password, so a pass cannot come from the password simply being wrong.
  describe 'POST #create with a saml user\'s own Chatwoot password' do
    let(:chatwoot_password) { 'ChatwootSideOnly1!' }
    let(:saml_login_refusal) do
      message = I18n.t('messages.login_saml_user')
      { status: 401, body: { 'success' => false, 'message' => message, 'errors' => [message] } }
    end

    it 'gives the saml refusal with delegation off' do
      post :create, params: { email: saml_user.email, password: chatwoot_password }

      expect(rendered_refusal).to eq(saml_login_refusal)
      expect(response.headers['access-token']).to be_nil
    end

    # Chatwoot's own MFA path finds the user by email and checks the local
    # password itself (DeviseOverrides::SessionsController#create), so it must
    # never be reached: it would answer with a challenge the local factor
    # can complete.
    it 'refuses before Chatwoot\'s own mfa challenge, with delegation off' do
      saml_user.update!(otp_required_for_login: true)

      post :create, params: { email: saml_user.email, password: chatwoot_password }

      expect(rendered_refusal).to eq(saml_login_refusal)
      expect(response.parsed_body).not_to have_key('mfa_token')
    end

    it 'finds the saml user however the email is cased or padded' do
      saml_user.update!(otp_required_for_login: true)

      post :create, params: { email: "  #{saml_user.email.upcase} ", password: chatwoot_password }

      expect(rendered_refusal).to eq(saml_login_refusal)
      expect(response.parsed_body).not_to have_key('mfa_token')
    end

    it 'asks the portal, not the local digest, with delegation on' do
      stub_verify({ ok: false, totp_required: false })

      sign_in_with_portal_password(password: chatwoot_password)

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['errors']).to eq([I18n.t('devise_token_auth.sessions.bad_credentials')])
      expect(response.headers['access-token']).to be_nil
      expect(a_request(:post, verify_url)).to have_been_made
    end

    # Only a VALID sso_auth_token is the exception: a made-up one must not
    # switch the saml check off.
    it 'is not let through by an sso_auth_token that does not verify' do
      post :create, params: { email: saml_user.email, password: chatwoot_password, sso_auth_token: 'not-a-real-token' }

      expect(rendered_refusal).to eq(saml_login_refusal)
      expect(response.headers['access-token']).to be_nil
    end
  end

  # The challenge after a portal second factor is answered by the portal
  # alone: nothing on the second leg may fall through to Chatwoot's own MFA
  # check (the local factor), let alone to a password sign-in.
  describe 'POST #create on the portal second leg' do
    let(:totp_verify_url) { 'https://api.comvor.test/portal/api/v1/internal/fork/verify-totp' }
    let(:portal_mfa_token) { Comvor::PortalTokenService.new(user: saml_user).generate_token }
    let(:local_factor) { instance_double(Mfa::AuthenticationService, authenticate: true) }

    # A local factor that would accept anything: if the second leg ever
    # reached Chatwoot's own MFA check, these would sign the user in.
    before do
      allow(Mfa::AuthenticationService).to receive(:new).and_return(local_factor)
      saml_user.update!(otp_required_for_login: true)
    end

    it 'never consults the local factor when the portal rejects the code' do
      stub_request(:post, totp_verify_url).to_return(status: 200, body: { ok: false }.to_json)

      with_modified_env(portal_env) { post :create, params: { mfa_token: portal_mfa_token, otp_code: '123456' } }

      expect(response).to have_http_status(:bad_request)
      expect(response.headers['access-token']).to be_nil
      expect(Mfa::AuthenticationService).not_to have_received(:new)
    end

    it 'never consults the local factor when delegation is off' do
      post :create, params: { mfa_token: portal_mfa_token, otp_code: '123456' }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']).to eq(I18n.t('errors.mfa.invalid_token'))
      expect(response.headers['access-token']).to be_nil
      expect(Mfa::AuthenticationService).not_to have_received(:new)
    end

    it 'ignores a password sent along with the challenge' do
      stub_request(:post, totp_verify_url).to_return(status: 200, body: { ok: false }.to_json)

      with_modified_env(portal_env) do
        post :create, params: { mfa_token: portal_mfa_token, otp_code: '123456', email: saml_user.email, password: 'ChatwootSideOnly1!' }
      end

      expect(response.headers['access-token']).to be_nil
      expect(Mfa::AuthenticationService).not_to have_received(:new)
    end

    # The same, with a real local factor rather than a stand-in (needs the
    # MFA encryption keys, as Chatwoot's own MFA specs do).
    context 'with Chatwoot MFA really set up for the saml user' do
      before do
        skip('Skipping since MFA is not configured in this environment') unless Chatwoot.encryption_configured?
        allow(Mfa::AuthenticationService).to receive(:new).and_call_original
        saml_user.enable_two_factor!
      end

      it 'does not accept a valid local code for a portal challenge' do
        stub_request(:post, totp_verify_url).to_return(status: 200, body: { ok: false }.to_json)

        with_modified_env(portal_env) { post :create, params: { mfa_token: portal_mfa_token, otp_code: saml_user.current_otp } }

        expect(response).to have_http_status(:bad_request)
        expect(response.headers['access-token']).to be_nil
      end
    end

    it 'refuses a challenge for a user who is no longer a saml user' do
      token = portal_mfa_token
      saml_user.update!(provider: 'email')

      with_modified_env(portal_env) { post :create, params: { mfa_token: token, otp_code: '123456' } }

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers['access-token']).to be_nil
      expect(a_request(:post, totp_verify_url)).not_to have_been_made
    end
  end
end
