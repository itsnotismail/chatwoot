require 'rails_helper'
require_relative '../../support/comvor_saml_helpers'

# The settings pin (Comvor::SamlIdpPin) on Comvor's own model, so it runs
# with enterprise/ removed too.
RSpec.describe Comvor::SamlSetting do
  let(:portal) { ComvorSamlHelpers::PORTAL }
  let(:account) { create(:account) }
  let(:portal_certificate) { ComvorSamlHelpers.key_and_certificate.last.to_pem }
  let(:other_certificate) { ComvorSamlHelpers.key_and_certificate.last.to_pem }
  let(:metadata) { ComvorSamlHelpers.metadata_xml(OpenSSL::X509::Certificate.new(portal_certificate)) }
  let(:portal_settings) do
    { account: account, sso_url: "#{portal}/portal/saml/sso", idp_entity_id: "#{portal}/portal/saml/metadata",
      sp_entity_id: "comvor-chatwoot-account-#{account.id}", certificate: portal_certificate }
  end

  before { stub_request(:get, "#{portal}/portal/saml/metadata").to_return(status: 200, body: metadata) }

  around do |example|
    with_modified_env(COMVOR_PORTAL_API_URL: portal) { example.run }
  end

  it 'is the account_saml_settings table, reached as Account#comvor_saml_setting' do
    setting = described_class.create!(portal_settings)

    expect(described_class.table_name).to eq('account_saml_settings')
    # By class name and id, not ==: the test env reloads classes (cache_classes
    # false), and upstream's ApplicationMailer adds a view path when first
    # autoloaded, so the next request unloads every constant. described_class
    # is then the class from before that reload, the association's the one after.
    reached = account.reload.comvor_saml_setting
    expect([reached.class.name, reached.id]).to eq([described_class.name, setting.id])
  end

  it 'accepts the portal as identity provider' do
    expect(described_class.new(portal_settings)).to be_valid
  end

  it 'refuses another SSO address' do
    setting = described_class.new(portal_settings.merge(sso_url: 'https://evil.example.com/sso'))
    expect(setting).not_to be_valid
    expect(setting.errors[:sso_url]).to be_present
  end

  it 'refuses another identity provider entity id' do
    setting = described_class.new(portal_settings.merge(idp_entity_id: 'https://evil.example.com/metadata'))
    expect(setting).not_to be_valid
    expect(setting.errors[:idp_entity_id]).to be_present
  end

  it 'refuses a certificate the portal does not publish' do
    setting = described_class.new(portal_settings.merge(certificate: other_certificate))
    expect(setting).not_to be_valid
    expect(setting.errors[:certificate]).to be_present
  end

  it 'refuses another service provider name' do
    setting = described_class.new(portal_settings.merge(sp_entity_id: 'comvor-chatwoot-account-999999'))
    expect(setting).not_to be_valid
    expect(setting.errors[:sp_entity_id]).to be_present
  end

  it 'refuses when the portal metadata cannot be read' do
    stub_request(:get, "#{portal}/portal/saml/metadata").to_return(status: 503)
    expect(described_class.new(portal_settings)).not_to be_valid
  end

  it 'refuses an existing row being repointed' do
    setting = described_class.create!(portal_settings)
    expect(setting.update(certificate: other_certificate)).to be(false)
    expect(setting.reload.certificate).to eq(portal_certificate)
  end

  it 'lets a pinned row change fields outside the pin' do
    setting = described_class.create!(portal_settings)
    expect(setting.update(role_mappings: { 'Agents' => { 'role' => 0 } })).to be(true)
  end

  it 'refuses every write in production without the portal address' do
    allow(Comvor::PortalIdp).to receive(:production?).and_return(true)

    with_modified_env(COMVOR_PORTAL_API_URL: nil) do
      setting = described_class.new(portal_settings)
      expect(setting).not_to be_valid
      expect(setting.errors[:base]).to include('SAML settings are managed by the Comvor portal')
    end
  end

  it 'converts no user on create: users keep their provider until their own SSO sign-in' do
    agent = create(:user, account: account)

    perform_enqueued_jobs { described_class.create!(portal_settings) }

    expect(agent.reload.provider).to eq('email')
  end
end
