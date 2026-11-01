# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Comvor::PortalIdp do
  let(:portal_env) { { COMVOR_PORTAL_API_URL: 'https://api.comvor.test', COMVOR_PORTAL_URL: 'https://app.comvor.test/' } }

  describe '.password_reset_url' do
    it 'is the portal web forgot-password page' do
      with_modified_env(portal_env) { expect(described_class.password_reset_url).to eq('https://app.comvor.test/forgot-password') }
    end

    it 'is nil when the portal web address is not set' do
      with_modified_env(portal_env.merge(COMVOR_PORTAL_URL: nil)) { expect(described_class.password_reset_url).to be_nil }
    end

    it 'is nil when the portal is not configured' do
      with_modified_env(portal_env.merge(COMVOR_PORTAL_API_URL: nil)) { expect(described_class.password_reset_url).to be_nil }
    end

    it 'is nil in production over plain HTTP' do
      allow(described_class).to receive(:production?).and_return(true)

      with_modified_env(portal_env.merge(COMVOR_PORTAL_URL: 'http://app.comvor.test')) { expect(described_class.password_reset_url).to be_nil }
    end
  end

  describe '.warn_if_insecure' do
    before { allow(Rails.logger).to receive(:warn) }

    it 'warns in production when the portal address is plain HTTP' do
      allow(described_class).to receive(:production?).and_return(true)

      with_modified_env(COMVOR_PORTAL_API_URL: 'http://api.comvor.test') { described_class.warn_if_insecure }

      expect(Rails.logger).to have_received(:warn).with(/COMVOR_PORTAL_API_URL is not https/)
    end

    it 'stays quiet for an https portal, an unconfigured one, or outside production' do
      allow(described_class).to receive(:production?).and_return(true)
      with_modified_env(COMVOR_PORTAL_API_URL: 'https://api.comvor.test') { described_class.warn_if_insecure }
      with_modified_env(COMVOR_PORTAL_API_URL: nil) { described_class.warn_if_insecure }
      allow(described_class).to receive(:production?).and_return(false)
      with_modified_env(COMVOR_PORTAL_API_URL: 'http://api.comvor.test') { described_class.warn_if_insecure }

      expect(Rails.logger).not_to have_received(:warn)
    end
  end
end
