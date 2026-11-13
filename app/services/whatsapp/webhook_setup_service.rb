class Whatsapp::WebhookSetupService
  def initialize(channel, waba_id = nil, access_token = nil, is_coexistence: nil)
    @channel = channel
    @waba_id = waba_id || channel.provider_config['business_account_id']
    @access_token = access_token || channel.provider_config['api_key']
    @api_client = Whatsapp::FacebookApiClient.new(@access_token)
    @is_coexistence = is_coexistence
  end

  def perform
    validate_parameters!

    register_phone_number if should_register_phone_number?

    setup_webhook
  end

  def register_callback
    validate_parameters!
    setup_webhook
  end

  private

  # Coexistence numbers come pre-registered, so /register is redundant. @is_coexistence (from the
  # FE's FINISH event) skips the health API call entirely; the is_on_biz_app fallback only runs for
  # callers that pass no signal at all (nil) — manual setup, voice toggle, direct webhook
  # re-registration — since an explicit `false` already means the FE positively ruled out coexistence.
  # Otherwise register when either condition is met:
  # 1. Phone number is not verified (code_verification_status != 'VERIFIED')
  # 2. Phone number needs registration (pending provisioning state)
  def should_register_phone_number?
    return false if @is_coexistence
    return false if @is_coexistence.nil? && health_data[:is_on_biz_app]

    !phone_number_verified? || phone_number_needs_registration?
  end

  # Memoized so the coexistence fallback and the pending-state check share one Graph call.
  def health_data
    @health_data ||= Whatsapp::HealthService.new(@channel).fetch_health_status
  rescue StandardError => e
    Rails.logger.error("[WHATSAPP] Health status check failed: #{e.message}")
    @health_data = {}
  end

  def validate_parameters!
    raise ArgumentError, 'Channel is required' if @channel.blank?
    raise ArgumentError, 'WABA ID is required' if @waba_id.blank?
    raise ArgumentError, 'Access token is required' if @access_token.blank?
  end

  def register_phone_number
    phone_number_id = @channel.provider_config['phone_number_id']
    pin = fetch_or_create_pin

    @api_client.register_phone_number(phone_number_id, pin)
    store_pin(pin)
  rescue StandardError => e
    Rails.logger.warn("[WHATSAPP] Phone registration failed but continuing: #{e.message}")
  end

  def fetch_or_create_pin
    # Check if we have a stored PIN for this phone number
    existing_pin = @channel.provider_config['verification_pin']
    return existing_pin.to_i if existing_pin.present?

    # Generate a new 6-digit PIN if none exists
    SecureRandom.random_number(900_000) + 100_000
  end

  def store_pin(pin)
    # Store the PIN in provider_config for future use
    @channel.provider_config['verification_pin'] = pin
    @channel.save!
  end

  def setup_webhook
    callback_url = build_callback_url
    verify_token = @channel.provider_config['webhook_verify_token']

    @api_client.subscribe_waba_webhook(@waba_id, callback_url, verify_token)

  rescue StandardError => e
    Rails.logger.error("[WHATSAPP] Webhook setup failed: #{e.message}")
    raise "Webhook setup failed: #{e.message}"
  end

  def build_callback_url
    frontend_url = ENV.fetch('FRONTEND_URL', nil)
    phone_number = @channel.phone_number

    "#{frontend_url}/webhooks/whatsapp/#{phone_number}"
  end

  def phone_number_verified?
    phone_number_id = @channel.provider_config['phone_number_id']

    # Check with WhatsApp API if the phone number code verification is complete
    # This checks code_verification_status == 'VERIFIED'
    verified = @api_client.phone_number_verified?(phone_number_id)
    Rails.logger.info("[WHATSAPP] Phone number #{phone_number_id} code verification status: #{verified}")

    verified
  rescue StandardError => e
    # If verification check fails, assume not verified to be safe
    Rails.logger.error("[WHATSAPP] Phone verification status check failed: #{e.message}")
    false
  end

  def phone_number_needs_registration?
    # Check if phone is in pending provisioning state based on health data
    # This is a separate check from phone_number_verified? which only checks code verification

    phone_number_in_pending_state?

  rescue StandardError => e
    Rails.logger.error("[WHATSAPP] Phone registration check failed: #{e.message}")
    # Conservative approach: don't register if we can't determine the state
    false
  end

  def phone_number_in_pending_state?
    # Check if phone number is in "not provisioned" state based on health indicators
    # These conditions indicate the number is pending and needs registration:
    # - platform_type: "NOT_APPLICABLE" means not fully set up
    # - throughput.level: "NOT_APPLICABLE" means no messaging capacity assigned
    health_data[:platform_type] == 'NOT_APPLICABLE' ||
      health_data.dig(:throughput, :level) == 'NOT_APPLICABLE'

  rescue StandardError => e
    Rails.logger.error("[WHATSAPP] Health status check failed: #{e.message}")
    # If health check fails, assume registration is not needed to avoid errors
    false
  end
end
