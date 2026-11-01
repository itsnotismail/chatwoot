# frozen_string_literal: true

# The rate limits on POST /internal/portal/agent_session (Rack::Attack, in
# custom/config/initializers/comvor_rack_attack.rb): 30 a minute for one
# (account, email) as before, and a new cap of 300 a minute for the whole
# endpoint.
#
# Rack::Attack skips every throttle for loopback addresses, which is what a
# request spec comes from, so these requests come from a documentation
# address, with Rack::Attack switched on (it is off outside production) and
# its counters in a memory store of their own, and time stopped so that a run
# cannot straddle the start of a new one-minute window. The endpoint-wide examples
# lower GLOBAL_LIMIT so they need a dozen requests, not three hundred; the
# throttle reads it on every request, and one example pins its real size.
require 'rails_helper'

RSpec.describe 'Comvor: limits on POST /internal/portal/agent_session', type: :request do
  let(:secret) { 'portal-fork-shared-secret-for-specs' }
  let(:headers) { { 'X-Comvor-Portal-Secret' => secret } }
  let(:remote) { { 'REMOTE_ADDR' => '198.51.100.7' } }
  let(:path) { '/internal/portal/agent_session' }
  let(:per_key) { Comvor::AgentSessionThrottle::PER_KEY_LIMIT }
  let(:global) { 12 }

  around do |example|
    original = [Rack::Attack.cache.store, Rack::Attack.enabled]
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.enabled = true
    freeze_time { with_modified_env(PORTAL_FORK_SHARED_SECRET: secret) { example.run } }
  ensure
    Rack::Attack.cache.store, Rack::Attack.enabled = original
  end

  # An account that does not exist: the cheapest answer the endpoint gives.
  def mint(email: 'someone@example.com', account_id: 999_999, headers: self.headers, to: path, body: nil)
    post to, params: body || { account_id: account_id, email: email }.to_json,
             headers: headers.merge('CONTENT_TYPE' => 'application/json').merge(remote)
  end

  def reach_limit(count, **)
    count.times do |i|
      mint(**)
      expect(response).not_to have_http_status(:too_many_requests), "throttled at request #{i + 1} of #{count}"
    end
  end

  it 'registers both throttles with the sizes named in the module' do
    expect(Rack::Attack.throttles.keys).to include('portal_agent_session/account_email', 'portal_agent_session/global')
    expect(per_key).to eq(30)
    expect(Comvor::AgentSessionThrottle::GLOBAL_LIMIT).to eq(300)
  end

  describe 'per account and email' do
    it 'answers 429 to the request after the limit, and not before' do
      reach_limit(per_key)
      mint

      expect(response).to have_http_status(:too_many_requests)
    end

    it 'counts another account and another email on their own' do
      reach_limit(per_key)

      mint(email: 'other@example.com')
      expect(response).not_to have_http_status(:too_many_requests)
      mint(account_id: 999_998)
      expect(response).not_to have_http_status(:too_many_requests)
    end

    it 'counts the email however it is spelled, and the account id as a number or a string' do
      reach_limit(per_key / 2, email: 'someone@example.com')
      (per_key - (per_key / 2)).times { |i| mint(email: i.even? ? ' SOMEONE@Example.com ' : "some\none@example.com", account_id: '999999') }
      mint

      expect(response).to have_http_status(:too_many_requests)
    end

    it 'counts every spelling of the path the routes answer' do
      paths = [path, "#{path}.json", "#{path}/", '/internal//portal/agent_session', '//internal/portal//agent_session/']
      per_key.times { |i| mint(to: paths[i % paths.size]) }
      mint

      expect(response).to have_http_status(:too_many_requests)
    end

    it 'counts requests with a wrong or missing secret as well' do
      per_key.times { mint(headers: {}) }
      mint

      expect(response).to have_http_status(:too_many_requests)
    end

    it 'keeps a body that does not parse in one bucket of its own instead of failing or going free' do
      per_key.times do
        mint(body: '{bad json')
        expect(response).to have_http_status(:bad_request)
      end
      mint(body: '{bad json')
      expect(response).to have_http_status(:too_many_requests)

      mint
      expect(response).not_to have_http_status(:too_many_requests)
    end

    it 'puts a request with no account or no email in the shared bucket' do
      per_key.times { |i| mint(body: (i.even? ? { email: 'a@example.com' } : { account_id: 1 }).to_json) }
      mint(body: { email: 'b@example.com' }.to_json)

      expect(response).to have_http_status(:too_many_requests)
    end

    it 'does not count other paths or other verbs' do
      per_key.times { get path, headers: headers.merge(remote) }
      per_key.times { post '/api/v1/auth/saml_login', params: { email: 'someone@example.com' }, headers: remote }
      mint

      expect(response).not_to have_http_status(:too_many_requests)
    end
  end

  describe 'the whole endpoint' do
    before { stub_const('Comvor::AgentSessionThrottle::GLOBAL_LIMIT', global) }

    it 'answers 429 to the request after the limit, whoever it is for' do
      reach_limit(global) # a different email each time, so no per-key bucket fills
      mint(email: 'fresh@example.com')

      expect(response).to have_http_status(:too_many_requests)
    end

    it 'counts a spelling of the path the routes answer toward the same cap' do
      paths = [path, "#{path}.json", "#{path}/", '/internal//portal/agent_session']
      global.times { |i| mint(email: "user#{i}@example.com", to: paths[i % paths.size]) }
      mint(email: 'fresh@example.com')

      expect(response).to have_http_status(:too_many_requests)
    end

    it 'is not used up by callers that do not hold the secret' do
      (global + 5).times { |i| mint(email: "stranger#{i}@example.com", headers: { 'X-Comvor-Portal-Secret' => 'wrong' }) }
      (global + 5).times { |i| mint(email: "anonymous#{i}@example.com", headers: {}) }

      mint(email: 'portal@example.com')
      expect(response).not_to have_http_status(:too_many_requests)
    end

    it 'counts nothing while no secret is set' do
      with_modified_env(PORTAL_FORK_SHARED_SECRET: nil) do
        (global + 2).times { |i| mint(email: "user#{i}@example.com", headers: { 'X-Comvor-Portal-Secret' => '' }) }
      end

      mint(email: 'portal@example.com')
      expect(response).not_to have_http_status(:too_many_requests)
    end
  end
end
