require 'rails_helper'

RSpec.describe Mfa::PortalTokenService do
  let(:user) { create(:user, provider: 'saml') }

  def signed_jwt(payload)
    JWT.encode(payload, Rails.application.secret_key_base, 'HS256')
  end

  describe '#generate_token' do
    it 'carries the user, a five minute expiry and the portal claim' do
      payload = JWT.decode(described_class.new(user: user).generate_token, Rails.application.secret_key_base, true,
                           algorithm: 'HS256').first

      expect(payload['user_id']).to eq(user.id)
      expect(payload['portal_totp']).to be(true)
      expect(payload['exp']).to be_within(5).of(5.minutes.from_now.to_i)
    end
  end

  describe '#verify_token' do
    it 'returns the user for a token it minted itself' do
      token = described_class.new(user: user).generate_token

      expect(described_class.new(token: token).verify_token).to eq(user)
    end

    # The whole reason this class exists. A Chatwoot-flavoured token decodes
    # perfectly here — same key, same algorithm — so only the claim keeps the two
    # kinds of challenge apart. Without this, a Chatwoot-MFA user's code would be
    # sent to the portal, or a portal user's code checked against Chatwoot's otp.
    it 'refuses a chatwoot flavoured token' do
      token = Mfa::TokenService.new(user: user).generate_token

      expect(described_class.new(token: token).verify_token).to be_nil
    end

    it 'refuses a token whose portal claim has been stripped' do
      token = signed_jwt(user_id: user.id, exp: 5.minutes.from_now.to_i)

      expect(described_class.new(token: token).verify_token).to be_nil
    end

    it 'refuses a token whose portal claim is false' do
      token = signed_jwt(user_id: user.id, exp: 5.minutes.from_now.to_i, portal_totp: false)

      expect(described_class.new(token: token).verify_token).to be_nil
    end

    it 'refuses an expired token' do
      token = signed_jwt(user_id: user.id, exp: 1.minute.ago.to_i, portal_totp: true)

      expect(described_class.new(token: token).verify_token).to be_nil
    end

    it 'refuses a token signed with somebody else key' do
      token = JWT.encode({ user_id: user.id, exp: 5.minutes.from_now.to_i, portal_totp: true }, 'not-the-key', 'HS256')

      expect(described_class.new(token: token).verify_token).to be_nil
    end

    it 'refuses garbage' do
      expect(described_class.new(token: 'not-a-jwt').verify_token).to be_nil
    end

    it 'returns nil when the user has since been deleted' do
      token = described_class.new(user: user).generate_token
      user.destroy!

      expect(described_class.new(token: token).verify_token).to be_nil
    end
  end
end
