require 'rails_helper'
require_relative '../../support/comvor_saml_helpers'

RSpec.describe Comvor::PortalIdp do
  let(:portal) { ComvorSamlHelpers::PORTAL }
  let(:metadata_url) { "#{portal}/portal/saml/metadata" }
  let(:first_cert) { ComvorSamlHelpers.key_and_certificate.last }
  let(:second_cert) { ComvorSamlHelpers.key_and_certificate.last }

  around do |example|
    with_modified_env(COMVOR_PORTAL_API_URL: portal) { example.run }
  end

  before { Redis::Alfred.delete(described_class::REFETCH_LOCK_KEY) }

  describe '.certificates' do
    it 'is every signing certificate the metadata lists, as PEM' do
      stub_request(:get, metadata_url).to_return(status: 200, body: ComvorSamlHelpers.metadata_xml(first_cert, second_cert))

      expect(described_class.certificates).to eq([first_cert.to_pem, second_cert.to_pem])
    end

    it 'leaves out a certificate published for encryption only' do
      body = ComvorSamlHelpers.metadata_xml(first_cert, second_cert).sub('use="signing"', 'use="encryption"')
      stub_request(:get, metadata_url).to_return(status: 200, body: body)

      expect(described_class.certificates).to eq([second_cert.to_pem])
    end

    it 'fails closed when the metadata cannot be read' do
      stub_request(:get, metadata_url).to_return(status: 503)

      expect { described_class.certificates }.to raise_error(described_class::MetadataError)
    end

    it 'fails closed when the metadata lists no certificate' do
      stub_request(:get, metadata_url).to_return(status: 200, body: ComvorSamlHelpers.metadata_xml)

      expect { described_class.certificates }.to raise_error(described_class::MetadataError)
    end

    it 'fails closed on metadata that is not SAML metadata' do
      stub_request(:get, metadata_url).to_return(status: 200, body: '<html>maintenance</html>')

      expect { described_class.certificates }.to raise_error(described_class::MetadataError)
    end

    it 'refuses plain HTTP in production' do
      allow(described_class).to receive(:production?).and_return(true)

      with_modified_env(COMVOR_PORTAL_API_URL: 'http://portal.example.test') do
        expect { described_class.certificates }.to raise_error(described_class::MetadataError, /https/)
      end
    end
  end

  it 'keeps the hash pin on the first published certificate' do
    stub_request(:get, metadata_url).to_return(status: 200, body: ComvorSamlHelpers.metadata_xml(first_cert, second_cert))

    expect(described_class.certificate_sha256).to eq(OpenSSL::Digest::SHA256.hexdigest(first_cert.to_der))
  end

  describe '.refetch_certificates' do
    before { stub_request(:get, metadata_url).to_return(status: 200, body: ComvorSamlHelpers.metadata_xml(first_cert)) }

    it 'reads the metadata again' do
      expect(described_class.refetch_certificates).to eq([first_cert.to_pem])
    end

    it 'reads it at most once per interval' do
      described_class.refetch_certificates

      expect(described_class.refetch_certificates).to be_nil
      expect(a_request(:get, metadata_url)).to have_been_made.once
    end

    it 'reads it again once the interval has passed' do
      allow(Redis::Alfred).to receive(:set).and_call_original
      described_class.refetch_certificates
      Redis::Alfred.delete(described_class::REFETCH_LOCK_KEY)

      expect(described_class.refetch_certificates).to eq([first_cert.to_pem])
      expect(Redis::Alfred).to have_received(:set).with(described_class::REFETCH_LOCK_KEY, 1, nx: true, ex: 60).twice
    end
  end

  describe '.secure?' do
    it 'needs the portal address' do
      with_modified_env(COMVOR_PORTAL_API_URL: nil) { expect(described_class.secure?).to be(false) }
    end

    it 'needs HTTPS in production' do
      allow(described_class).to receive(:production?).and_return(true)

      expect(described_class.secure?).to be(true)
      with_modified_env(COMVOR_PORTAL_API_URL: 'http://portal.example.test') { expect(described_class.secure?).to be(false) }
    end
  end
end
