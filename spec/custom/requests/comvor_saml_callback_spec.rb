require 'rails_helper'
require_relative '../support/comvor_saml_helpers'

# The comvor_saml strategy is registered in the app's middleware: a portal
# response posted to its return address is validated and handed to the app.
# What the app then does with it is the callback controller's business.
RSpec.describe 'POST /omniauth/comvor_saml/callback', type: :request do
  let(:portal) { ComvorSamlHelpers::PORTAL }
  let(:account) { create(:account) }
  let(:portal_keys) { ComvorSamlHelpers.key_and_certificate }

  around do |example|
    test_mode = OmniAuth.config.test_mode
    OmniAuth.config.test_mode = false
    with_modified_env(COMVOR_PORTAL_API_URL: portal, FRONTEND_URL: ComvorSamlHelpers::FRONTEND) { example.run }
  ensure
    OmniAuth.config.test_mode = test_mode
  end

  before do
    stub_request(:get, "#{portal}/portal/saml/metadata").to_return(status: 200, body: ComvorSamlHelpers.metadata_xml(portal_keys.last))
    Comvor::SamlSetting.new(account: account).save!(validate: false)
  end

  def portal_response
    ComvorSamlHelpers.saml_response(key: portal_keys.first, cert: portal_keys.last, account_id: account.id)
  end

  it 'hands a valid portal response to the app' do
    post "/omniauth/comvor_saml/callback?account_id=#{account.id}", params: { SAMLResponse: portal_response }

    expect(request.env['omniauth.error']).to be_nil
    expect(request.env['omniauth.auth']).to include('provider' => 'saml', 'uid' => 'agent@example.com')
    expect(request.env['omniauth.auth'].extra.account_id).to eq(account.id)
  end

  it 'refuses the same response the second time' do
    response_xml = portal_response
    post "/omniauth/comvor_saml/callback?account_id=#{account.id}", params: { SAMLResponse: response_xml }
    post "/omniauth/comvor_saml/callback?account_id=#{account.id}", params: { SAMLResponse: response_xml }

    expect(request.env['omniauth.auth']).to be_nil
    expect(request.env['omniauth.error'].message).to include('already used')
  end
end
