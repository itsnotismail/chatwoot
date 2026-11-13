# frozen_string_literal: true

# POST /api/v1/auth/saml_login (the SSO page's form): sends a member of an
# account with portal SSO switched on to the comvor_saml strategy for that
# account. Anyone else gets the same answer, whether or not the email or an
# account exists.
#
# Answers 307 so the form's authenticity_token reaches the strategy's request
# phase (omniauth-rails_csrf_protection checks it there).
class Comvor::SamlLoginsController < ActionController::API
  FAILURE = 'saml-authentication-failed'

  def create
    email = params[:email].to_s.strip.downcase
    return render json: { error: I18n.t('auth.saml.invalid_email') }, status: :bad_request if email.blank?

    account = sso_account_for(email)
    return redirect_to failure_url, allow_other_host: true if account.nil?

    redirect_to "/auth/comvor_saml?account_id=#{account.id}&RelayState=#{mobile? ? params[:target] : 'web'}", status: :temporary_redirect
  end

  private

  def sso_account_for(email)
    user = User.from_email(email)
    return if user.nil?

    user.accounts.where(id: Comvor::SamlSetting.select(:account_id)).order(:id).find { |account| Comvor::SamlSso.enabled_for?(account) }
  end

  # 'mobile' (the default app) or 'mobile_comvor' (Comvor Agent); it travels
  # on as the RelayState. See Comvor::MobileApp.
  def mobile?
    Comvor::MobileApp.mobile_relay_state?(params[:target])
  end

  def failure_url
    return Comvor::MobileApp.failure_link(Comvor::MobileApp.app_for_relay_state(params[:target]), FAILURE) if mobile?

    "#{ENV.fetch('FRONTEND_URL', nil)}/app/login/sso?error=#{FAILURE}"
  end
end
