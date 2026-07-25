require 'rails_helper'

RSpec.describe Internal::PortalPasswordVerifier do
  let(:portal_env) do
    { COMVOR_PORTAL_API_URL: 'https://api.comvor.test', PORTAL_FORK_SHARED_SECRET: 'shhh' }
  end
  let(:verify_url) { 'https://api.comvor.test/portal/api/v1/internal/fork/verify-password' }

  def perform
    described_class.new(email: 'agent@example.com', password: 'sekrit', client_ip: '203.0.113.9').perform
  end

  describe '.enabled?' do
    it 'is enabled when both the portal url and the shared secret are present' do
      with_modified_env(portal_env) { expect(described_class).to be_enabled }
    end

    it 'is disabled when the portal url is blank' do
      with_modified_env(portal_env.merge(COMVOR_PORTAL_API_URL: nil)) { expect(described_class).not_to be_enabled }
    end

    it 'is disabled when the shared secret is blank' do
      with_modified_env(portal_env.merge(PORTAL_FORK_SHARED_SECRET: nil)) { expect(described_class).not_to be_enabled }
    end
  end

  describe '#perform' do
    it 'posts the credential to the portal verify endpoint with the secret and the forwarded client ip' do
      stub = stub_request(:post, verify_url)
             .with(
               body: { email: 'agent@example.com', password: 'sekrit' }.to_json,
               headers: {
                 'X-Comvor-Portal-Secret' => 'shhh',
                 'X-Comvor-Client-IP' => '203.0.113.9',
                 'Content-Type' => 'application/json'
               }
             )
             .to_return(status: 200, body: { ok: true, totp_required: false }.to_json)

      with_modified_env(portal_env) { expect(perform).to eq(:ok) }
      expect(stub).to have_been_requested
    end

    it 'strips a trailing slash from the configured portal url' do
      stub = stub_request(:post, verify_url).to_return(status: 200, body: { ok: true }.to_json)

      with_modified_env(portal_env.merge(COMVOR_PORTAL_API_URL: 'https://api.comvor.test/')) do
        expect(perform).to eq(:ok)
      end
      expect(stub).to have_been_requested
    end

    it 'returns :totp_required when the portal verified the password but wants a second factor' do
      stub_request(:post, verify_url).to_return(status: 200, body: { ok: true, totp_required: true }.to_json)

      with_modified_env(portal_env) { expect(perform).to eq(:totp_required) }
    end

    it 'returns :rejected when the portal says the credential is bad' do
      stub_request(:post, verify_url).to_return(status: 200, body: { ok: false, totp_required: false }.to_json)

      with_modified_env(portal_env) { expect(perform).to eq(:rejected) }
    end

    it 'fails closed on a non-200 response' do
      stub_request(:post, verify_url).to_return(status: 500, body: { ok: true }.to_json)

      with_modified_env(portal_env) { expect(perform).to eq(:rejected) }
    end

    it 'fails closed on an unparseable body' do
      stub_request(:post, verify_url).to_return(status: 200, body: 'not json')

      with_modified_env(portal_env) { expect(perform).to eq(:rejected) }
    end

    it 'fails closed on a transport error' do
      stub_request(:post, verify_url).to_raise(Errno::ECONNREFUSED)

      with_modified_env(portal_env) { expect(perform).to eq(:rejected) }
    end

    it 'fails closed on a timeout' do
      stub_request(:post, verify_url).to_timeout

      with_modified_env(portal_env) { expect(perform).to eq(:rejected) }
    end

    it 'never writes the password or the response body to the log' do
      stub_request(:post, verify_url).to_return(status: 200, body: 'sekrit leaked in the body')
      allow(Rails.logger).to receive(:warn)

      with_modified_env(portal_env) { expect(perform).to eq(:rejected) }

      expect(Rails.logger).to have_received(:warn) do |message|
        expect(message).not_to include('sekrit')
      end
    end
  end
end
