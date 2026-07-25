require 'rails_helper'

RSpec.describe SsoAuthenticatable do
  let(:user) { create(:user, email: 'agent@example.com') }

  describe '#generate_mobile_sso_deep_link' do
    it 'uses the configured mobile deep link scheme' do
      link = user.generate_mobile_sso_deep_link

      expect(link).to start_with('chatwootapp://auth/saml?')
    end

    # The email is url_encoded and then re-encoded by to_query. This DOUBLE
    # encoding is the shape of the link verified end-to-end on a real Android
    # device (2026-07-25) — the app decodes twice. Do not "fix" it here without
    # re-verifying on a physical device and updating both call sites.
    it 'double-encodes the email, matching the shape proven on device' do
      link = user.generate_mobile_sso_deep_link

      expect(link).to include('email=agent%2540example.com')
    end

    it 'carries a freshly minted, valid sso_auth_token' do
      link = user.generate_mobile_sso_deep_link
      token = CGI.parse(URI.parse(link).query).fetch('sso_auth_token').first

      expect(user.valid_sso_auth_token?(token)).to be(true)
    end

    it 'mints a distinct token on each call' do
      first = user.generate_mobile_sso_deep_link
      second = user.generate_mobile_sso_deep_link

      expect(first).not_to eq(second)
    end
  end
end
