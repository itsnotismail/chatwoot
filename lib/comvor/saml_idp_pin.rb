# frozen_string_literal: true

# Validates an account's SAML settings against the Comvor portal (see
# Comvor::PortalIdp). Mixed into AccountSamlSettings by
# config/initializers/comvor_saml_idp_pin.rb, so no enterprise file changes.
module Comvor::SamlIdpPin
  extend ActiveSupport::Concern

  PINNED_ATTRIBUTES = %w[sso_url idp_entity_id sp_entity_id certificate].freeze

  included do
    before_validation :comvor_canonicalize_certificate, if: -> { Comvor::PortalIdp.enforced? }
    validate :comvor_portal_idp_pinned, if: :comvor_idp_fields_changing?
  end

  private

  # Store exactly one clean PEM, so nothing around the certificate can be
  # read one way here and another way at callback time.
  def comvor_canonicalize_certificate
    return if certificate.blank?

    self.certificate = OpenSSL::X509::Certificate.new(certificate).to_pem
  rescue OpenSSL::X509::CertificateError
    nil
  end

  def comvor_idp_fields_changing?
    return false unless Comvor::PortalIdp.enforced?

    new_record? || PINNED_ATTRIBUTES.any? { |attribute| will_save_change_to_attribute?(attribute) }
  end

  def comvor_portal_idp_pinned
    unless Comvor::PortalIdp.configured?
      errors.add(:base, 'SAML settings are managed by the Comvor portal')
      return
    end

    errors.add(:sso_url, 'must be the Comvor portal') unless sso_url == Comvor::PortalIdp.sso_url
    errors.add(:idp_entity_id, 'must be the Comvor portal') unless idp_entity_id == Comvor::PortalIdp.entity_id
    errors.add(:sp_entity_id, 'must be the Comvor portal name for this account') unless sp_entity_id == Comvor::PortalIdp.sp_entity_id_for(account_id)
    comvor_certificate_pinned
  end

  def comvor_certificate_pinned
    expected = Comvor::PortalIdp.certificate_sha256
    actual = Comvor::PortalIdp.saml_certificate_sha256(certificate)
    errors.add(:certificate, 'must be the Comvor portal certificate') unless actual == expected
  rescue Comvor::PortalIdp::MetadataError => e
    Rails.logger.warn("comvor: SAML settings refused, portal metadata unreadable: #{e.message}")
    errors.add(:certificate, 'could not be checked against the Comvor portal')
  end
end
