# frozen_string_literal: true

# Comvor dual-run push. Upstream sends every FCM subscription either straight
# to FCM v1 (when FIREBASE_PROJECT_ID and FIREBASE_CREDENTIALS are set) or
# through Chatwoot's hub relay (when they are not), never both. The hub can
# only reach tokens minted by the official Chatwoot app, and Comvor's own
# Firebase project can only reach tokens minted by the Comvor Agent app. So
# setting Comvor's Firebase config upstream-style would silence every agent
# still on the official app.
#
# Here each FCM subscription is routed on its own:
# - tagged `subscription_attributes['app_id'] == 'com.comvor.agent'`, with the
#   Firebase config present: direct FCM v1 with Comvor's project;
# - anything else: the hub, when the relay is on (ENABLE_PUSH_RELAY_SERVER);
# - anything else with the relay off and the config present: direct, which
#   is upstream's behaviour for that setup.
# With the Firebase config absent nothing changes: the relay sends everything,
# as upstream does.
#
# It also replaces upstream's error check, which reads the legacy API's
# `results` key and so never matches a v1 error. A subscription is now removed
# only when FCM v1 says the token is dead for this sender.
module Custom::Notification::PushNotificationService
  COMVOR_APP_ID = 'com.comvor.agent'

  # FCM v1 error codes that mean this sender can never deliver to the token.
  # https://firebase.google.com/docs/reference/fcm/rest/v1/ErrorCode
  # Everything else (QUOTA_EXCEEDED, UNAVAILABLE, INTERNAL, INVALID_ARGUMENT,
  # THIRD_PARTY_AUTH_ERROR, a 401 from a bad service account, a 404 from a
  # wrong project id) keeps the subscription.
  DEAD_TOKEN_ERROR_CODES = %w[UNREGISTERED SENDER_ID_MISMATCH].freeze
  FCM_ERROR_DETAIL_TYPE = 'type.googleapis.com/google.firebase.fcm.v1.FcmError'

  private

  def send_fcm_push(subscription)
    return unless subscription.fcm?
    return unless comvor_direct_fcm?(subscription)

    super
  rescue StandardError => e
    # A token fetch or connection failure on one subscription must not stop
    # the loop in #perform, or the hub-routed subscriptions after it get no
    # push. The subscription is kept: nothing says its token is dead.
    Rails.logger.error("FCM v1 push failed for subscription #{subscription.id}: #{e.class}")
    ChatwootExceptionTracker.new(e, account: notification.account).capture_exception
  end

  # Upstream returns early whenever the Firebase config is present. Not
  # calling super is the point of this override.
  def send_push_via_chatwoot_hub(subscription)
    return unless subscription.fcm?
    return if comvor_direct_fcm?(subscription)
    return unless chatwoot_hub_enabled?

    ChatwootHub.send_push(fcm_options(subscription))
  end

  def comvor_direct_fcm?(subscription)
    return false unless firebase_credentials_present?
    return true if comvor_app_subscription?(subscription)

    !chatwoot_hub_enabled?
  end

  # Upstream checks truthiness, and GlobalConfigService.load returns '' when a
  # Super Admin cleared the value while the env var is still set. '' would
  # count as configured and send with empty credentials.
  def firebase_credentials_present?
    GlobalConfigService.load('FIREBASE_PROJECT_ID', nil).present? && GlobalConfigService.load('FIREBASE_CREDENTIALS', nil).present?
  end

  def comvor_app_subscription?(subscription)
    subscription.subscription_attributes.to_h['app_id'] == COMVOR_APP_ID
  end

  # `response` is fcm 1.0.8's FCM#build_response hash: { body: <raw response
  # body string>, headers:, status_code:, response: }. Faraday raises no error
  # on a 4xx or 5xx there, so v1 errors arrive here as a non-200 status with
  # Google's error JSON in the body:
  #   { "error": { "code": 404, "status": "NOT_FOUND", "message": "...",
  #     "details": [{ "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
  #                   "errorCode": "UNREGISTERED" }] } }
  def remove_subscription_if_error(subscription, response)
    error = comvor_fcm_v1_error(response)
    return Rails.logger.info("FCM push sent to #{user.email} with title #{push_message[:title]}") if error.nil?

    error_code = comvor_fcm_v1_error_code(error)
    if DEAD_TOKEN_ERROR_CODES.include?(error_code)
      Rails.logger.info("FCM v1 #{error_code}: removing subscription #{subscription.id}")
      subscription.destroy!
    else
      Rails.logger.warn(
        "FCM v1 push failed for subscription #{subscription.id}: status #{response[:status_code]} #{error['status']} #{error_code}".squish
      )
    end
  end

  def comvor_fcm_v1_error(response)
    body = comvor_parse_fcm_body(response[:body])
    return body['error'] if body.is_a?(Hash) && body['error'].is_a?(Hash)
    return {} if response[:status_code].present? && response[:status_code] != 200

    nil
  end

  def comvor_parse_fcm_body(body)
    return body if body.is_a?(Hash)

    JSON.parse(body.to_s)
  rescue JSON::ParserError
    nil
  end

  def comvor_fcm_v1_error_code(error)
    detail = Array(error['details']).find { |d| d.is_a?(Hash) && d['@type'] == FCM_ERROR_DETAIL_TYPE }
    detail&.dig('errorCode')
  end
end
