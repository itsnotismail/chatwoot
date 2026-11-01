# frozen_string_literal: true

# Builds what the Comvor portal (crewjam/saml) sends: a SAML response whose
# assertion and/or response element is signed with a throwaway key, plus the
# portal metadata that publishes the matching certificate(s).
module ComvorSamlHelpers
  PORTAL = 'https://portal.example.test'
  FRONTEND = 'https://chat.example.test'

  module_function

  def key_and_certificate
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = SecureRandom.random_number(2**64)
    cert.subject = OpenSSL::X509::Name.parse('/CN=portal.example.test')
    cert.issuer = cert.subject
    cert.public_key = key.public_key
    cert.not_before = 1.day.ago
    cert.not_after = 1.year.from_now
    cert.sign(key, OpenSSL::Digest.new('SHA256'))
    [key, cert]
  end

  def metadata_xml(*certificates)
    key_descriptors = certificates.map do |cert|
      <<~XML
        <md:KeyDescriptor use="signing"><ds:KeyInfo><ds:X509Data>
          <ds:X509Certificate>#{Base64.strict_encode64(cert.to_der)}</ds:X509Certificate>
        </ds:X509Data></ds:KeyInfo></md:KeyDescriptor>
      XML
    end
    <<~XML
      <md:EntityDescriptor xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata" xmlns:ds="http://www.w3.org/2000/09/xmldsig#" entityID="#{PORTAL}/portal/saml/metadata">
        <md:IDPSSODescriptor protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">
          #{key_descriptors.join}
          <md:SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect" Location="#{PORTAL}/portal/saml/sso"/>
        </md:IDPSSODescriptor>
      </md:EntityDescriptor>
    XML
  end

  def acs_for(account_id)
    "#{FRONTEND}/omniauth/comvor_saml/callback?account_id=#{account_id}"
  end

  # Defaults are the values the portal sends for account_id; override any of
  # them to build the response an attacker or a misconfiguration would send.
  def saml_response(key:, cert:, account_id:, **overrides)
    values = {
      email: 'agent@example.com', issuer: "#{PORTAL}/portal/saml/metadata",
      audiences: ["comvor-chatwoot-account-#{account_id}"], destination: acs_for(account_id), recipient: acs_for(account_id),
      assertion_id: "id-#{SecureRandom.hex(20)}", not_on_or_after: 90.seconds.from_now, confirmation_not_on_or_after: 90.seconds.from_now,
      sign_assertion: true, sign_response: true
    }.merge(overrides)

    assertion = assertion_xml(values)
    assertion = sign(assertion, key, cert) if values[:sign_assertion]
    response = response_xml(values, assertion)
    response = sign(response, key, cert) if values[:sign_response]
    Base64.strict_encode64(response)
  end

  # An XML attribute, or nothing when the value is nil.
  def xml_attribute(name, value)
    value = value.utc.iso8601 if value.respond_to?(:utc)
    value.nil? ? '' : " #{name}=#{value.to_s.encode(xml: :attr)}"
  end

  def audience_xml(audiences)
    return '' if audiences.nil?

    "<saml:AudienceRestriction>#{audiences.map { |a| "<saml:Audience>#{a}</saml:Audience>" }.join}</saml:AudienceRestriction>"
  end

  def assertion_xml(values)
    now = Time.now.utc
    <<~XML.squish.gsub('> <', '><')
      <saml:Assertion xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol"
        ID="#{values[:assertion_id]}" Version="2.0" IssueInstant="#{now.iso8601}">
        <saml:Issuer>#{values[:issuer]}</saml:Issuer>
        <saml:Subject>
          <saml:NameID Format="urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress">#{values[:email]}</saml:NameID>
          <saml:SubjectConfirmation Method="urn:oasis:names:tc:SAML:2.0:cm:bearer">
            <saml:SubjectConfirmationData#{xml_attribute('NotOnOrAfter', values[:confirmation_not_on_or_after])}#{xml_attribute('Recipient', values[:recipient])}/>
          </saml:SubjectConfirmation>
        </saml:Subject>
        <saml:Conditions NotBefore="#{(now - 30).iso8601}"#{xml_attribute('NotOnOrAfter', values[:not_on_or_after])}>#{audience_xml(values[:audiences])}</saml:Conditions>
        <saml:AuthnStatement AuthnInstant="#{now.iso8601}" SessionIndex="_session">
          <saml:AuthnContext>
            <saml:AuthnContextClassRef>urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport</saml:AuthnContextClassRef>
          </saml:AuthnContext>
        </saml:AuthnStatement>
      </saml:Assertion>
    XML
  end

  def response_xml(values, assertion)
    <<~XML.squish.gsub('> <', '><')
      <samlp:Response xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion"
        ID="id-#{SecureRandom.hex(20)}" Version="2.0" IssueInstant="#{Time.now.utc.iso8601}"#{xml_attribute('Destination', values[:destination])}>
        <saml:Issuer>#{values[:issuer]}</saml:Issuer>
        <samlp:Status><samlp:StatusCode Value="urn:oasis:names:tc:SAML:2.0:status:Success"/></samlp:Status>
        #{assertion}
      </samlp:Response>
    XML
  end

  def sign(xml, key, cert)
    document = XMLSecurity::Document.new(xml)
    document.sign_document(key, cert, XMLSecurity::Document::RSA_SHA256, XMLSecurity::Document::SHA256)
    document.to_s
  end
end
