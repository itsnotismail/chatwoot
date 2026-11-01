# frozen_string_literal: true

# POST /internal/portal/agent_session: the mobile SSO deep links comvor-api's
# ForkClient.MobileDeepLink asks for (internal/portal/provision/forkauth.go).
# It sends { account_id (a number), email, name } with X-Comvor-Portal-Secret
# and reads { deep_link }; any 4xx is "not eligible", anything else a fault.
#
# The answers below are the ones the endpoint gave when it lived in
# enterprise/, recorded against it before it was rebuilt, in the order it
# checks them. The few deliberate tightenings (ids that are not whole
# numbers, an email that is not a string) are called out where they are
# specced.
require 'rails_helper'

RSpec.describe 'POST /internal/portal/agent_session', type: :request do
  let(:secret) { 'portal-fork-shared-secret-for-specs' }
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:member) { create(:user, email: 'member@example.com', account: account) }
  let(:outsider) { create(:user, email: 'outsider@example.com', account: other_account) }
  let(:headers) { { 'X-Comvor-Portal-Secret' => secret } }

  around do |example|
    with_modified_env(PORTAL_FORK_SHARED_SECRET: secret) { example.run }
  end

  before do
    account.enable_features!('saml')
    Comvor::SamlSetting.new(account: account).save!(validate: false)
    member
  end

  def mint(params, headers: self.headers)
    post '/internal/portal/agent_session', params: params, headers: headers, as: :json
  end

  def token_of(link)
    Rack::Utils.parse_query(URI.parse(link).query)['sso_auth_token']
  end

  def kill_switch(value)
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('ENABLE_SAML_SSO_LOGIN', 'true').and_return(value)
  end

  it 'is served by the Comvor controller' do
    mint({ account_id: account.id, email: member.email })

    expect(controller).to be_a(Comvor::PortalAgentSessionsController)
  end

  describe 'the shared secret' do
    it 'answers 404 for everything while no secret is set, so the endpoint is dark' do
      ['', nil].each do |unset|
        with_modified_env(PORTAL_FORK_SHARED_SECRET: unset) do
          mint({ account_id: account.id, email: member.email })
          expect(response).to have_http_status(:not_found)
          expect(response.parsed_body).to eq('error' => 'not found')
          mint({ account_id: account.id, email: member.email }, headers: { 'X-Comvor-Portal-Secret' => '' })
          expect(response).to have_http_status(:not_found)
        end
      end
    end

    it 'answers 401 for a missing, empty or wrong secret, and mints nothing' do
      [{}, { 'X-Comvor-Portal-Secret' => '' }, { 'X-Comvor-Portal-Secret' => 'wrong' }, { 'X-Comvor-Portal-Secret' => "#{secret}x" },
       { 'X-Comvor-Portal-Secret' => secret[0..-2] }, { 'X-Comvor-Portal-Secret' => secret.upcase }].each do |bad|
        mint({ account_id: account.id, email: member.email }, headers: bad)

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body).to eq('error' => 'unauthorized')
      end
    end

    it 'checks the secret before anything else it is sent' do
      mint({ account_id: 999_999, email: ' ' }, headers: {})

      expect(response).to have_http_status(:unauthorized)
    end

    it 'compares SHA-256 digests in constant time, whatever the length of the secret presented' do
      allow(ActiveSupport::SecurityUtils).to receive(:secure_compare).and_call_original

      mint({ account_id: account.id, email: member.email }, headers: { 'X-Comvor-Portal-Secret' => 'short' })

      expect(ActiveSupport::SecurityUtils).to have_received(:secure_compare).with(Digest::SHA256.hexdigest('short'), Digest::SHA256.hexdigest(secret))
    end

    it 'does not take the secret from a parameter or from a cookie' do
      post '/internal/portal/agent_session', params: { account_id: account.id, email: member.email, secret: secret }, as: :json
      expect(response).to have_http_status(:unauthorized)
      post '/internal/portal/agent_session', params: { account_id: account.id, email: member.email },
                                             headers: { 'Cookie' => "X-Comvor-Portal-Secret=#{secret}" }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'a successful mint' do
    it 'gives a mobile deep link whose one-time token signs the member in' do
      mint({ account_id: account.id, email: member.email, name: 'Member' })

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/json')
      link = response.parsed_body.fetch('deep_link')
      expect(link).to start_with('chatwootapp://auth/saml?')
      expect(member.reload.valid_sso_auth_token?(token_of(link))).to be true
    end

    it 'double-encodes the email, the shape the mobile app decodes' do
      mint({ account_id: account.id, email: member.email })

      expect(response.parsed_body['deep_link']).to include('email=member%2540example.com')
    end

    it 'builds the link on MOBILE_DEEP_LINK_BASE' do
      allow(GlobalConfigService).to receive(:load).and_call_original
      allow(GlobalConfigService).to receive(:load).with('MOBILE_DEEP_LINK_BASE', 'chatwootapp').and_return('comvorapp')

      mint({ account_id: account.id, email: member.email })

      expect(response.parsed_body['deep_link']).to start_with('comvorapp://auth/saml?')
    end

    it 'is not cached' do
      mint({ account_id: account.id, email: member.email })

      expect(response.headers['Cache-Control']).to include('no-store')
    end

    it 'strips and downcases the email, and takes the account id as a string of digits' do
      mint({ account_id: account.id.to_s, email: "  MEMBER@Example.com\n" })

      expect(response).to have_http_status(:ok)
      expect(member.reload.valid_sso_auth_token?(token_of(response.parsed_body['deep_link']))).to be true
    end

    it 'takes a form body as well as JSON' do
      post '/internal/portal/agent_session', params: { account_id: account.id, email: member.email }, headers: headers

      expect(response).to have_http_status(:ok)
    end

    it 'is served on the same path with a format, a trailing slash or doubled slashes' do
      ['/internal/portal/agent_session.json', '/internal/portal/agent_session/', '/internal//portal/agent_session'].each do |path|
        post path, params: { account_id: account.id, email: member.email }, headers: headers, as: :json

        expect(response).to have_http_status(:ok), path
        expect(controller).to be_a(Comvor::PortalAgentSessionsController)
      end
    end

    it 'answers only POST' do
      get '/internal/portal/agent_session', headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it 'makes the member a saml user, confirmed, still a member only of their account' do
      mint({ account_id: account.id, email: member.email })

      expect(member.reload).to have_attributes(provider: 'saml', confirmed_at: be_present)
      expect(member.account_users.pluck(:account_id)).to eq([account.id])
    end

    it 'creates a first-time agent with the name sent, as SAML sign-in would' do
      expect { mint({ account_id: account.id, email: 'New.Agent@example.com', name: ' New Agent ' }) }.to change(User, :count).by(1)

      created = User.from_email('new.agent@example.com')
      expect(response).to have_http_status(:ok)
      expect(created).to have_attributes(provider: 'saml', name: 'New Agent')
      expect(created.confirmed?).to be true
      expect(created.account_users.find_by(account_id: account.id).role).to eq('agent')
    end

    it 'names a new agent after their email when no name (or one that is no string) is sent' do
      mint({ account_id: account.id, email: 'no.name@example.com' })
      mint({ account_id: account.id, email: 'odd.name@example.com', name: { a: 1 } })

      expect(User.from_email('no.name@example.com').name).to eq('no.name')
      expect(User.from_email('odd.name@example.com').name).to eq('odd.name')
    end
  end

  describe 'the kill switch' do
    # Off gives the answer an account without SAML gets, after the account is
    # found, so what it refuses is the same as today's endpoint.
    %w[false FALSE 0].each do |off|
      it "answers 403 as an account without saml does, when ENABLE_SAML_SSO_LOGIN is #{off.inspect}" do
        kill_switch(off)

        mint({ account_id: account.id, email: member.email })

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body).to eq('error' => 'saml not enabled for account')
      end
    end

    it 'mints no token and creates no user while off' do
      kill_switch('false')
      allow(Redis::Alfred).to receive(:setex).and_call_original

      expect { mint({ account_id: account.id, email: 'would.be.new@example.com' }) }.not_to change(User, :count)
      expect(Redis::Alfred).not_to have_received(:setex)
    end

    it 'refuses before it looks at who the email belongs to' do
      kill_switch('false')

      mint({ account_id: account.id, email: outsider.email })

      expect(response.parsed_body).to eq('error' => 'saml not enabled for account')
    end

    it 'leaves the earlier answers as they are' do
      kill_switch('false')

      mint({ account_id: account.id, email: member.email }, headers: {})
      expect(response).to have_http_status(:unauthorized)
      mint({ account_id: account.id, email: ' ' })
      expect(response).to have_http_status(:bad_request)
      mint({ account_id: 999_999, email: member.email })
      expect(response).to have_http_status(:not_found)
      with_modified_env(PORTAL_FORK_SHARED_SECRET: nil) do
        mint({ account_id: account.id, email: member.email })
        expect(response).to have_http_status(:not_found)
      end
    end

    it 'mints again once it is back on' do
      kill_switch('true')

      mint({ account_id: account.id, email: member.email })

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'a malformed account id' do
    it 'answers 404 for anything that is not a plain positive whole number, and touches no user' do
      [nil, '', ' ', 'abc', '1abc', " #{account.id}", "#{account.id} ", "0#{account.id}", "#{account.id}.0", account.id.to_f,
       '1e3', '0x1', '-1', -1, 0, '0', true, false, { a: account.id }, [account.id], 2**70, '9' * 40,
       "#{account.id}\n", "#{account.id}\u0000"].each do |id|
        expect { mint({ account_id: id, email: 'would.be.new@example.com' }) }.not_to change(User, :count)

        expect(response).to have_http_status(:not_found), "account_id #{id.inspect} gave #{response.status}"
        expect(response.parsed_body).to eq('error' => 'account not found')
      end
    end

    it 'answers 404 when no account_id is sent at all' do
      mint({ email: member.email })

      expect(response).to have_http_status(:not_found)
    end

    it 'answers 404 for an id that is well formed but names no account' do
      mint({ account_id: 999_999, email: member.email })

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'the email' do
    it 'answers 400 when it is blank or missing, before the account is looked up' do
      [' ', '', nil, "\n\t"].each do |blank|
        mint({ account_id: account.id, email: blank })
        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body).to eq('error' => 'email required')
      end
      mint({ account_id: account.id })
      expect(response).to have_http_status(:bad_request)
      mint({ account_id: 999_999, email: ' ' })
      expect(response).to have_http_status(:bad_request)
    end

    it 'answers 400 for an email that is not a string, which used to become the text of an array or hash' do
      [['a@example.com'], { a: 1 }, 5, true].each do |odd|
        expect { mint({ account_id: account.id, email: odd }) }.not_to change(User, :count)

        expect(response).to have_http_status(:bad_request)
      end
    end

    it 'answers 422 when the user cannot be created' do
      expect { mint({ account_id: account.id, email: 'notanemail' }) }.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'user could not be provisioned')
    end

    it 'answers 422 when a name is too long for the user' do
      mint({ account_id: account.id, email: 'long.name@example.com', name: 'x' * 400 })

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'who may get a link' do
    it 'answers 403 for an account without the saml feature, and does not create a user there' do
      account.disable_features!('saml')

      expect { mint({ account_id: account.id, email: 'would.be.new@example.com' }) }.not_to change(User, :count)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq('error' => 'saml not enabled for account')
    end

    it 'answers 403 for an account with the feature and no settings row' do
      Comvor::SamlSetting.of_account(account.id).destroy_all

      mint({ account_id: account.id, email: member.email })

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq('error' => 'saml not enabled for account')
    end

    it 'answers 403 for a user of another account, and neither changes them nor mints for them' do
      allow(Redis::Alfred).to receive(:setex).and_call_original

      mint({ account_id: account.id, email: outsider.email })

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq('error' => 'user not authorized for account')
      expect(outsider.reload.provider).not_to eq('saml')
      expect(outsider.account_users.pluck(:account_id)).to eq([other_account.id])
      expect(Redis::Alfred).not_to have_received(:setex)
    end

    it 'does not need the portal itself to be configured, as before' do
      with_modified_env(COMVOR_PORTAL_API_URL: nil) do
        mint({ account_id: account.id, email: member.email })

        expect(response).to have_http_status(:ok)
      end
    end
  end
end
