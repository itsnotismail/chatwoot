# frozen_string_literal: true

# The origins (scheme, host, port) the Comvor portal answers on, as set in
# the environment: its web address and its API address. The workspace
# sign-out may send a browser back to these and nowhere else.
module Comvor::PortalOrigins
  module_function

  # In production only the https ones.
  def allowed
    [Comvor::PortalIdp.web_url, Comvor::PortalIdp.base_url].filter_map { |url| of(url) }.uniq
  end

  # The origin of an absolute http(s) URL, or nil when it is none, carries
  # userinfo, or (in production) is not https.
  def of(url)
    uri = URI.parse(url.to_s)
    return nil unless usable?(uri)

    port = ":#{uri.port}" unless uri.port == uri.default_port
    "#{uri.scheme}://#{uri.host.downcase}#{port}"
  rescue URI::InvalidURIError
    nil
  end

  def usable?(uri)
    return false unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?

    !Comvor::PortalIdp.production? || uri.is_a?(URI::HTTPS)
  end
end
