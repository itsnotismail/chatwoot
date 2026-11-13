require 'rails_helper'

# The app a mobile deep link opens (Comvor::MobileApp). Only the scheme
# changes: the double-encoded email (see user_mobile_sso_deep_link_spec.rb)
# is the same for every app.
RSpec.describe User do
  let(:user) { create(:user, email: 'agent@example.com') }

  describe '#generate_mobile_sso_deep_link(app:)' do
    it 'opens Comvor Agent for app comvor, with the same double-encoded email' do
      link = user.generate_mobile_sso_deep_link(app: 'comvor')

      expect(link).to start_with('comvor://auth/saml?')
      expect(link).to include('email=agent%2540example.com')
      token = CGI.parse(URI.parse(link).query).fetch('sso_auth_token').first
      expect(user.valid_sso_auth_token?(token)).to be(true)
    end

    it 'opens the official app for app chatwoot, whatever MOBILE_DEEP_LINK_BASE says' do
      allow(GlobalConfigService).to receive(:load).and_call_original
      allow(GlobalConfigService).to receive(:load).with('MOBILE_DEEP_LINK_BASE', 'chatwootapp').and_return('comvor')

      expect(user.generate_mobile_sso_deep_link(app: 'chatwoot')).to start_with('chatwootapp://auth/saml?')
    end

    it 'refuses an app it does not know rather than give the default app\'s link' do
      expect { user.generate_mobile_sso_deep_link(app: 'evilapp') }.to raise_error(ArgumentError)
    end

    it 'keeps the configured default when no app is named' do
      allow(GlobalConfigService).to receive(:load).and_call_original
      allow(GlobalConfigService).to receive(:load).with('MOBILE_DEEP_LINK_BASE', 'chatwootapp').and_return('comvor')

      expect(user.generate_mobile_sso_deep_link).to start_with('comvor://auth/saml?')
      expect(user.generate_mobile_sso_deep_link(app: nil)).to start_with('comvor://auth/saml?')
    end
  end
end
