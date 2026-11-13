# frozen_string_literal: true

# The statements /.well-known/assetlinks.json serves, which let Android
# verify https App Links (chat.comvor.com/app/...) for an app.
#
# The first statement is upstream's, unchanged: ANDROID_BUNDLE_ID with the
# one ANDROID_SHA256_CERT_FINGERPRINT. Comvor Agent gets its own statement
# when COMVOR_AGENT_ANDROID_SHA256_CERT_FINGERPRINTS lists any fingerprints,
# comma-separated, because one app needs several: the upload key, Play App
# Signing's key (known only once the Play app exists) and a debug key.
# A value that is not a SHA-256 fingerprint is left out, so one typo cannot
# break verification for the others.
module Comvor::AndroidAssetLinks
  COMVOR_AGENT_PACKAGE = 'com.comvor.agent'
  FINGERPRINT = /\A(?:[0-9A-F]{2}:){31}[0-9A-F]{2}\z/
  RELATION = ['delegate_permission/common.handle_all_urls'].freeze

  module_function

  def statements
    [statement(ENV.fetch('ANDROID_BUNDLE_ID', nil).to_s, [ENV.fetch('ANDROID_SHA256_CERT_FINGERPRINT', nil).to_s])] + comvor_agent_statements
  end

  def comvor_agent_fingerprints
    ENV.fetch('COMVOR_AGENT_ANDROID_SHA256_CERT_FINGERPRINTS', '').split(',').map { |value| value.strip.upcase }.grep(FINGERPRINT).uniq
  end

  def comvor_agent_statements
    fingerprints = comvor_agent_fingerprints
    fingerprints.empty? ? [] : [statement(COMVOR_AGENT_PACKAGE, fingerprints)]
  end

  def statement(package_name, fingerprints)
    { relation: RELATION, target: { namespace: 'android_app', package_name: package_name, sha256_cert_fingerprints: fingerprints } }
  end
end
