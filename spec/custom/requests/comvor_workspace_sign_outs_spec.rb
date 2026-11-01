# frozen_string_literal: true

# App review 2026-10-17, L13 (seen live): signing out of the Comvor portal left the workspace session in
# place, so the next person on a shared phone landed in the previous person's inbox.
#
# The first seven examples are ported from
# spec/enterprise/requests/comvor_workspace_sign_outs_spec.rb with every
# assertion kept, so they hold with enterprise/ removed. The portal origin is
# now read from the environment (COMVOR_PORTAL_URL, COMVOR_PORTAL_API_URL),
# not from an account's SAML settings.
require 'rails_helper'

RSpec.describe 'Comvor workspace sign-out', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:auth_headers) { user.create_new_auth_token }
  let(:portal_login) { 'https://app.comvor.test/login' }

  let(:session_cookie) { { 'Cookie' => "cw_d_session_info=#{CGI.escape(auth_headers.to_json)}" } }

  around do |example|
    with_modified_env(COMVOR_PORTAL_URL: 'https://app.comvor.test', COMVOR_PORTAL_API_URL: 'https://api.comvor.test') { example.run }
  end

  def sign_out(return_to, headers: session_cookie)
    get '/comvor/sign_out', params: { return_to: return_to }, headers: headers
  end

  it 'revokes the session token named in the cookie, so it can no longer call the API' do
    sign_out(portal_login)

    expect(user.reload.tokens).not_to have_key(auth_headers['client'])
    get '/api/v1/profile', headers: auth_headers, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'expires the workspace session cookies' do
    sign_out(portal_login)

    set_cookie = Array(response.headers['Set-Cookie']).join("\n")
    %w[cw_d_session_info auth_data user].each do |name|
      expect(set_cookie).to match(/#{name}=;.*max-age=0|#{name}=;.*expires=Thu, 01 Jan 1970/i)
    end
  end

  it 'returns to the portal when return_to is on the portal origin' do
    sign_out(portal_login)
    expect(response).to redirect_to(portal_login)
  end

  it 'continues to a path on this host, such as the SSO sign-in, after ending the session' do
    sign_out('/app/login/sso?target=mobile')

    expect(response).to redirect_to('/app/login/sso?target=mobile')
    expect(user.reload.tokens).not_to have_key(auth_headers['client'])
  end

  it 'does not treat a protocol-relative URL as a path on this host' do
    sign_out('//evil.example/phish')
    expect(response).to redirect_to('/app/login')
  end

  it 'never redirects to another site' do
    sign_out('https://evil.example/phish')
    expect(response).to redirect_to('/app/login')
  end

  it 'still ends cleanly with no session cookie at all' do
    get '/comvor/sign_out', params: { return_to: portal_login }
    expect(response).to redirect_to(portal_login)
  end

  it 'is served by the Comvor controller' do
    sign_out(portal_login)
    expect(controller).to be_a(Comvor::WorkspaceSignOutsController)
  end

  it 'is not cached' do
    sign_out(portal_login)
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  describe 'ending the session' do
    it 'does not let one user\'s other devices lose their session' do
      other = user.create_new_auth_token
      auth_headers

      sign_out(portal_login)

      expect(user.reload.tokens).to have_key(other['client'])
    end

    it 'revokes nothing when the cookie only guesses a client and uid' do
      forged = { 'uid' => user.uid, 'client' => auth_headers['client'], 'access-token' => 'not-the-token' }
      sign_out(portal_login, headers: { 'Cookie' => "cw_d_session_info=#{CGI.escape(forged.to_json)}" })

      expect(response).to redirect_to(portal_login)
      expect(user.reload.tokens).to have_key(auth_headers['client'])
    end

    it 'revokes nothing for a cookie that is not JSON or not an object' do
      sign_out(portal_login, headers: { 'Cookie' => 'cw_d_session_info=%5B1%5D' })
      expect(response).to redirect_to(portal_login)
      sign_out(portal_login, headers: { 'Cookie' => 'cw_d_session_info=not-json' })
      expect(response).to redirect_to(portal_login)
    end

    it 'resets the Rails session too, as devise_token_auth\'s own sign-out does' do
      allow_any_instance_of(Comvor::WorkspaceSignOutsController).to receive(:reset_session).and_call_original # rubocop:disable RSpec/AnyInstance

      sign_out(portal_login)

      expect(controller).to have_received(:reset_session)
    end
  end

  describe 'return_to' do
    let(:fallback) { '/app/login' }

    def expect_refused(target)
      sign_out(target)
      expect(response).to have_http_status(:found)
      expect(response.headers['Location']).to eq("http://www.example.com#{fallback}"), "#{target.inspect} went to #{response.headers['Location']}"
    end

    it 'accepts the portal web origin and the portal API origin, exactly' do
      sign_out('https://app.comvor.test/login?x=1')
      expect(response.headers['Location']).to eq('https://app.comvor.test/login?x=1')
      sign_out('https://api.comvor.test/portal/saml/logout')
      expect(response.headers['Location']).to eq('https://api.comvor.test/portal/saml/logout')
    end

    it 'accepts the origin with its default port and any case in scheme and host' do
      sign_out('HTTPS://APP.comvor.test:443/login')
      expect(URI.parse(response.headers['Location']).host).to eq('app.comvor.test')
    end

    it 'refuses a host that merely starts with the portal host' do
      expect_refused('https://app.comvor.test.evil.example/login')
      expect_refused('https://app.comvor.testevil.example/login')
    end

    it 'refuses a portal host that ends in another' do
      expect_refused('https://evilapp.comvor.test/login')
    end

    it 'refuses a different scheme or port for the portal host' do
      expect_refused('http://app.comvor.test/login')
      expect_refused('https://app.comvor.test:8443/login')
      expect_refused('ftp://app.comvor.test/login')
    end

    it 'refuses userinfo' do
      expect_refused('https://app.comvor.test@evil.example/login')
      expect_refused('https://evil.example@app.comvor.test/login')
      expect_refused('https://app.comvor.test:pw@app.comvor.test/login')
      expect_refused('https://evil.example\\@app.comvor.test/login')
    end

    it 'refuses a scheme-relative address, with or without a backslash' do
      expect_refused('//app.comvor.test/login')
      expect_refused('//evil.example')
      expect_refused('/\\evil.example')
      expect_refused('\\\\evil.example')
      expect_refused('/\\/evil.example')
    end

    it 'refuses backslashes after the scheme, which a browser reads as slashes' do
      expect_refused('https:\\\\evil.example')
      expect_refused('https://evil.example\\.app.comvor.test/login')
      expect_refused('https:/\\evil.example')
    end

    it 'refuses encoded forms of the host, the slash and the separator' do
      expect_refused('https://app.comvor.test%2f@evil.example/')
      expect_refused('https://app.comvor.test%40evil.example/')
      expect_refused('https://app%2Ecomvor.test/login')
      expect_refused('https%3A%2F%2Fevil.example')
      expect_refused('/%2Fevil.example')
      expect_refused('/%2fevil.example')
      expect_refused('/%5Cevil.example')
      expect_refused('%2F%2Fevil.example')
    end

    it 'refuses whitespace and control characters, which a browser strips' do
      expect_refused("/\t/evil.example")
      expect_refused("/\n/evil.example")
      expect_refused("https://app.comvor.test\t.evil.example/")
      expect_refused("https://evil.example\r\nLocation: x")
      expect_refused(' https://evil.example/')
    end

    it 'refuses a scheme that is not http(s), and a bare host' do
      expect_refused('javascript:alert(1)')
      expect_refused('data:text/html,x')
      expect_refused('app.comvor.test/login')
      expect_refused('evil.example')
      expect_refused('')
    end

    it 'refuses a missing, repeated or structured return_to' do
      get '/comvor/sign_out', headers: session_cookie
      expect(response.headers['Location']).to eq("http://www.example.com#{fallback}")
      get '/comvor/sign_out', params: { return_to: [portal_login] }, headers: session_cookie
      expect(response.headers['Location']).to eq("http://www.example.com#{fallback}")
      get '/comvor/sign_out', params: { return_to: { a: portal_login } }, headers: session_cookie
      expect(response.headers['Location']).to eq("http://www.example.com#{fallback}")
    end

    it 'refuses an address longer than any the portal sends' do
      expect_refused("/#{'a' * 2048}")
    end

    it 'still ends the session whatever return_to is' do
      sign_out('https://evil.example/')

      expect(user.reload.tokens).not_to have_key(auth_headers['client'])
    end

    it 'allows no portal origin while none is set, but still paths on this host' do
      with_modified_env(COMVOR_PORTAL_URL: nil, COMVOR_PORTAL_API_URL: nil) do
        expect_refused(portal_login)
        sign_out('/app/login/sso')
        expect(response).to redirect_to('/app/login/sso')
      end
    end

    it 'allows only an https portal in production' do
      allow(Comvor::PortalIdp).to receive(:production?).and_return(true)
      with_modified_env(COMVOR_PORTAL_URL: 'http://app.comvor.test', COMVOR_PORTAL_API_URL: 'https://api.comvor.test') do
        expect_refused('http://app.comvor.test/login')
        sign_out('https://api.comvor.test/x')
        expect(response.headers['Location']).to eq('https://api.comvor.test/x')
      end
    end

    it 'does not read an origin from an account\'s SAML settings' do
      Comvor::SamlSetting.new(account: account, sso_url: 'https://tenant.evil.example/saml/sso').save!(validate: false)
      expect_refused('https://tenant.evil.example/login')
    end
  end
end
