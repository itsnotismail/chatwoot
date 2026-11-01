# frozen_string_literal: true

# An account's SAML settings row. To the Comvor sign-in (the comvor_saml
# strategy) the row only means "SSO is enabled for this account": the
# identity provider is always Comvor::PortalIdp, never what the row says.
# Writes are still pinned to the portal, so the row cannot drift from it.
#
# Shares account_saml_settings with enterprise's model while enterprise is
# present. Creating a row converts nobody: users become provider 'saml' one
# at a time, at their first SSO sign-in. Deleting it puts the account's
# users back on password sign-in (Comvor::SamlProviderResetJob).
class Comvor::SamlSetting < ApplicationRecord
  include Comvor::SamlIdpPin

  self.table_name = 'account_saml_settings'

  # A custom role id as role_mappings may carry it in a string: decimal, no
  # leading zero, so it reads as the same number everywhere.
  CUSTOM_ROLE_ID = /\A[1-9]\d*\z/
  MAX_ID = (2**63) - 1 # custom_roles.id is a bigint

  belongs_to :account

  # An account's row(s), oldest first. The table has no unique index, so
  # every reader takes the same one (for_account) and DELETE takes them all.
  scope :of_account, ->(account_id) { where(account_id: account_id).order(:id) }

  before_validation :normalize_custom_role_ids, if: :role_mappings_changing?
  validates :sso_url, :certificate, :idp_entity_id, presence: true
  validate :certificate_is_x509, if: -> { certificate.present? }
  validate :custom_roles_of_this_account, if: :role_mappings_changing?

  after_destroy_commit { Comvor::SamlProviderResetJob.perform_later(account_id) }

  def self.for_account(account_id)
    of_account(account_id).first
  end

  # The certificate's SHA-1, as the dashboard shows it (AA:BB:...).
  def certificate_fingerprint
    return nil if certificate.blank?

    OpenSSL::Digest::SHA1.hexdigest(OpenSSL::X509::Certificate.new(certificate).to_der).upcase.scan(/../).join(':')
  rescue OpenSSL::X509::CertificateError
    nil
  end

  private

  def role_mappings_changing?
    new_record? || will_save_change_to_role_mappings?
  end

  # Stores a custom role id given as a string as the Integer it names, so
  # the id checked below is the id Comvor::SamlUserBuilder hands out.
  def normalize_custom_role_ids
    return unless role_mappings.is_a?(Hash)

    self.role_mappings = role_mappings.to_h.transform_values do |mapping|
      next mapping unless mapping.is_a?(Hash)

      mapping = mapping.to_h.stringify_keys
      id = mapping['custom_role_id']
      mapping['custom_role_id'] = id.to_i if id.is_a?(String) && id.match?(CUSTOM_ROLE_ID)
      mapping
    end
  end

  def certificate_is_x509
    OpenSSL::X509::Certificate.new(certificate)
  rescue OpenSSL::X509::CertificateError
    errors.add(:certificate, 'is not a valid X.509 certificate')
  end

  # A mapping may hand new users a custom role (Comvor::SamlUserBuilder);
  # it must be one of this account's. custom_roles is queried as a table,
  # because its model is enterprise's.
  def custom_roles_of_this_account
    ids = mapped_custom_role_ids
    return if ids.empty?
    return if ids.all? { |id| id.is_a?(Integer) && id.between?(1, MAX_ID) } && (ids.uniq - custom_role_ids_in_account(ids)).empty?

    errors.add(:role_mappings, 'must name custom roles of this account')
  end

  def mapped_custom_role_ids
    mappings = role_mappings.is_a?(Hash) ? role_mappings.values : []
    mappings.filter_map { |mapping| mapping.to_h.stringify_keys['custom_role_id'] if mapping.is_a?(Hash) }
  end

  def custom_role_ids_in_account(ids)
    roles = Arel::Table.new(:custom_roles)
    query = roles.project(roles[:id]).where(roles[:account_id].eq(account_id).and(roles[:id].in(ids)))
    self.class.connection.select_values(query)
  end
end
