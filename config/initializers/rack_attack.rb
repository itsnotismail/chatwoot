class Rack::Attack
  ### Configure Cache ###

  # If you don't want to use Rails.cache (Rack::Attack's default), then
  # configure it here.
  #
  # Note: The store is only used for throttling (not blocklisting and
  # safelisting). It must implement .increment and .write like
  # ActiveSupport::Cache::Store

  # Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  # https://github.com/rack/rack-attack/issues/102
  # Rails 7.1 automatically adds its own ConnectionPool around RedisCacheStore.
  # Because `$velma` is *already* a ConnectionPool, double-wrapping causes
  # Redis calls like `get` to hit the outer wrapper and explode.
  # `pool: false` tells Rails to skip its internal pool and use ours directly.
  # TODO: We can use build in connection pool in future upgrade
  Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(redis: $velma, pool: false)

  class Request < ::Rack::Request
    # You many need to specify a method to fetch the correct remote IP address
    # if the web server is behind a load balancer.
    def remote_ip
      @remote_ip ||= (env['action_dispatch.remote_ip'] || ip).to_s
    end

    def allowed_ip?
      default_allowed_ips = ['127.0.0.1', '::1']
      env_allowed_ips = ENV.fetch('RACK_ATTACK_ALLOWED_IPS', '').split(',').map(&:strip)
      (default_allowed_ips + env_allowed_ips).include?(remote_ip)
    end

    # Rails would allow requests to paths with extentions, so lets compare against the path with extention stripped
    # example /auth & /auth.json would both work
    def path_without_extentions
      path[/^[^.]+/]
    end
  end

  ### Safelist IPs from Environment Variable ###
  #
  # This block ensures requests from any IP present in RACK_ATTACK_ALLOWED_IPS
  # will bypass Rack::Attack’s throttling rules.
  #
  # Example: RACK_ATTACK_ALLOWED_IPS="127.0.0.1,::1,192.168.0.10"

  Rack::Attack.safelist('trusted IPs', &:allowed_ip?)

  # Safelist health check endpoint so it never touches Redis for throttle tracking.
  # This keeps /health fully dependency-free for ALB liveness checks.
  Rack::Attack.safelist('health check') do |req|
    req.path == '/health'
  end

  ### Throttle Spammy Clients ###

  # If any single client IP is making tons of requests, then they're
  # probably malicious or a poorly-configured scraper. Either way, they
  # don't deserve to hog all of the app server's CPU. Cut them off!
  #
  # Note: If you're serving assets through rack, those requests may be
  # counted by rack-attack and this throttle may be activated too
  # quickly. If so, enable the condition to exclude them from tracking.

  # Throttle all requests by IP (60rpm)
  #
  # Key: "rack::attack:#{Time.now.to_i/:period}:req/ip:#{req.ip}"

  throttle('req/ip', limit: ENV.fetch('RACK_ATTACK_LIMIT', '3000').to_i, period: 1.minute, &:ip)

  ###-----------------------------------------------###
  ###-----Authentication Related Throttling---------###
  ###-----------------------------------------------###

  ### Prevent Brute-Force Super Admin Login Attacks ###
  throttle('super_admin_login/ip', limit: 5, period: 5.minutes) do |req|
    req.ip if req.path_without_extentions == '/super_admin/sign_in' && req.post?
  end

  throttle('super_admin_login/email', limit: 5, period: 15.minutes) do |req|
    if req.path_without_extentions == '/super_admin/sign_in' && req.post?
      # NOTE: This line used to throw ArgumentError /rails/action_mailbox/sendgrid/inbound_emails : invalid byte sequence in UTF-8
      # Hence placed in the if block
      # ref: https://github.com/rack/rack-attack/issues/399
      email = req.params['email'].presence || ActionDispatch::Request.new(req.env).params['email'].presence
      email.to_s.downcase.gsub(/\s+/, '')
    end
  end

  # ### Prevent Brute-Force Login Attacks ###
  # Exclude MFA verification attempts from regular login throttling
  throttle('login/ip', limit: 5, period: 5.minutes) do |req|
    if req.path_without_extentions == '/auth/sign_in' && req.post? && req.params['mfa_token'].blank?
      # Skip if this is an MFA verification request
      req.ip
    end
  end

  throttle('login/email', limit: 10, period: 15.minutes) do |req|
    # Skip if this is an MFA verification request
    if req.path_without_extentions == '/auth/sign_in' && req.post? && req.params['mfa_token'].blank?
      # ref: https://github.com/rack/rack-attack/issues/399
      # NOTE: This line used to throw ArgumentError /rails/action_mailbox/sendgrid/inbound_emails : invalid byte sequence in UTF-8
      # Hence placed in the if block
      email = req.params['email'].presence || ActionDispatch::Request.new(req.env).params['email'].presence
      email.to_s.downcase.gsub(/\s+/, '')
    end
  end

  ## Reset password throttling
  throttle('reset_password/ip', limit: 5, period: 30.minutes) do |req|
    req.ip if req.path_without_extentions == '/auth/password' && req.post?
  end

  throttle('reset_password/email', limit: 5, period: 1.hour) do |req|
    if req.path_without_extentions == '/auth/password' && req.post?
      email = req.params['email'].presence || ActionDispatch::Request.new(req.env).params['email'].presence
      email.to_s.downcase.gsub(/\s+/, '')
    end
  end

  ## Resend confirmation throttling (unauthenticated)
  throttle('resend_confirmation/ip', limit: 5, period: 30.minutes) do |req|
    req.ip if req.path_without_extentions == '/resend_confirmation' && req.post?
  end

  throttle('resend_confirmation/email', limit: 5, period: 1.hour) do |req|
    if req.path_without_extentions == '/resend_confirmation' && req.post?
      email = req.params['email'].presence || ActionDispatch::Request.new(req.env).params['email'].presence
      email.to_s.downcase.gsub(/\s+/, '')
    end
  end

  ## Resend confirmation throttling (authenticated)
  throttle('resend_confirmation_auth/ip', limit: 5, period: 30.minutes) do |req|
    req.ip if req.path_without_extentions == '/api/v1/profile/resend_confirmation' && req.post?
  end

  ## MFA throttling - prevent brute force attacks
  throttle('mfa_verification/ip', limit: 5, period: 1.minute) do |req|
    if req.path_without_extentions == '/api/v1/profile/mfa'
      req.ip if req.delete? # Throttle disable attempts
    elsif req.path_without_extentions.match?(%r{/api/v1/profile/mfa/(verify|backup_codes)})
      req.ip if req.post? # Throttle verify and backup_codes attempts
    end
  end

  # Separate rate limiting for MFA verification attempts
  throttle('mfa_login/ip', limit: 10, period: 1.minute) do |req|
    req.ip if req.path_without_extentions == '/auth/sign_in' && req.post? && req.params['mfa_token'].present?
  end

  throttle('mfa_login/token', limit: 10, period: 1.minute) do |req|
    if req.path_without_extentions == '/auth/sign_in' && req.post?
      # Track by MFA token to prevent brute force on a specific token
      mfa_token = req.params['mfa_token'].presence
      (mfa_token.presence)
    end
  end

  ## Prevent Brute-Force Signup Attacks ###
  throttle('accounts/ip', limit: 5, period: 30.minutes) do |req|
    req.ip if req.path_without_extentions == '/api/v1/accounts' && req.post?
  end

  ## Comvor: portal -> fork mint endpoint (POST /internal/portal/agent_session).
  ##
  ## Keyed on account_id + email, deliberately NOT on ip. Every legitimate
  ## request originates from the single comvor-api instance, so an ip key would
  ## lump all merchants into one bucket — throttling real users the moment any
  ## one of them got busy — while doing nothing to bound abuse of a particular
  ## identity. (An ip key is also fragile here: the `trusted IPs` safelist above
  ## short-circuits ALL throttles for 127.0.0.1/::1, so if comvor-api's request
  ## ever presented as loopback the throttle would silently never fire.)
  ##
  ## The 32-byte shared secret is the primary defence; this is the blast-radius
  ## bound if it ever leaks — it caps how fast an attacker could mint sessions
  ## or enumerate which (account, email) pairs are valid. Set looser than the
  ## portal's own 20/min per user so that in normal operation the portal is the
  ## binding constraint and this is the backstop for anything bypassing it.
  throttle('portal_agent_session/account_email', limit: 30, period: 1.minute) do |req|
    if req.path_without_extentions == '/internal/portal/agent_session' && req.post?
      # Params are read inside the `if`, and the read rescues StandardError.
      # That breadth is deliberate, not laziness: this block runs in middleware
      # BEFORE the endpoint's shared-secret check, so an unauthenticated caller
      # fully controls the body and query string, and ANY exception escaping
      # here becomes a 500 raised from inside Rack::Attack — a free error-noise
      # generator for anyone who finds the path. Parsing attacker-controlled
      # input has more failure modes than are worth enumerating: bad JSON raises
      # ActionDispatch::Http::Parameters::ParseError, invalid UTF-8 raises
      # ActionController::BadRequest, and a malformed query string raises
      # Rack::QueryParser::ParameterTypeError — all three verified by hand
      # against this block.
      #
      # Anything we cannot key precisely still gets bounded, just coarsely: all
      # such requests share one bucket. Returning nil instead would leave
      # malformed traffic entirely unthrottled, which is the opposite of what
      # this throttle is for.
      begin
        params = ActionDispatch::Request.new(req.env).params
        account_id = params['account_id'].presence
        email = params['email'].to_s.downcase.gsub(/\s+/, '').presence
        account_id.present? && email.present? ? "#{account_id}:#{email}" : 'unkeyable'
      rescue StandardError
        'unkeyable'
      end
    end
  end

  ##-----------------------------------------------##

  ###-----------------------------------------------###
  ###-----------Widget API Throttling---------------###
  ###-----------------------------------------------###

  # Rack attack on widget APIs can be disabled by setting ENABLE_RACK_ATTACK_WIDGET_API to false
  # For clients using the widgets in specific conditions like inside and iframe
  # TODO: Deprecate this feature in future after finding a better solution
  if ActiveModel::Type::Boolean.new.cast(ENV.fetch('ENABLE_RACK_ATTACK_WIDGET_API', true))
    ## Prevent Conversation Bombing on Widget APIs ###
    throttle('api/v1/widget/conversations', limit: 6, period: 12.hours) do |req|
      req.ip if req.path_without_extentions == '/api/v1/widget/conversations' && req.post?
    end

    ## Prevent Contact update Bombing in Widget API ###
    throttle('api/v1/widget/contacts', limit: 60, period: 1.hour) do |req|
      req.ip if req.path_without_extentions == '/api/v1/widget/contacts' && (req.patch? || req.put?)
    end

    ## Prevent Conversation Bombing through multiple sessions
    throttle('widget?website_token={website_token}&cw_conversation={x-auth-token}', limit: 5, period: 1.hour) do |req|
      req.ip if req.path_without_extentions == '/widget' && ActionDispatch::Request.new(req.env).params['cw_conversation'].blank?
    end
  end

  ##-----------------------------------------------##

  ###-----------------------------------------------###
  ###----------Application API Throttling-----------###
  ###-----------------------------------------------###

  ## Prevent Abuse of Converstion Transcript APIs ###
  throttle('/api/v1/accounts/:account_id/conversations/:conversation_id/transcript',
           limit: ENV.fetch('RATE_LIMIT_CONVERSATION_TRANSCRIPT', '1000').to_i, period: 1.hour) do |req|
    match_data = %r{/api/v1/accounts/(?<account_id>\d+)/conversations/(?<conversation_id>\d+)/transcript}.match(req.path)
    match_data[:account_id] if match_data.present?
  end

  ## Prevent Abuse of attachment upload APIs ##
  throttle('/api/v1/accounts/:account_id/upload', limit: 60, period: 1.hour) do |req|
    match_data = %r{/api/v1/accounts/(?<account_id>\d+)/upload}.match(req.path)
    match_data[:account_id] if match_data.present?
  end

  ## Prevent abuse of contact search api
  throttle('/api/v1/accounts/:account_id/contacts/search', limit: ENV.fetch('RATE_LIMIT_CONTACT_SEARCH', '100').to_i, period: 1.minute) do |req|
    match_data = %r{/api/v1/accounts/(?<account_id>\d+)/contacts/search}.match(req.path)
    match_data[:account_id] if match_data.present?
  end

  # Throttle by individual user (based on uid)
  throttle('/api/v2/accounts/:account_id/reports/user', limit: ENV.fetch('RATE_LIMIT_REPORTS_API_USER_LEVEL', '100').to_i, period: 1.minute) do |req|
    match_data = %r{/api/v2/accounts/(?<account_id>\d+)/reports}.match(req.path)
    # Extract user identification (uid for web, api_access_token for API requests)
    user_uid = req.get_header('HTTP_UID')
    api_access_token = req.get_header('HTTP_API_ACCESS_TOKEN') || req.get_header('api_access_token')

    # Use uid if present, otherwise fallback to api_access_token for tracking
    user_identifier = user_uid.presence || api_access_token.presence

    "#{user_identifier}:#{match_data[:account_id]}" if match_data.present? && user_identifier.present?
  end

  ## Prevent abuse of reports api at account level
  throttle('/api/v2/accounts/:account_id/reports', limit: ENV.fetch('RATE_LIMIT_REPORTS_API_ACCOUNT_LEVEL', '1000').to_i, period: 1.minute) do |req|
    match_data = %r{/api/v2/accounts/(?<account_id>\d+)/reports}.match(req.path)
    match_data[:account_id] if match_data.present?
  end

  ## Prevent increased use of conversations meta API per user
  throttle('/api/v1/accounts/:account_id/conversations/meta/user',
           limit: ENV.fetch('RATE_LIMIT_CONVERSATIONS_META', '30').to_i, period: 1.minute) do |req|
    match_data = %r{/api/v1/accounts/(?<account_id>\d+)/conversations/meta}.match(req.path)
    next unless match_data.present? && req.get?

    user_uid = req.get_header('HTTP_UID')
    api_access_token = req.get_header('HTTP_API_ACCESS_TOKEN') || req.get_header('api_access_token')
    user_identifier = user_uid.presence || api_access_token.presence

    "#{user_identifier}:#{match_data[:account_id]}" if user_identifier.present?
  end

  ## ----------------------------------------------- ##
end

# Log blocked events
ActiveSupport::Notifications.subscribe('throttle.rack_attack') do |_name, _start, _finish, _request_id, payload|
  req = payload[:request]

  user_uid = req.get_header('HTTP_UID')
  api_access_token = req.get_header('HTTP_API_ACCESS_TOKEN') || req.get_header('api_access_token')

  # Mask the token if present
  masked_api_token = api_access_token.present? ? "#{api_access_token[0..4]}...[REDACTED]" : nil

  # Use uid if present, otherwise fallback to masked api_access_token for tracking
  user_identifier = user_uid.presence || masked_api_token.presence || 'unknown_user'

  # Extract account ID if present
  account_match = %r{/accounts/(?<account_id>\d+)}.match(req.path)
  account_id = account_match ? account_match[:account_id] : 'unknown_account'

  Rails.logger.warn(
    "[Rack::Attack][Blocked] remote_ip: \"#{req.remote_ip}\", " \
    "path: \"#{req.path}\", " \
    "user_identifier: \"#{user_identifier}\", " \
    "account_id: \"#{account_id}\", " \
    "method: \"#{req.request_method}\", " \
    "user_agent: \"#{req.user_agent}\""
  )
end

Rack::Attack.enabled = Rails.env.production? ? ActiveModel::Type::Boolean.new.cast(ENV.fetch('ENABLE_RACK_ATTACK', true)) : false
