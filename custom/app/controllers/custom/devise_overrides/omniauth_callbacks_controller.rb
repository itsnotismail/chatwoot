# frozen_string_literal: true

# Signs in a user the comvor_saml strategy vouched for. Every other provider,
# enterprise's saml included, goes on to super; only the mobile hand-off page
# (sign_in_user_on_mobile) is Comvor's for all of them.
#
# The strategy's callback is the portal's cross-site POST, which arrives
# without the session cookie. redirect_callbacks hands what sign-in needs,
# including the account the assertion was validated for, to
# Comvor::SamlSignInHandoff (Redis, single use, short-lived), keeps only its
# nonce in the session, and answers 303: the browser follows with a GET,
# which (unlike a 307 replay of that POST) carries the cookie just set. The
# account always comes from the hand-off, never from the follow-up request,
# and is checked again there, in case SSO was switched off in between.
module Custom::DeviseOverrides::OmniauthCallbacksController
  COMVOR_SAML = 'comvor_saml'
  COMVOR_SAML_SESSION_KEY = 'comvor_saml.sign_in'
  COMVOR_SAML_GROUP_ATTRIBUTES = %w[groups memberOf role].freeze
  COMVOR_SAML_FAILURE = 'saml-authentication-failed'

  def redirect_callbacks
    return super unless params[:provider] == COMVOR_SAML

    auth = request.env['omniauth.auth']
    return comvor_saml_refuse unless auth && request.env['omniauth.strategy'].is_a?(OmniAuth::Strategies::ComvorSaml)

    session[COMVOR_SAML_SESSION_KEY] = Comvor::SamlSignInHandoff.store(comvor_saml_sign_in(auth))
    redirect_to "/auth/#{COMVOR_SAML}/callback", status: :see_other
  rescue Comvor::SamlSignInHandoff::Unavailable
    comvor_saml_refuse(**comvor_saml_mobile(request.params['RelayState']))
  end

  def omniauth_success
    return super unless params[:provider] == COMVOR_SAML

    sign_in = Comvor::SamlSignInHandoff.claim(session.delete(COMVOR_SAML_SESSION_KEY))
    return comvor_saml_refuse if sign_in.nil?

    @comvor_mobile_app = sign_in['app']
    return comvor_saml_refuse(mobile: sign_in['mobile']) unless comvor_saml_still_enabled?(sign_in)

    @resource = Comvor::SamlUserBuilder.new(email: sign_in['email'], account_id: sign_in['account_id'], name: sign_in['name'],
                                            first_name: sign_in['first_name'], groups: sign_in['groups']).perform
    sign_in['mobile'] ? sign_in_user_on_mobile : sign_in_user
  rescue Comvor::SamlSignInHandoff::Unavailable
    comvor_saml_refuse
  rescue Comvor::SamlUserBuilder::AuthenticationFailed, ActiveRecord::RecordInvalid
    comvor_saml_refuse(mobile: sign_in['mobile'])
  end

  def omniauth_failure
    return super unless params[:strategy] == COMVOR_SAML

    comvor_saml_refuse(**comvor_saml_mobile(params[:RelayState]))
  end

  private

  # Replaces upstream's for every provider, enterprise's saml included: the
  # same first three lines, then a page with a button instead of upstream's
  # redirect. Browsers refuse to launch an external app from a navigation
  # they did not attribute to a user gesture, so a bare redirect to a custom
  # scheme is silently dropped and the user is left on a blank page; the tap
  # supplies the gesture. The page carries a one-time sso_auth_token, so it
  # must not be cached. The deep link opens the app the sign-in started from
  # (@comvor_mobile_app, set only by the comvor_saml path; nil is the default
  # app, so enterprise's saml keeps today's link).
  def sign_in_user_on_mobile
    needs_password_reset = oauth_user_needs_password_reset?
    @resource.skip_confirmation! if confirmable_enabled?
    set_random_password_if_oauth_user if needs_password_reset

    @deep_link = @resource.generate_mobile_sso_deep_link(app: @comvor_mobile_app)
    response.headers['Cache-Control'] = 'no-store'
    render 'comvor/mobile_handoff', layout: false
  end

  def comvor_saml_sign_in(auth)
    {
      'email' => auth.uid, 'name' => auth.info&.name, 'first_name' => auth.info&.first_name,
      'account_id' => auth.extra.account_id, 'groups' => comvor_saml_groups(auth.extra.raw_info),
      **comvor_saml_mobile(request.params['RelayState']).stringify_keys
    }
  end

  # SSO may have been switched off since the assertion was validated.
  def comvor_saml_still_enabled?(sign_in)
    Comvor::SamlSso.enabled_for?(Account.find_by(id: sign_in['account_id']))
  end

  # RelayState 'mobile' is the default mobile app, 'mobile_comvor' Comvor
  # Agent (Comvor::MobileApp); anything else is the web.
  def comvor_saml_mobile(relay_state)
    { mobile: Comvor::MobileApp.mobile_relay_state?(relay_state), app: Comvor::MobileApp.app_for_relay_state(relay_state) }
  end

  # app defaults to the app a claimed sign-in started from (omniauth_success).
  def comvor_saml_refuse(mobile: false, app: @comvor_mobile_app)
    url = if mobile
            Comvor::MobileApp.failure_link(app, COMVOR_SAML_FAILURE)
          else
            login_page_url(error: COMVOR_SAML_FAILURE)
          end
    redirect_to url, allow_other_host: true
  end

  def comvor_saml_groups(raw_info)
    return [] if raw_info.nil?

    COMVOR_SAML_GROUP_ATTRIBUTES.flat_map { |name| Array(raw_info.respond_to?(:multi) ? raw_info.multi(name) : raw_info[name]) }.compact
  end
end
