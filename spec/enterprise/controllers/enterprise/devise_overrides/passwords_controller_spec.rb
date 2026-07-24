require 'rails_helper'

RSpec.describe 'Enterprise Passwords Controller', type: :request do
  let!(:account) { create(:account) }

  describe 'POST /auth/password' do
    context 'with SAML user email' do
      let!(:saml_user) { create(:user, email: 'saml@example.com', provider: 'saml', account: account) }

      it 'prevents password reset and returns forbidden with custom error message' do
        params = { email: saml_user.email, redirect_url: 'http://test.host' }

        post user_password_path, params: params, as: :json

        expect(response).to have_http_status(:forbidden)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be(false)
        expect(json_response['errors']).to include(I18n.t('messages.reset_password_saml_user'))
      end
    end

    context 'with non-SAML user email' do
      let!(:regular_user) { create(:user, email: 'regular@example.com', provider: 'email', account: account) }

      it 'allows password reset for non-SAML users' do
        params = { email: regular_user.email, redirect_url: 'http://test.host' }

        post user_password_path, params: params, as: :json

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['message']).to be_present
      end
    end
  end

  describe 'PUT /auth/password (reset completion)' do
    context 'with a SAML user reset token' do
      let!(:saml_user) { create(:user, email: 'saml-reset@example.com', provider: 'saml', account: account) }
      let(:token) { saml_user.send_reset_password_instructions }

      it 'declines with forbidden and the SAML error message' do
        put user_password_path,
            params: { reset_password_token: token, password: 'NewPassword1!', password_confirmation: 'NewPassword1!' },
            as: :json

        expect(response).to have_http_status(:forbidden)
        json_response = JSON.parse(response.body)
        expect(json_response['errors']).to include(I18n.t('messages.reset_password_saml_user'))
      end
    end

    context 'with an email user reset token' do
      let!(:regular_user) { create(:user, email: 'regular-reset@example.com', provider: 'email', account: account) }
      let(:token) { regular_user.send_reset_password_instructions }

      it 'still completes the reset' do
        put user_password_path,
            params: { reset_password_token: token, password: 'NewPassword1!', password_confirmation: 'NewPassword1!' },
            as: :json

        expect(response).to have_http_status(:ok)
      end
    end
  end
end
