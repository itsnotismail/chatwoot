# frozen_string_literal: true

# Sign-out hand-off (behaviour G): a saml user's sign-out revokes the token,
# then hands the SPA the Comvor portal's single-logout URL, so the portal
# session ends too (comvor-api internal/portal/samlidp/samlidp.go, GET
# /portal/saml/logout). The URL comes from COMVOR_PORTAL_API_URL alone, never
# from tenant data such as an account's SAML settings row.
require 'rails_helper'

RSpec.describe 'Comvor: SAML sign-out hand-off', type: :request do
  let(:account) { create(:account) }
  let(:saml_user) { create(:user, provider: 'saml', account: account) }
  let(:portal_env) { { COMVOR_PORTAL_API_URL: 'https://api.comvor.test/' } }
  let(:logout_url) { 'https://api.comvor.test/portal/saml/logout' }

  def sign_out(user, env: portal_env)
    auth = user.create_new_auth_token
    with_modified_env(env) { delete '/auth/sign_out', headers: auth }
    auth
  end

  it 'revokes the token, then hands a saml user to the portal single logout' do
    auth = sign_out(saml_user)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('success' => true, 'saml_logout_url' => logout_url)
    expect(saml_user.reload.tokens).not_to have_key(auth['client'])
    get '/api/v1/profile', headers: auth, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'needs no SAML settings row on any of the user\'s accounts' do
    expect(Comvor::SamlSetting.where(account_id: saml_user.account_ids)).not_to exist

    sign_out(saml_user)

    expect(response.parsed_body['saml_logout_url']).to eq(logout_url)
  end

  it 'ignores the identity provider an account\'s settings row names' do
    Comvor::SamlSetting.new(account_id: account.id, sso_url: 'https://idp.attacker.test/portal/saml/sso',
                            idp_entity_id: 'https://idp.attacker.test/portal/saml/metadata', certificate: 'x',
                            sp_entity_id: "comvor-chatwoot-account-#{account.id}").save!(validate: false)

    sign_out(saml_user)

    expect(response.parsed_body['saml_logout_url']).to eq(logout_url)
  end

  it 'keeps upstream\'s answer for a user who is not a saml user' do
    sign_out(create(:user, account: account))

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('success' => true)
  end

  it 'keeps upstream\'s answer when the portal is not configured' do
    sign_out(saml_user, env: { COMVOR_PORTAL_API_URL: nil })

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('success' => true)
  end

  it 'hands off to no plain-HTTP portal in production' do
    allow(Comvor::PortalIdp).to receive(:production?).and_return(true)

    sign_out(saml_user, env: { COMVOR_PORTAL_API_URL: 'http://api.comvor.test' })

    expect(response.parsed_body).to eq('success' => true)
  end

  it 'still answers 404 for a token that is not signed in' do
    with_modified_env(portal_env) { delete '/auth/sign_out', headers: { 'uid' => saml_user.email, 'client' => 'x', 'access-token' => 'y' } }

    expect(response).to have_http_status(:not_found)
  end
end
