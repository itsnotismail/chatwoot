require 'rails_helper'
require_relative '../support/comvor_saml_helpers'

# The SAML settings API. comvor-api's tenant provisioning writes it with one
# PATCH (provision/application.go UpsertSamlSettings, api_access_token header,
# body {"saml_settings": {...}}); the dashboard's security page reads it and
# writes it with POST, PUT and DELETE. Answers and fields are the ones
# today's endpoint gives (recorded against it in E mode before this was built).
RSpec.describe 'Comvor SAML settings API', type: :request do
  let(:portal) { ComvorSamlHelpers::PORTAL }
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:portal_certificate) { ComvorSamlHelpers.key_and_certificate.last }
  let(:other_certificate) { ComvorSamlHelpers.key_and_certificate.last }
  let(:path) { "/api/v1/accounts/#{account.id}/saml_settings" }
  let(:sp_entity_id) { "comvor-chatwoot-account-#{account.id}" }
  let(:admin_token) { { api_access_token: administrator.access_token.token } }
  # Exactly what comvor-api provisions (saga.go).
  let(:provisioned) do
    { sso_url: "#{portal}/portal/saml/sso", certificate: portal_certificate.to_pem,
      idp_entity_id: "#{portal}/portal/saml/metadata", sp_entity_id: sp_entity_id }
  end
  let(:response_fields) { %w[id account_id sso_url certificate fingerprint idp_entity_id sp_entity_id role_mappings created_at updated_at] }
  let(:verbs) { %i[get post patch put delete] }

  around do |example|
    with_modified_env(COMVOR_PORTAL_API_URL: portal) { example.run }
  end

  before do
    stub_request(:get, "#{portal}/portal/saml/metadata").to_return(status: 200, body: ComvorSamlHelpers.metadata_xml(portal_certificate))
    account.enable_features!('saml')
  end

  def json_response
    JSON.parse(response.body)
  end

  def call(verb, headers: admin_token, settings: provisioned)
    params = %i[get delete].include?(verb) ? nil : { saml_settings: settings }
    public_send(verb, path, params: params, headers: headers, as: :json)
  end

  # A row as comvor-api wrote it through today's (enterprise) controller.
  def existing_row(role_mappings: {})
    Comvor::SamlSetting.create!(provisioned.merge(account: account, role_mappings: role_mappings))
  end

  def rows
    Comvor::SamlSetting.where(account_id: account.id)
  end

  def fingerprint(certificate)
    OpenSSL::Digest::SHA1.hexdigest(certificate.to_der).upcase.scan(/../).join(':')
  end

  describe 'route precedence over config/routes.rb (enterprise present or not)' do
    %i[get post patch put delete].each do |verb|
      it "is served by Comvor::SamlSettingsController for #{verb.upcase}" do
        call(verb)

        expect(controller).to be_a(Comvor::SamlSettingsController)
      end
    end

    it 'is served by Comvor::SamlSettingsController with a .json suffix too' do
      get "#{path}.json", headers: admin_token

      expect(controller).to be_a(Comvor::SamlSettingsController)
    end
  end

  describe 'PATCH, as comvor-api provisions a tenant' do
    it 'creates the row when there is none and answers 200 with the settings' do
      call(:patch)

      expect(response).to have_http_status(:ok)
      expect(rows.count).to eq(1)
      row = rows.first
      expect(row.attributes.slice('sso_url', 'idp_entity_id', 'sp_entity_id')).to eq(provisioned.stringify_keys.except('certificate'))
      expect(OpenSSL::X509::Certificate.new(row.certificate).to_der).to eq(portal_certificate.to_der)
      expect(json_response.keys).to eq(response_fields)
      expect(json_response).to include('id' => row.id, 'account_id' => account.id, 'sp_entity_id' => sp_entity_id,
                                       'fingerprint' => fingerprint(portal_certificate), 'role_mappings' => {})
    end

    it 'updates the existing row in place, a row written by the enterprise controller included' do
      row = existing_row(role_mappings: { 'Admins' => { 'role' => 1 } })

      call(:patch)

      expect(response).to have_http_status(:ok)
      expect(rows.pluck(:id)).to eq([row.id])
      expect(row.reload.role_mappings).to eq({ 'Admins' => { 'role' => 1 } })
      expect(json_response['role_mappings']).to eq({ 'Admins' => { 'role' => 1 } })
    end

    it 'stores comvor-chatwoot-account-N whatever service provider name the client sends' do
      call(:patch, settings: provisioned.merge(sp_entity_id: 'https://evil.example.com/sp'))

      expect(response).to have_http_status(:ok)
      expect(rows.first.sp_entity_id).to eq(sp_entity_id)
      expect(json_response['sp_entity_id']).to eq(sp_entity_id)
    end

    it 'stores comvor-chatwoot-account-N when the client sends no service provider name' do
      call(:patch, settings: provisioned.except(:sp_entity_id))

      expect(response).to have_http_status(:ok)
      expect(rows.first.sp_entity_id).to eq(sp_entity_id)
    end

    it 'puts a stored row with another service provider name back to the computed one' do
      existing_row.update_columns(sp_entity_id: 'stored-name') # rubocop:disable Rails/SkipsModelValidations

      call(:patch, settings: { role_mappings: {} })

      expect(response).to have_http_status(:ok)
      expect(rows.first.sp_entity_id).to eq(sp_entity_id)
    end

    it 'changes role mappings alone' do
      existing_row

      call(:patch, settings: { role_mappings: { 'Admins' => { 'role' => 1 } } })

      expect(response).to have_http_status(:ok)
      expect(rows.first.role_mappings).to eq({ 'Admins' => { 'role' => 1 } })
    end

    it 'answers 422 without a saml_settings body' do
      patch path, params: {}, headers: admin_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(rows).to be_empty
    end
  end

  describe 'PUT, as the dashboard updates' do
    it 'updates the existing row in place' do
      row = existing_row

      call(:put, settings: { role_mappings: { 'Agents' => { 'role' => 0 } } })

      expect(response).to have_http_status(:ok)
      expect(rows.pluck(:id)).to eq([row.id])
      expect(row.reload.role_mappings).to eq({ 'Agents' => { 'role' => 0 } })
    end

    it 'creates the row when there is none' do
      call(:put)

      expect(response).to have_http_status(:ok)
      expect(rows.count).to eq(1)
    end
  end

  describe 'POST, as the dashboard creates' do
    it 'creates the row, computing the service provider name' do
      call(:post, settings: provisioned.except(:sp_entity_id))

      expect(response).to have_http_status(:ok)
      expect(rows.count).to eq(1)
      expect(json_response['sp_entity_id']).to eq(sp_entity_id)
      expect(json_response['fingerprint']).to eq(fingerprint(portal_certificate))
    end

    it 'refuses a second row for the account' do
      row = existing_row

      call(:post)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_response['errors']).to be_present
      expect(rows.pluck(:id)).to eq([row.id])
    end

    it 'refuses missing fields with the errors listed' do
      call(:post, settings: provisioned.merge(sso_url: nil))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_response['errors']).to include("Sso url can't be blank")
      expect(rows).to be_empty
    end
  end

  describe 'GET' do
    it 'answers 200 with null fields when there is no row' do
      call(:get)

      expect(response).to have_http_status(:ok)
      expect(json_response).to eq(response_fields.index_with(nil).merge('account_id' => account.id, 'role_mappings' => {}))
    end

    it 'answers the stored row' do
      row = existing_row(role_mappings: { 'Admins' => { 'role' => 1 } })

      call(:get)

      expect(response).to have_http_status(:ok)
      expect(json_response).to include('id' => row.id, 'sso_url' => "#{portal}/portal/saml/sso", 'sp_entity_id' => sp_entity_id,
                                       'fingerprint' => fingerprint(portal_certificate), 'role_mappings' => { 'Admins' => { 'role' => 1 } })
      expect(json_response['certificate']).to eq(row.certificate)
    end
  end

  describe 'DELETE' do
    let(:other_account) { create(:account) }

    # Created before perform_enqueued_jobs, which would also run its avatar job.
    before { administrator }

    it 'removes the row and answers 204' do
      existing_row

      call(:delete)

      expect(response).to have_http_status(:no_content)
      expect(rows).to be_empty
    end

    it 'answers 204 when there is no row' do
      call(:delete)

      expect(response).to have_http_status(:no_content)
    end

    it "puts the account's users back on password sign-in" do
      existing_row
      converted = create(:user, account: account, provider: 'saml')

      perform_enqueued_jobs { call(:delete) }

      expect(converted.reload.provider).to eq('email')
      expect(administrator.reload.provider).to eq('email')
    end

    it 'keeps SSO for a user who is also a member of another account that still has SAML settings' do
      existing_row
      Comvor::SamlSetting.new(account: other_account).save!(validate: false)
      shared = create(:user, account: account, provider: 'saml')
      create(:account_user, account: other_account, user: shared)

      perform_enqueued_jobs { call(:delete) }

      expect(shared.reload.provider).to eq('saml')
    end

    it 'leaves users of other accounts alone' do
      existing_row
      outsider = create(:user, account: other_account, provider: 'saml')

      perform_enqueued_jobs { call(:delete) }

      expect(outsider.reload.provider).to eq('saml')
    end
  end

  describe 'gates' do
    def expect_nothing_written(verb)
      expect(rows.count).to eq(verb == :delete ? 1 : 0)
    end

    def prepare(verb)
      existing_row if verb == :delete
    end

    it 'refuses a request without credentials' do
      %i[get patch].each do |verb|
        public_send(verb, path, params: verb == :get ? nil : { saml_settings: provisioned }, as: :json)
        expect(response).to have_http_status(:unauthorized), verb.to_s
      end
      expect(rows).to be_empty
    end

    %i[get post patch put delete].each do |verb|
      it "refuses an agent (#{verb.upcase})" do
        prepare(verb)

        call(verb, headers: { api_access_token: agent.access_token.token })

        expect(response).to have_http_status(:unauthorized)
        expect_nothing_written(verb)
      end

      it "refuses an administrator of another account (#{verb.upcase})" do
        prepare(verb)
        outsider = create(:user, account: create(:account), role: :administrator)

        call(verb, headers: { api_access_token: outsider.access_token.token })

        expect(response).to have_http_status(:unauthorized)
        expect_nothing_written(verb)
      end

      it "refuses when the account's saml feature is off (#{verb.upcase})" do
        prepare(verb)
        account.disable_features!('saml')

        call(verb)

        expect(response).to have_http_status(:forbidden)
        expect(json_response['error']).to eq('SAML feature not enabled for this account')
        expect_nothing_written(verb)
      end

      it "refuses when SAML sign-in is switched off for the installation (#{verb.upcase})" do
        prepare(verb)
        allow(GlobalConfigService).to receive(:load).and_call_original
        allow(GlobalConfigService).to receive(:load).with('ENABLE_SAML_SSO_LOGIN', 'true').and_return('false')

        call(verb)

        expect(response).to have_http_status(:forbidden)
        expect_nothing_written(verb)
      end
    end
  end

  describe 'the portal pin' do
    {
      'another SSO address' => { sso_url: 'https://evil.example.com/sso' },
      'another identity provider entity id' => { idp_entity_id: 'https://evil.example.com/metadata' }
    }.each do |label, change|
      it "refuses #{label}" do
        call(:patch, settings: provisioned.merge(change))

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response['errors']).to be_present
        expect(rows).to be_empty
      end
    end

    it 'refuses a certificate the portal does not publish' do
      call(:patch, settings: provisioned.merge(certificate: other_certificate.to_pem))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(rows).to be_empty
    end

    it 'refuses an existing row being repointed, and keeps it' do
      row = existing_row

      call(:put, settings: { sso_url: 'https://evil.example.com/sso' })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(row.reload.sso_url).to eq("#{portal}/portal/saml/sso")
    end

    it 'refuses a certificate that does not parse' do
      call(:patch, settings: provisioned.merge(certificate: 'not a certificate'))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_response['errors']).to include('Certificate is not a valid X.509 certificate')
    end
  end

  describe 'role mappings naming a custom role' do
    def custom_role_for(owner)
      Comvor::SamlSetting.connection.select_value(<<~SQL.squish)
        INSERT INTO custom_roles (name, account_id, created_at, updated_at)
        VALUES ('Team', #{owner.id}, NOW(), NOW()) RETURNING id
      SQL
    end

    it "accepts a custom role of the account's own" do
      role_id = custom_role_for(account)

      call(:patch, settings: provisioned.merge(role_mappings: { 'Team' => { 'custom_role_id' => role_id } }))

      expect(response).to have_http_status(:ok)
      expect(rows.first.role_mappings).to eq({ 'Team' => { 'custom_role_id' => role_id } })
    end

    it 'refuses a custom role of another account' do
      role_id = custom_role_for(create(:account))

      call(:patch, settings: provisioned.merge(role_mappings: { 'Team' => { 'custom_role_id' => role_id } }))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_response['errors']).to include('Role mappings must name custom roles of this account')
      expect(rows).to be_empty
    end
  end
end
