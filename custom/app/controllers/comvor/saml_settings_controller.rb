# frozen_string_literal: true

# An account's SAML settings. comvor-api's tenant provisioning writes them
# with one PATCH (find or build, then save), and the dashboard's security
# page reads and writes them. Served instead of enterprise's controller
# (prepended routes), with the answers and fields that one gives.
#
# The service provider name is always comvor-chatwoot-account-N, whatever
# the client sends; the identity provider fields must name the Comvor
# portal (Comvor::SamlIdpPin).
class Comvor::SamlSettingsController < Api::V1::Accounts::BaseController
  RESPONSE_FIELDS = %i[id account_id sso_url certificate fingerprint idp_entity_id sp_entity_id role_mappings created_at updated_at].freeze

  before_action { authorize(Comvor::SamlSetting) }
  before_action :ensure_saml_available
  before_action :fetch_setting

  def show
    render json: settings_json(@setting || Comvor::SamlSetting.new(account: Current.account))
  end

  def create
    return render_unprocessable(['SAML settings already exist for this account']) if @setting

    save_setting(Comvor::SamlSetting.new(account: Current.account))
  end

  def update
    save_setting(@setting || Comvor::SamlSetting.new(account: Current.account))
  end

  def destroy
    @setting&.destroy!
    head :no_content
  end

  private

  def ensure_saml_available
    return render_forbidden('SAML feature not enabled for this account') unless Current.account.feature_enabled?('saml')

    render_forbidden('SAML sign-in is switched off for this installation') unless Comvor::SamlSso.switched_on?
  end

  def fetch_setting
    @setting = Comvor::SamlSetting.where(account_id: Current.account.id).order(:id).first
  end

  def save_setting(setting)
    setting.assign_attributes(setting_params)
    setting.sp_entity_id = Comvor::PortalIdp.sp_entity_id_for(Current.account.id)

    if setting.save
      render json: settings_json(setting)
    else
      render_unprocessable(setting.errors.full_messages)
    end
  end

  def setting_params
    params.require(:saml_settings).permit(:sso_url, :certificate, :idp_entity_id, role_mappings: {}).to_h
  end

  def settings_json(setting)
    RESPONSE_FIELDS.index_with { |field| field == :fingerprint ? setting.certificate_fingerprint : setting.public_send(field) }
  end

  def render_unprocessable(messages)
    render json: { errors: messages }, status: :unprocessable_entity
  end

  def render_forbidden(message)
    render json: { error: message }, status: :forbidden
  end
end
