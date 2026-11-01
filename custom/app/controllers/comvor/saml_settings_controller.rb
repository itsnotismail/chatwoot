# frozen_string_literal: true

# An account's SAML settings. comvor-api's tenant provisioning writes them
# with one PATCH (find or build, then save), and the dashboard's security
# page reads and writes them. Served instead of enterprise's controller
# (prepended routes), with the answers and fields that one gives.
#
# The service provider name is comvor-chatwoot-account-N: generated when
# the client sends none, refused when it sends another. The identity
# provider fields must name the Comvor portal (Comvor::SamlIdpPin).
#
# Reading and writing need the account's saml feature and the installation's
# ENABLE_SAML_SSO_LOGIN switch; DELETE does not, because it is the rollback
# lever and must work while SSO is switched off.
class Comvor::SamlSettingsController < Api::V1::Accounts::BaseController
  RESPONSE_FIELDS = %i[id account_id sso_url certificate fingerprint idp_entity_id sp_entity_id role_mappings created_at updated_at].freeze
  # The message the settings pin gives for the same refusal.
  SP_ENTITY_ID_REFUSED = 'Sp entity must be the Comvor portal name for this account'

  before_action { authorize(Comvor::SamlSetting) }
  before_action :ensure_saml_available, except: :destroy
  before_action :fetch_setting, except: :destroy

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

  # Every row of the account (the table allows more than one). Each destroyed
  # row enqueues its own reset job (N rows, N idempotent jobs), and one is
  # enqueued here when there was none, so the lever can be pulled again.
  def destroy
    destroyed = Comvor::SamlSetting.transaction { Comvor::SamlSetting.of_account(Current.account.id).destroy_all }
    Comvor::SamlProviderResetJob.perform_later(Current.account.id) if destroyed.empty?
    head :no_content
  end

  private

  def ensure_saml_available
    return render_forbidden('SAML feature not enabled for this account') unless Current.account.feature_enabled?('saml')

    render_forbidden('SAML sign-in is switched off for this installation') unless Comvor::SamlSso.switched_on?
  end

  def fetch_setting
    @setting = Comvor::SamlSetting.for_account(Current.account.id)
  end

  def save_setting(setting)
    attributes = setting_params
    attributes[:sp_entity_id] = expected_sp_entity_id if attributes[:sp_entity_id].blank?
    return render_unprocessable([SP_ENTITY_ID_REFUSED]) unless attributes[:sp_entity_id] == expected_sp_entity_id

    setting.assign_attributes(attributes)

    if setting.save
      render json: settings_json(setting)
    else
      render_unprocessable(setting.errors.full_messages)
    end
  end

  def setting_params
    params.require(:saml_settings).permit(:sso_url, :certificate, :idp_entity_id, :sp_entity_id, role_mappings: {}).to_h
  end

  def expected_sp_entity_id
    Comvor::PortalIdp.sp_entity_id_for(Current.account.id)
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
