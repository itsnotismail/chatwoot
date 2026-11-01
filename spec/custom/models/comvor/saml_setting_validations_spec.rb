require 'rails_helper'
require_relative '../../support/comvor_saml_helpers'

# What the settings API (behaviour B) relies on in Comvor::SamlSetting, apart
# from the portal pin (saml_setting_spec.rb). The presence, fingerprint and
# destroy examples are ported from spec/enterprise/models/account_saml_settings_spec.rb,
# Comvor's destroy example included, so they hold with enterprise/ removed.
RSpec.describe Comvor::SamlSetting do
  let(:account) { create(:account) }
  let(:certificate) { ComvorSamlHelpers.key_and_certificate.last }
  # No portal address outside production: the pin is off, so each example
  # sees only the validation it is about.
  let(:settings) do
    { account: account, sso_url: 'https://idp.example.com/saml/sso', idp_entity_id: 'https://idp.example.com/saml/metadata',
      sp_entity_id: "comvor-chatwoot-account-#{account.id}", certificate: certificate.to_pem }
  end

  around do |example|
    with_modified_env(COMVOR_PORTAL_API_URL: nil) { example.run }
  end

  describe 'validations' do
    it 'requires sso_url' do
      setting = described_class.new(settings.merge(sso_url: nil))
      expect(setting).not_to be_valid
      expect(setting.errors[:sso_url]).to include("can't be blank")
    end

    it 'requires certificate' do
      setting = described_class.new(settings.merge(certificate: nil))
      expect(setting).not_to be_valid
      expect(setting.errors[:certificate]).to include("can't be blank")
    end

    it 'requires idp_entity_id' do
      setting = described_class.new(settings.merge(idp_entity_id: nil))
      expect(setting).not_to be_valid
      expect(setting.errors[:idp_entity_id]).to include("can't be blank")
    end

    it 'requires a certificate that parses as X.509' do
      setting = described_class.new(settings.merge(certificate: 'invalid-cert-data'))
      expect(setting).not_to be_valid
      expect(setting.errors[:certificate]).to include('is not a valid X.509 certificate')
    end
  end

  describe 'role mappings naming a custom role' do
    def custom_role_for(owner)
      described_class.connection.select_value(<<~SQL.squish)
        INSERT INTO custom_roles (name, account_id, created_at, updated_at)
        VALUES ('Team', #{owner.id}, NOW(), NOW()) RETURNING id
      SQL
    end

    it "accepts a custom role of the account's own" do
      setting = described_class.new(settings.merge(role_mappings: { 'Team' => { 'custom_role_id' => custom_role_for(account) } }))
      expect(setting).to be_valid
    end

    it 'refuses a custom role of another account' do
      other_role = custom_role_for(create(:account))
      setting = described_class.new(settings.merge(role_mappings: { 'Team' => { 'custom_role_id' => other_role } }))
      expect(setting).not_to be_valid
      expect(setting.errors[:role_mappings]).to include('must name custom roles of this account')
    end

    it 'refuses a custom role that does not exist' do
      setting = described_class.new(settings.merge(role_mappings: { 'Team' => { 'custom_role_id' => 0 } }))
      expect(setting).not_to be_valid
    end

    it 'refuses a custom role id that is not a number' do
      setting = described_class.new(settings.merge(role_mappings: { 'Team' => { 'custom_role_id' => "#{custom_role_for(account)} OR 1=1" } }))
      expect(setting).not_to be_valid
    end

    { 'octal' => ->(id) { "0#{id.to_s(8)}" }, 'hexadecimal' => ->(id) { "0x#{id.to_s(16)}" } }.each do |label, spell|
      it "refuses a custom role id spelled in #{label} (it would read as another id)" do
        spelling = spell.call(custom_role_for(account))
        setting = described_class.new(settings.merge(role_mappings: { 'Team' => { 'custom_role_id' => spelling } }))
        expect(setting).not_to be_valid
      end
    end

    it 'stores a custom role id given as a decimal string as that Integer' do
      role_id = custom_role_for(account)
      setting = described_class.create!(settings.merge(role_mappings: { 'Team' => { 'custom_role_id' => role_id.to_s } }))
      expect(setting.reload.role_mappings).to eq({ 'Team' => { 'custom_role_id' => role_id } })
    end

    it 'refuses a custom role id beyond the id column' do
      setting = described_class.new(settings.merge(role_mappings: { 'Team' => { 'custom_role_id' => (2**64).to_s } }))
      expect(setting).not_to be_valid
    end

    it 'checks only when the mappings change, so a stored row stays writable' do
      setting = described_class.create!(settings)
      setting.update_columns(role_mappings: { 'Team' => { 'custom_role_id' => 0 } }) # rubocop:disable Rails/SkipsModelValidations
      expect(setting.reload.update(sso_url: 'https://idp.example.com/saml/sso2')).to be(true)
    end

    it 'accepts mappings that name only a role' do
      setting = described_class.new(settings.merge(role_mappings: { 'Admins' => { 'role' => 1 }, 'Agents' => { 'role' => 'agent' } }))
      expect(setting).to be_valid
    end
  end

  describe 'the row every reader takes' do
    it 'is the oldest, for for_account and Account#comvor_saml_setting alike' do
      oldest = described_class.create!(settings)
      described_class.new(settings).save!(validate: false)

      expect(described_class.for_account(account.id)).to eq(oldest)
      expect(account.reload.comvor_saml_setting).to eq(oldest)
    end
  end

  describe '#certificate_fingerprint' do
    it 'returns fingerprint for valid certificate' do
      fingerprint = described_class.new(settings).certificate_fingerprint

      expect(fingerprint).to be_present
      expect(fingerprint).to match(/^[A-F0-9]{2}(:[A-F0-9]{2}){19}$/) # SHA1 fingerprint format
    end

    it 'is the SHA-1 of the certificate' do
      expect(described_class.new(settings).certificate_fingerprint)
        .to eq(OpenSSL::Digest::SHA1.hexdigest(certificate.to_der).upcase.scan(/../).join(':'))
    end

    it 'returns nil for blank certificate' do
      expect(described_class.new(settings.merge(certificate: '')).certificate_fingerprint).to be_nil
    end

    it 'returns nil for invalid certificate' do
      expect(described_class.new(settings.merge(certificate: 'invalid-cert-data')).certificate_fingerprint).to be_nil
    end
  end

  describe 'on destroy' do
    it 'still resets users to email provider on destroy (rollback path)' do
      setting = described_class.create!(settings)
      expect do
        setting.destroy!
      end.to have_enqueued_job(Comvor::SamlProviderResetJob).with(account.id)
    end

    it 'converts no user on create, and resets them once destroyed' do
      user = create(:user, account: account, provider: 'saml')
      setting = perform_enqueued_jobs { described_class.create!(settings) }
      expect(user.reload.provider).to eq('saml')

      perform_enqueued_jobs { setting.destroy! }

      expect(user.reload.provider).to eq('email')
    end
  end
end
