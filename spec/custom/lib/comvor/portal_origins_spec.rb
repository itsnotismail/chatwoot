# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Comvor::PortalOrigins do
  describe '.allowed' do
    it 'is the web and API origins, without path, userinfo or a default port' do
      env = { COMVOR_PORTAL_URL: 'https://App.comvor.test:443/login/', COMVOR_PORTAL_API_URL: 'https://api.comvor.test:8443/x' }
      with_modified_env(env) { expect(described_class.allowed).to eq(['https://app.comvor.test', 'https://api.comvor.test:8443']) }
    end

    it 'is empty while neither is set or either names no usable origin' do
      with_modified_env(COMVOR_PORTAL_URL: nil, COMVOR_PORTAL_API_URL: nil) { expect(described_class.allowed).to eq([]) }
      with_modified_env(COMVOR_PORTAL_URL: 'not a url', COMVOR_PORTAL_API_URL: 'ftp://api.comvor.test') do
        expect(described_class.allowed).to eq([])
      end
      with_modified_env(COMVOR_PORTAL_URL: 'https://user:pw@app.comvor.test', COMVOR_PORTAL_API_URL: nil) { expect(described_class.allowed).to eq([]) }
    end

    it 'lists an origin once' do
      with_modified_env(COMVOR_PORTAL_URL: 'https://comvor.test', COMVOR_PORTAL_API_URL: 'https://comvor.test/') do
        expect(described_class.allowed).to eq(['https://comvor.test'])
      end
    end

    it 'leaves out an http origin in production' do
      allow(Comvor::PortalIdp).to receive(:production?).and_return(true)

      with_modified_env(COMVOR_PORTAL_URL: 'http://app.comvor.test', COMVOR_PORTAL_API_URL: 'https://api.comvor.test') do
        expect(described_class.allowed).to eq(['https://api.comvor.test'])
      end
    end
  end
end
