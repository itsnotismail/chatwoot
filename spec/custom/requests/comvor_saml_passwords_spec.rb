# frozen_string_literal: true

# A saml user can never set a Chatwoot password (behaviour D): the portal is
# their only credential authority, and a local password would sign in around
# the portal's second factor. Each path that sets one is refused; the Devise
# reset examples are ported from
# spec/enterprise/controllers/enterprise/devise_overrides/passwords_controller_spec.rb
# (upstream's and Comvor's, every assertion kept), so they hold with
# enterprise/ removed.
require 'rails_helper'

RSpec.describe 'Comvor: no Chatwoot password for a saml user', type: :request do
  let!(:account) { create(:account) }
  let(:old_password) { 'OldPassword1!' }
  let(:new_password) { 'NewPassword1!' }
  let(:refusal) { I18n.t('messages.reset_password_saml_user') }

  describe 'POST /auth/password (reset request)' do
    # The answer must not tell who signs in through the portal, so it is the
    # one any other email gets. The saml user is pointed at the portal's own
    # reset page instead of being sent a Chatwoot reset token.
    context 'with SAML user email' do
      let!(:saml_user) { create(:user, email: 'saml@example.com', provider: 'saml', account: account) }
      let(:portal_env) { { COMVOR_PORTAL_API_URL: 'https://api.comvor.test', COMVOR_PORTAL_URL: 'https://app.comvor.test/' } }

      def request_reset(email, env: portal_env)
        with_modified_env(env) { post user_password_path, params: { email: email, redirect_url: 'http://test.host' }, as: :json }
        { status: response.status, body: response.parsed_body }
      end

      it 'answers exactly as for an email nobody has heard of' do
        expect(request_reset(saml_user.email)).to eq(request_reset('nobody@example.test'))
        expect(response).to have_http_status(:ok)
      end

      it 'sends no Chatwoot reset email and stores no reset token' do
        expect { request_reset(saml_user.email) }.not_to have_enqueued_mail(Devise.mailer, :reset_password_instructions)

        expect(saml_user.reload.reset_password_token).to be_nil
      end

      it 'points the saml user at the portal reset page, with no Chatwoot reset token' do
        expect { request_reset(saml_user.email) }
          .to have_enqueued_mail(Comvor::SamlPasswordPointerMailer, :pointer).with(saml_user, 'https://app.comvor.test/forgot-password')

        mail = Comvor::SamlPasswordPointerMailer.pointer(saml_user.reload, 'https://app.comvor.test/forgot-password')
        expect(mail.to).to eq([saml_user.email])
        expect(mail.subject).to eq(I18n.t('comvor.saml_password_pointer.subject'))
        expect(mail.body.encoded).to include('href="https://app.comvor.test/forgot-password"')
        expect(mail.body.encoded).not_to include('reset_password_token')
        expect(saml_user.reset_password_token).to be_nil
      end

      it 'sends nothing when the portal is not configured' do
        expect { request_reset(saml_user.email, env: { COMVOR_PORTAL_API_URL: nil, COMVOR_PORTAL_URL: nil }) }.not_to have_enqueued_mail

        expect(response).to have_http_status(:ok)
      end

      it 'sends nothing when only the portal API address is configured' do
        expect { request_reset(saml_user.email, env: { COMVOR_PORTAL_API_URL: 'https://api.comvor.test', COMVOR_PORTAL_URL: nil }) }
          .not_to have_enqueued_mail
      end

      it 'takes the link from the environment, never from an account\'s SAML settings' do
        Comvor::SamlSetting.new(account_id: account.id, sso_url: 'https://idp.attacker.test/portal/saml/sso',
                                idp_entity_id: 'https://idp.attacker.test/portal/saml/metadata', certificate: 'x',
                                sp_entity_id: "comvor-chatwoot-account-#{account.id}").save!(validate: false)

        expect { request_reset(saml_user.email) }
          .to have_enqueued_mail(Comvor::SamlPasswordPointerMailer, :pointer).with(saml_user, 'https://app.comvor.test/forgot-password')
      end
    end

    context 'with non-SAML user email' do
      let!(:regular_user) { create(:user, email: 'regular@example.com', provider: 'email', account: account) }

      it 'allows password reset for non-SAML users' do
        params = { email: regular_user.email, redirect_url: 'http://test.host' }

        post user_password_path, params: params, as: :json

        expect(response).to have_http_status(:ok)
        json_response = response.parsed_body
        expect(json_response['message']).to be_present
      end
    end
  end

  describe 'PUT /auth/password (reset completion)' do
    context 'with a SAML user reset token' do
      let!(:saml_user) { create(:user, email: 'saml-reset@example.com', provider: 'saml', password: old_password, account: account) }
      let(:token) { saml_user.send_reset_password_instructions }

      it 'declines with forbidden and the SAML error message' do
        put user_password_path,
            params: { reset_password_token: token, password: new_password, password_confirmation: new_password },
            as: :json

        expect(response).to have_http_status(:forbidden)
        json_response = response.parsed_body
        expect(json_response['errors']).to include(refusal)
      end

      it 'leaves the password as it was and signs nobody in' do
        put user_password_path,
            params: { reset_password_token: token, password: new_password, password_confirmation: new_password },
            as: :json

        expect(saml_user.reload.valid_password?(new_password)).to be(false)
        expect(saml_user.valid_password?(old_password)).to be(true)
        expect(response.headers['access-token']).to be_nil
      end
    end

    context 'with an email user reset token' do
      let!(:regular_user) { create(:user, email: 'regular-reset@example.com', provider: 'email', account: account) }
      let(:token) { regular_user.send_reset_password_instructions }

      it 'still completes the reset' do
        put user_password_path,
            params: { reset_password_token: token, password: new_password, password_confirmation: new_password },
            as: :json

        expect(response).to have_http_status(:ok)
      end
    end
  end

  # The profile example is Comvor's, in spec/controllers/api/v1/profiles_controller_spec.rb.
  describe 'PUT /api/v1/profile' do
    let(:saml_user) { create(:user, provider: 'saml', password: old_password, account: account, role: :agent) }

    def change_password(user, current_password:)
      put '/api/v1/profile',
          params: { profile: { current_password: current_password, password: new_password, password_confirmation: new_password } },
          headers: user.create_new_auth_token,
          as: :json
    end

    it 'refuses a saml user\'s password change, even with the right current password' do
      change_password(saml_user, current_password: old_password)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq(refusal)
      expect(saml_user.reload.valid_password?(new_password)).to be(false)
    end

    it 'still lets a saml user change the rest of their profile' do
      put '/api/v1/profile', params: { profile: { name: 'Renamed Agent' } }, headers: saml_user.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(saml_user.reload.name).to eq('Renamed Agent')
    end

    it 'still lets an email user change their password' do
      email_user = create(:user, password: old_password, account: account, role: :agent)

      change_password(email_user, current_password: old_password)

      expect(response).to have_http_status(:success)
      expect(email_user.reload.valid_password?(new_password)).to be(true)
    end
  end

  # comvor-api provisioning only ever CREATES users with a password
  # (internal/portal/provision/platform.go:203-208); it never sends one on update.
  describe 'Platform API users' do
    let(:platform_app) { create(:platform_app) }
    let(:headers) { { api_access_token: platform_app.access_token.token } }
    let(:saml_user) { create(:user, provider: 'saml', password: old_password, account: account) }

    def permit(user)
      create(:platform_app_permissible, platform_app: platform_app, permissible: user)
    end

    it 'refuses a password on update for a saml user, and writes nothing' do
      permit(saml_user)

      patch "/platform/api/v1/users/#{saml_user.id}", params: { name: 'Renamed', password: new_password }, headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq(refusal)
      saml_user.reload
      expect(saml_user.valid_password?(new_password)).to be(false)
      expect(saml_user.name).not_to eq('Renamed')
    end

    it 'still updates a saml user without a password' do
      permit(saml_user)

      patch "/platform/api/v1/users/#{saml_user.id}", params: { name: 'Renamed' }, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(saml_user.reload.name).to eq('Renamed')
    end

    it 'still sets a password on update for an email user' do
      email_user = create(:user, password: old_password, account: account)
      permit(email_user)

      patch "/platform/api/v1/users/#{email_user.id}", params: { password: new_password }, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(email_user.reload.valid_password?(new_password)).to be(true)
    end

    it 'still creates a user with a password, as comvor-api provisioning does' do
      post '/platform/api/v1/users', params: { name: 'Admin', email: 'new-admin@example.com', password: new_password }, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(User.from_email('new-admin@example.com').valid_password?(new_password)).to be(true)
    end

    it 'leaves an existing saml user\'s password alone when create names their email' do
      post '/platform/api/v1/users', params: { name: 'Admin', email: saml_user.email, password: new_password }, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(saml_user.reload.valid_password?(new_password)).to be(false)
    end
  end
end
