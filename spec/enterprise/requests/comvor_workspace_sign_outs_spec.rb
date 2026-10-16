require 'rails_helper'

# App review 2026-10-17, L13 (seen live): signing out of the Comvor portal left the workspace session in
# place, so the next person on a shared phone landed in the previous person's inbox.
RSpec.describe 'Comvor workspace sign-out', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:auth_headers) { user.create_new_auth_token }
  let(:portal_login) { 'https://app.comvor.test/login' }

  let(:session_cookie) { { 'Cookie' => "cw_d_session_info=#{CGI.escape(auth_headers.to_json)}" } }

  before do
    create(:account_saml_settings, account: account, sso_url: 'https://app.comvor.test/portal/saml/sso')
  end

  it 'revokes the session token named in the cookie, so it can no longer call the API' do
    get '/comvor/sign_out', params: { return_to: portal_login }, headers: session_cookie

    expect(user.reload.tokens).not_to have_key(auth_headers['client'])
    get '/api/v1/profile', headers: auth_headers, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'expires the workspace session cookies' do
    get '/comvor/sign_out', params: { return_to: portal_login }, headers: session_cookie

    set_cookie = Array(response.headers['Set-Cookie']).join("\n")
    %w[cw_d_session_info auth_data user].each do |name|
      expect(set_cookie).to match(/#{name}=;.*max-age=0|#{name}=;.*expires=Thu, 01 Jan 1970/i)
    end
  end

  it 'returns to the portal when return_to is on the portal origin' do
    get '/comvor/sign_out', params: { return_to: portal_login }, headers: session_cookie
    expect(response).to redirect_to(portal_login)
  end

  it 'never redirects to another site' do
    get '/comvor/sign_out', params: { return_to: 'https://evil.example/phish' }, headers: session_cookie
    expect(response).to redirect_to('/app/login')
  end

  it 'still ends cleanly with no session cookie at all' do
    get '/comvor/sign_out', params: { return_to: portal_login }
    expect(response).to redirect_to(portal_login)
  end
end
