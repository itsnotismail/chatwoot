# frozen_string_literal: true

# The Comvor portal is the only SAML identity provider this installation
# trusts. Its address is COMVOR_PORTAL_API_URL, the same trust anchor the
# portal password delegation uses; its signing certificate is whatever the
# portal publishes at /portal/saml/metadata.
#
# Without this pin, any account administrator could point their own
# account's SAML settings at an identity provider they run, add another
# tenant's user to their account by email, and sign in as that user.
module Comvor::PortalIdp
  SSO_PATH = '/portal/saml/sso'
  METADATA_PATH = '/portal/saml/metadata'
  CACHE_TTL = 1.hour
  OPEN_TIMEOUT = 3
  READ_TIMEOUT = 5
  REFETCH_INTERVAL = 1.minute
  REFETCH_LOCK_KEY = 'comvor:portal_idp:certificates_refetched'

  class MetadataError < StandardError; end

  module_function

  def base_url
    ENV.fetch('COMVOR_PORTAL_API_URL', '').to_s.strip.chomp('/')
  end

  def configured?
    base_url.present?
  end

  # Production always pins (and, unconfigured, refuses everything).
  # Elsewhere the pin applies once the portal address is set, so local
  # setups and specs with a test identity provider keep working.
  def enforced?
    configured? || production?
  end

  def production?
    Rails.env.production?
  end

  def sso_url
    "#{base_url}#{SSO_PATH}"
  end

  def entity_id
    "#{base_url}#{METADATA_PATH}"
  end

  # The service provider name the portal resolves an account by
  # (comvor-api samlidp/sp.go).
  def sp_entity_id_for(account_id)
    "comvor-chatwoot-account-#{account_id}"
  end

  # Whether a stored settings row names the portal, read the way the SAML
  # callback reads it. Raises MetadataError when the portal cannot be read.
  def pinned?(settings)
    settings.sso_url == sso_url &&
      settings.idp_entity_id == entity_id &&
      settings.sp_entity_id == sp_entity_id_for(settings.account_id) &&
      saml_certificate_sha256(settings.certificate) == certificate_sha256
  end

  # SHA-256 of the DER certificate the portal publishes first. Raises
  # MetadataError when the metadata cannot be read, so callers fail closed.
  def certificate_sha256
    OpenSSL::Digest::SHA256.hexdigest(OpenSSL::X509::Certificate.new(certificates.first).to_der)
  end

  # The signing certificates (PEM) the portal publishes; a key rotation
  # lists more than one. Raises MetadataError when the metadata cannot be
  # read, so callers fail closed.
  def certificates
    Rails.cache.fetch(certificates_cache_key, expires_in: CACHE_TTL) { fetch_certificates }
  end

  # Reads the metadata again after a signature failure, to pick up a key the
  # portal rotated inside the cache window. Badly signed responses are free
  # to send, so this runs at most once per REFETCH_INTERVAL for the whole
  # installation; otherwise it returns nil and the cached certificates stand.
  def refetch_certificates
    return nil unless Redis::Alfred.set(REFETCH_LOCK_KEY, 1, nx: true, ex: REFETCH_INTERVAL.to_i)

    fetch_certificates.tap { |pems| Rails.cache.write(certificates_cache_key, pems, expires_in: CACHE_TTL) }
  end

  # Whether sign-in may trust the portal at all: it is configured and, in
  # production, reached over HTTPS.
  def secure?
    configured? && (!production? || URI.parse(base_url).scheme == 'https')
  rescue URI::InvalidURIError
    false
  end

  # SHA-256 of a stored certificate as ruby-saml parses it at callback time.
  # OpenSSL and ruby-saml read a PEM with text around it differently, so the
  # pin must hash what the callback will actually verify against.
  def saml_certificate_sha256(certificate)
    return nil if certificate.blank?

    cert = OneLogin::RubySaml::Utils.build_cert_object(certificate)
    cert && OpenSSL::Digest::SHA256.hexdigest(cert.to_der)
  rescue OpenSSL::X509::CertificateError, ArgumentError
    nil
  end

  def certificates_cache_key
    "comvor:portal_idp:certificates:#{base_url}"
  end

  def fetch_certificates
    response = fetch_metadata
    raise MetadataError, "portal metadata answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    idp = OneLogin::RubySaml::IdpMetadataParser.new.parse_to_idp_metadata_array(response.body.to_s).first
    encoded = idp.certificates&.fetch('signing', nil)
    raise MetadataError, 'portal metadata has no signing certificate' if encoded.blank?

    encoded.map { |text| OpenSSL::X509::Certificate.new(Base64.decode64(text.gsub(/\s/, ''))).to_pem }
  rescue ArgumentError, REXML::ParseException, OpenSSL::X509::CertificateError => e
    raise MetadataError, "portal metadata unreadable: #{e.message}"
  end

  def fetch_metadata
    uri = URI.parse(entity_id)
    raise MetadataError, 'portal metadata must be fetched over https' if production? && uri.scheme != 'https'

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
      http.get(uri.request_uri)
    end
  rescue SocketError, SystemCallError, Timeout::Error, IOError, Net::ProtocolError, URI::InvalidURIError, OpenSSL::SSL::SSLError => e
    raise MetadataError, e.message
  end
end
