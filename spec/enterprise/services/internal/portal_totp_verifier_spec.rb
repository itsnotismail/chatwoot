require 'rails_helper'

RSpec.describe Internal::PortalTotpVerifier do
  let(:portal_env) do
    { COMVOR_PORTAL_API_URL: 'https://api.comvor.test', PORTAL_FORK_SHARED_SECRET: 'shhh' }
  end
  let(:verify_url) { 'https://api.comvor.test/portal/api/v1/internal/fork/verify-totp' }

  def perform
    described_class.new(email: 'agent@example.com', code: '123456', client_ip: '203.0.113.9').perform
  end

  describe '#perform' do
    it 'posts the code to the portal verify endpoint with the secret and the forwarded client ip' do
      stub = stub_request(:post, verify_url)
             .with(
               body: { email: 'agent@example.com', code: '123456' }.to_json,
               headers: {
                 'X-Comvor-Portal-Secret' => 'shhh',
                 'X-Comvor-Client-IP' => '203.0.113.9',
                 'Content-Type' => 'application/json'
               }
             )
             .to_return(status: 200, body: { ok: true }.to_json)

      with_modified_env(portal_env) { expect(perform).to be(true) }
      expect(stub).to have_been_requested
    end

    it 'strips a trailing slash from the configured portal url' do
      stub = stub_request(:post, verify_url).to_return(status: 200, body: { ok: true }.to_json)

      with_modified_env(portal_env.merge(COMVOR_PORTAL_API_URL: 'https://api.comvor.test/')) do
        expect(perform).to be(true)
      end
      expect(stub).to have_been_requested
    end

    it 'rejects when the portal says the code is bad' do
      stub_request(:post, verify_url).to_return(status: 200, body: { ok: false }.to_json)

      with_modified_env(portal_env) { expect(perform).to be(false) }
    end

    it 'fails closed on a non-200 response' do
      stub_request(:post, verify_url).to_return(status: 500, body: { ok: true }.to_json)

      with_modified_env(portal_env) { expect(perform).to be(false) }
    end

    it 'fails closed on an unparseable body' do
      stub_request(:post, verify_url).to_return(status: 200, body: 'not json')

      with_modified_env(portal_env) { expect(perform).to be(false) }
    end

    it 'fails closed on a body that omits ok' do
      stub_request(:post, verify_url).to_return(status: 200, body: {}.to_json)

      with_modified_env(portal_env) { expect(perform).to be(false) }
    end

    it 'fails closed on a transport error' do
      stub_request(:post, verify_url).to_raise(Errno::ECONNREFUSED)

      with_modified_env(portal_env) { expect(perform).to be(false) }
    end

    it 'fails closed on a timeout' do
      stub_request(:post, verify_url).to_timeout

      with_modified_env(portal_env) { expect(perform).to be(false) }
    end

    it 'never writes the code or the response body to the log' do
      stub_request(:post, verify_url).to_return(status: 200, body: '123456 leaked in the body')
      allow(Rails.logger).to receive(:warn)

      with_modified_env(portal_env) { expect(perform).to be(false) }

      expect(Rails.logger).to have_received(:warn) do |message|
        expect(message).not_to include('123456')
      end
    end
  end
end
