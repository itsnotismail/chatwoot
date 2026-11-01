require 'rails_helper'

# Comvor offers SAML sign-in through its portal whatever the pricing plan;
# upstream offers it on paid plans only.
describe 'GET /app/login allowed login methods', type: :request do
  def allowed_login_methods
    get '/app/login'
    JSON.parse(response.body[/allowedLoginMethods: (\[[^\]]*\])/, 1])
  end

  before { allow(ChatwootHub).to receive(:pricing_plan).and_return('community') }

  it 'includes saml on the community plan when the installation signs in through the portal' do
    with_modified_env(COMVOR_PORTAL_API_URL: 'https://portal.example.test') do
      expect(allowed_login_methods).to include('saml')
    end
  end

  it 'leaves saml out without a portal, as upstream does on the community plan' do
    with_modified_env(COMVOR_PORTAL_API_URL: nil) do
      expect(allowed_login_methods).not_to include('saml')
    end
  end

  it 'leaves saml out when SAML sign-in is switched off' do
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('ENABLE_SAML_SSO_LOGIN', 'true').and_return('false')

    with_modified_env(COMVOR_PORTAL_API_URL: 'https://portal.example.test') do
      expect(allowed_login_methods).not_to include('saml')
    end
  end

  it 'lists saml once on a paid plan' do
    allow(ChatwootHub).to receive(:pricing_plan).and_return('enterprise')

    with_modified_env(COMVOR_PORTAL_API_URL: 'https://portal.example.test') do
      expect(allowed_login_methods.count('saml')).to eq(1)
    end
  end
end
