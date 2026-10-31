require 'rails_helper'

RSpec.describe Comvor::SamlIdpPin do
  let(:portal) { 'https://portal.example.test' }
  let(:account) { create(:account) }
  let(:portal_certificate) { build(:account_saml_settings).certificate }
  let(:other_certificate) { build(:account_saml_settings).certificate }
  let(:metadata) do
    encoded = portal_certificate.gsub(/-----[^-]+-----|\s/, '')
    <<~XML
      <EntityDescriptor xmlns="urn:oasis:names:tc:SAML:2.0:metadata" entityID="#{portal}/portal/saml/metadata">
        <IDPSSODescriptor><KeyDescriptor use="signing"><KeyInfo xmlns="http://www.w3.org/2000/09/xmldsig#"><X509Data>
          <X509Certificate xmlns="http://www.w3.org/2000/09/xmldsig#">#{encoded}</X509Certificate>
        </X509Data></KeyInfo></KeyDescriptor></IDPSSODescriptor>
      </EntityDescriptor>
    XML
  end
  # A certificate whose DER base64-encodes without padding, so it can sit in
  # front of another PEM and still decode cleanly.
  let(:attacker_der) do
    loop do
      der = OpenSSL::X509::Certificate.new(build(:account_saml_settings).certificate).to_der
      break der if (der.bytesize % 3).zero?
    end
  end
  let(:portal_settings) do
    { account: account, sso_url: "#{portal}/portal/saml/sso", idp_entity_id: "#{portal}/portal/saml/metadata",
      sp_entity_id: "comvor-chatwoot-account-#{account.id}", certificate: portal_certificate }
  end

  before do
    Rails.cache.delete("comvor:portal_idp:certificate_sha256:#{portal}")
    stub_request(:get, "#{portal}/portal/saml/metadata").to_return(status: 200, body: metadata)
  end

  around do |example|
    with_modified_env(COMVOR_PORTAL_API_URL: portal) { example.run }
  end

  it 'accepts the portal as identity provider' do
    expect(build(:account_saml_settings, portal_settings)).to be_valid
  end

  it 'refuses another SSO address' do
    settings = build(:account_saml_settings, portal_settings.merge(sso_url: 'https://evil.example.com/sso'))
    expect(settings).not_to be_valid
    expect(settings.errors[:sso_url]).to be_present
  end

  it 'refuses another identity provider entity id' do
    settings = build(:account_saml_settings, portal_settings.merge(idp_entity_id: 'https://evil.example.com/metadata'))
    expect(settings).not_to be_valid
    expect(settings.errors[:idp_entity_id]).to be_present
  end

  it 'refuses a certificate the portal does not publish' do
    settings = build(:account_saml_settings, portal_settings.merge(certificate: other_certificate))
    expect(settings).not_to be_valid
    expect(settings.errors[:certificate]).to be_present
  end

  it 'refuses another service provider name' do
    settings = build(:account_saml_settings, portal_settings.merge(sp_entity_id: 'comvor-chatwoot-account-999999'))
    expect(settings).not_to be_valid
    expect(settings.errors[:sp_entity_id]).to be_present
  end

  describe 'a certificate with another one placed before it' do
    # OpenSSL skips the leading text and reads the portal certificate;
    # ruby-saml, at callback time, decodes the leading text as the certificate.
    let(:forged) do
      "#{Base64.strict_encode64(attacker_der)}\n#{portal_certificate}"
    end
    let(:portal_sha) { OpenSSL::Digest::SHA256.hexdigest(OpenSSL::X509::Certificate.new(portal_certificate).to_der) }

    it 'is stored as the clean portal certificate' do
      settings = build(:account_saml_settings, portal_settings.merge(certificate: forged))

      expect(settings.save).to be(true)
      expect(Comvor::PortalIdp.saml_certificate_sha256(settings.reload.certificate)).to eq(portal_sha)
    end

    it 'is read the way the callback reads it' do
      expect(Comvor::PortalIdp.saml_certificate_sha256(forged)).not_to eq(portal_sha)
    end
  end

  it 'refuses when the portal metadata cannot be read' do
    stub_request(:get, "#{portal}/portal/saml/metadata").to_return(status: 503)
    expect(build(:account_saml_settings, portal_settings)).not_to be_valid
  end

  it 'refuses an existing row being repointed' do
    settings = create(:account_saml_settings, portal_settings)
    expect(settings.update(certificate: other_certificate)).to be(false)
    expect(settings.reload.certificate).to eq(portal_certificate)
  end

  it 'lets a pinned row change fields outside the pin' do
    settings = create(:account_saml_settings, portal_settings)
    expect(settings.update(role_mappings: { 'Agents' => { 'role' => 0 } })).to be(true)
  end

  context 'without the portal address' do
    around do |example|
      with_modified_env(COMVOR_PORTAL_API_URL: nil) { example.run }
    end

    it 'refuses every write in production' do
      allow(Comvor::PortalIdp).to receive(:production?).and_return(true)
      settings = build(:account_saml_settings, portal_settings)
      expect(settings).not_to be_valid
      expect(settings.errors[:base]).to include('SAML settings are managed by the Comvor portal')
    end

    it 'leaves other environments unpinned' do
      expect(build(:account_saml_settings, account: account)).to be_valid
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/saml_settings', type: :request do
    let(:admin) { create(:user, account: account, role: :administrator) }

    before { account.enable_features!('saml') }

    it 'refuses an administrator pointing the account at their own identity provider' do
      patch "/api/v1/accounts/#{account.id}/saml_settings",
            params: { saml_settings: portal_settings.except(:account).merge(sso_url: 'https://evil.example.com/sso',
                                                                            idp_entity_id: 'https://evil.example.com/metadata',
                                                                            certificate: other_certificate) },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.reload.saml_settings).to be_nil
    end

    it 'accepts what comvor-api provisions' do
      patch "/api/v1/accounts/#{account.id}/saml_settings",
            params: { saml_settings: portal_settings.except(:account) },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(account.reload.saml_settings.sso_url).to eq("#{portal}/portal/saml/sso")
    end
  end

  describe 'SAML sign-in guard', type: :request do
    let(:callback) { "/omniauth/saml/callback?account_id=#{account.id}" }

    it 'refuses a stored row whose certificate the callback would read as another one' do
      settings = create(:account_saml_settings, portal_settings)
      settings.update_columns(certificate: "#{Base64.strict_encode64(attacker_der)}\n#{portal_certificate}") # rubocop:disable Rails/SkipsModelValidations

      post callback, params: { SAMLResponse: 'x' }

      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses a callback for an account whose stored row names another identity provider' do
      settings = create(:account_saml_settings, portal_settings)
      settings.update_columns(certificate: other_certificate) # rubocop:disable Rails/SkipsModelValidations

      post callback, params: { SAMLResponse: 'x' }

      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses however the path is spelled' do
      settings = create(:account_saml_settings, portal_settings)
      settings.update_columns(certificate: other_certificate) # rubocop:disable Rails/SkipsModelValidations

      ["/OMNIAUTH/SAML/CALLBACK?account_id=#{account.id}", "/Omniauth/Saml/Callback/?account_id=#{account.id}"].each do |path|
        post path, params: { SAMLResponse: 'x' }
        expect(response).to have_http_status(:forbidden), path
      end
    end

    it 'refuses a stored row with another service provider name' do
      settings = create(:account_saml_settings, portal_settings)
      settings.update_columns(sp_entity_id: 'comvor-chatwoot-account-999999') # rubocop:disable Rails/SkipsModelValidations

      post callback, params: { SAMLResponse: 'x' }

      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses when the portal metadata cannot be read' do
      create(:account_saml_settings, portal_settings)
      Rails.cache.delete("comvor:portal_idp:certificate_sha256:#{portal}")
      stub_request(:get, "#{portal}/portal/saml/metadata").to_return(status: 503)

      post callback, params: { SAMLResponse: 'x' }

      expect(response).to have_http_status(:forbidden)
    end

    it 'lets a pinned account through to SAML' do
      create(:account_saml_settings, portal_settings)

      post callback, params: { SAMLResponse: 'x' }

      expect(response).not_to have_http_status(:forbidden)
    end
  end
end
