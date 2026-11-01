require 'rails_helper'

# While enterprise/ is still in the image (phase 2), its own saml strategy
# and /omniauth/saml/callback keep working beside comvor_saml: the 7
# provisioned rows and any sign-in in flight use them. The Comvor callbacks
# controller passes them on to super, and the hotfix guard still stands in
# front of them.
RSpec.describe 'Enterprise SAML beside comvor_saml', type: :request do
  let(:portal) { 'https://portal.example.test' }
  let(:account) { create(:account) }
  let(:portal_settings) do
    { account: account, sso_url: "#{portal}/portal/saml/sso", idp_entity_id: "#{portal}/portal/saml/metadata",
      sp_entity_id: "comvor-chatwoot-account-#{account.id}", certificate: portal_certificate }
  end
  let(:portal_certificate) { build(:account_saml_settings).certificate }

  around do |example|
    test_mode = OmniAuth.config.test_mode
    with_modified_env(COMVOR_PORTAL_API_URL: portal, FRONTEND_URL: 'http://www.example.com') { example.run }
  ensure
    OmniAuth.config.test_mode = test_mode
    OmniAuth.config.mock_auth[:saml] = nil
  end

  before do
    skip 'enterprise SAML is absent in CE mode' unless Object.const_defined?(:AccountSamlSettings)
    encoded = portal_certificate.gsub(/-----[^-]+-----|\s/, '')
    stub_request(:get, "#{portal}/portal/saml/metadata").to_return(status: 200, body: <<~XML)
      <EntityDescriptor xmlns="urn:oasis:names:tc:SAML:2.0:metadata" entityID="#{portal}/portal/saml/metadata">
        <IDPSSODescriptor><KeyDescriptor use="signing"><KeyInfo xmlns="http://www.w3.org/2000/09/xmldsig#"><X509Data>
          <X509Certificate xmlns="http://www.w3.org/2000/09/xmldsig#">#{encoded}</X509Certificate>
        </X509Data></KeyInfo></KeyDescriptor></IDPSSODescriptor>
      </EntityDescriptor>
    XML
    account.enable_features!('saml')
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:saml] = OmniAuth::AuthHash.new(provider: 'saml', uid: 'agent@example.com',
                                                              info: { name: 'Agent', email: 'agent@example.com' })
  end

  it 'still signs a member in through /omniauth/saml/callback, past the Comvor callback code' do
    create(:account_saml_settings, portal_settings)
    member = create(:user, email: 'agent@example.com', account: account)

    get "/omniauth/saml/callback?account_id=#{account.id}"

    expect(response).to redirect_to('http://www.example.com/auth/saml/callback')
    expect(session['comvor_saml.sign_in']).to be_nil
    follow_redirect!
    expect(response).to redirect_to(%r{/app/login\?email=.+&sso_auth_token=.+$})
    expect(member.reload.provider).to eq('saml')
  end

  it 'still runs it behind the hotfix guard' do
    settings = create(:account_saml_settings, portal_settings)
    settings.update_columns(sso_url: 'https://evil.example.com/sso') # rubocop:disable Rails/SkipsModelValidations

    get "/omniauth/saml/callback?account_id=#{account.id}"

    expect(response).to have_http_status(:forbidden)
  end
end
