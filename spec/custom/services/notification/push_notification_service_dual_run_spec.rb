require 'rails_helper'

# Comvor dual-run push (Custom::Notification::PushNotificationService). Stubbed
# at the HTTP boundary only: Google's OAuth token endpoint, the FCM v1
# messages:send endpoint and the Chatwoot hub. The FCM v1 request and error
# shapes are Google's (https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages/send,
# https://firebase.google.com/docs/reference/fcm/rest/v1/ErrorCode); the fcm
# gem (1.0.8) posts { message: ... } and returns the raw body for a non-200.
RSpec.describe Notification::PushNotificationService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:notification) { create(:notification, user: user, account: account) }

  let(:project_id) { 'comvor-agent-test' }
  # A throwaway key made per run, so googleauth can sign its JWT grant. Not a
  # real credential; the token endpoint it talks to is stubbed.
  let(:service_account_json) do
    {
      type: 'service_account',
      project_id: project_id,
      private_key_id: 'test-key-id',
      private_key: OpenSSL::PKey::RSA.new(2048).to_pem,
      client_email: "push@#{project_id}.iam.gserviceaccount.com",
      client_id: '1',
      token_uri: google_token_url
    }.to_json
  end

  # googleauth 1.11.2 signs its JWT grant for this endpoint (Google::Auth::ServiceAccountCredentials::TOKEN_CRED_URI).
  let(:google_token_url) { 'https://www.googleapis.com/oauth2/v4/token' }
  let(:fcm_send_url) { "https://fcm.googleapis.com/v1/projects/#{project_id}/messages:send" }
  let(:hub_url) { ChatwootHub.push_notification_url }

  let(:comvor_subscription) do
    create(:notification_subscription, :fcm, user: user, identifier: 'comvor-device',
                                             subscription_attributes: { push_token: 'comvor-token', device_id: 'comvor-device',
                                                                        app_id: 'com.comvor.agent' })
  end
  let(:official_subscription) do
    create(:notification_subscription, :fcm, user: user, identifier: 'official-device',
                                             subscription_attributes: { push_token: 'official-token', device_id: 'official-device' })
  end

  before do
    stub_request(:post, google_token_url)
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                 body: { access_token: 'test-access-token', expires_in: 3599, token_type: 'Bearer' }.to_json)
    stub_request(:post, fcm_send_url)
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                 body: { name: "projects/#{project_id}/messages/0:1700000000000000%abc" }.to_json)
    stub_request(:post, hub_url).to_return(status: 200, body: '{}')
  end

  def with_firebase_config(present, absent_value: nil)
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('FIREBASE_PROJECT_ID', nil).and_return(present ? project_id : absent_value)
    allow(GlobalConfigService).to receive(:load).with('FIREBASE_CREDENTIALS', nil).and_return(present ? service_account_json : absent_value)
  end

  def fcm_send_to(token)
    a_request(:post, fcm_send_url).with do |req|
      body = JSON.parse(req.body)
      req.headers['Authorization'] == 'Bearer test-access-token' && body.dig('message', 'token') == token
    end
  end

  def hub_send_to(token)
    a_request(:post, hub_url).with { |req| JSON.parse(req.body).dig('fcm_options', 'token') == token }
  end

  def fcm_v1_error(code:, status:, error_code: nil)
    details = error_code ? [{ '@type' => 'type.googleapis.com/google.firebase.fcm.v1.FcmError', 'errorCode' => error_code }] : []
    { status: code, headers: { 'Content-Type' => 'application/json' },
      body: { error: { code: code, message: 'test', status: status, details: details } }.to_json }
  end

  def perform
    described_class.new(notification: notification).perform
  end

  context 'when the Firebase config is absent (today\'s behaviour)' do
    before { with_firebase_config(false) }

    it 'sends every FCM subscription, tagged or not, through the hub and never calls FCM' do
      with_modified_env ENABLE_PUSH_RELAY_SERVER: 'true' do
        comvor_subscription
        official_subscription
        perform
      end

      expect(hub_send_to('official-token')).to have_been_made.once
      expect(hub_send_to('comvor-token')).to have_been_made.once
      expect(a_request(:post, fcm_send_url)).not_to have_been_made
      expect(a_request(:post, google_token_url)).not_to have_been_made
    end

    it 'sends nothing when the relay is off too' do
      with_modified_env ENABLE_PUSH_RELAY_SERVER: 'false' do
        comvor_subscription
        official_subscription
        perform
      end

      expect(a_request(:post, hub_url)).not_to have_been_made
      expect(a_request(:post, fcm_send_url)).not_to have_been_made
    end
  end

  context 'when the Firebase config was cleared to blank in Super Admin while the env var is still set' do
    # GlobalConfigService.load then returns '' (see global_config_service_firebase_spec.rb).
    before { with_firebase_config(false, absent_value: '') }

    it 'treats it as absent and sends through the hub' do
      with_modified_env ENABLE_PUSH_RELAY_SERVER: 'true' do
        comvor_subscription
        official_subscription
        perform
      end

      expect(hub_send_to('official-token')).to have_been_made.once
      expect(hub_send_to('comvor-token')).to have_been_made.once
      expect(a_request(:post, fcm_send_url)).not_to have_been_made
    end
  end

  context 'when the Firebase config is present and the relay is on (dual run)' do
    before { with_firebase_config(true) }

    around { |example| with_modified_env(ENABLE_PUSH_RELAY_SERVER: 'true') { example.run } }

    it 'sends the Comvor app subscription direct over FCM v1 and the official app subscription through the hub' do
      comvor_subscription
      official_subscription
      perform

      expect(fcm_send_to('comvor-token')).to have_been_made.once
      expect(hub_send_to('official-token')).to have_been_made.once
      expect(fcm_send_to('official-token')).not_to have_been_made
      expect(hub_send_to('comvor-token')).not_to have_been_made
    end

    it 'sends the FCM v1 message shape upstream builds' do
      comvor_subscription
      perform

      expect(a_request(:post, fcm_send_url).with do |req|
        message = JSON.parse(req.body)['message']
        message['notification'] == { 'title' => notification.push_message_title, 'body' => notification.push_message_body } &&
          message['android'] == { 'priority' => 'high' } && message.dig('data', 'payload').present?
      end).to have_been_made.once
    end

    it 'routes an app_id other than com.comvor.agent to the hub' do
      official_subscription.update!(subscription_attributes: official_subscription.subscription_attributes.merge('app_id' => 'com.chatwoot.app'))
      perform

      expect(hub_send_to('official-token')).to have_been_made.once
      expect(a_request(:post, fcm_send_url)).not_to have_been_made
    end

    it 'still pushes through the hub when the direct send raises' do
      stub_request(:post, fcm_send_url).to_raise(Faraday::ConnectionFailed.new('connection reset'))
      comvor_subscription
      official_subscription

      expect { perform }.not_to raise_error
      expect(hub_send_to('official-token')).to have_been_made.once
      expect(NotificationSubscription.exists?(comvor_subscription.id)).to be(true)
    end

    it 'leaves browser push alone' do
      allow(WebPush).to receive(:payload_send).and_return(true)
      with_modified_env VAPID_PUBLIC_KEY: 'test' do
        create(:notification_subscription, :browser_push, user: user)
        perform
      end

      expect(WebPush).to have_received(:payload_send).once
      expect(a_request(:post, fcm_send_url)).not_to have_been_made
      expect(a_request(:post, hub_url)).not_to have_been_made
    end
  end

  context 'when the Firebase config is present and the relay is off (upstream direct-only setup)' do
    before { with_firebase_config(true) }

    it 'sends every FCM subscription direct, as upstream does' do
      with_modified_env ENABLE_PUSH_RELAY_SERVER: 'false' do
        comvor_subscription
        official_subscription
        perform
      end

      expect(fcm_send_to('comvor-token')).to have_been_made.once
      expect(fcm_send_to('official-token')).to have_been_made.once
      expect(a_request(:post, hub_url)).not_to have_been_made
    end
  end

  describe 'FCM v1 errors on the direct path' do
    before { with_firebase_config(true) }

    around { |example| with_modified_env(ENABLE_PUSH_RELAY_SERVER: 'true') { example.run } }

    it 'removes the subscription on UNREGISTERED (404 NOT_FOUND)' do
      stub_request(:post, fcm_send_url).to_return(fcm_v1_error(code: 404, status: 'NOT_FOUND', error_code: 'UNREGISTERED'))
      comvor_subscription
      perform

      expect(NotificationSubscription.exists?(comvor_subscription.id)).to be(false)
    end

    it 'removes the subscription on SENDER_ID_MISMATCH (403 PERMISSION_DENIED)' do
      stub_request(:post, fcm_send_url).to_return(fcm_v1_error(code: 403, status: 'PERMISSION_DENIED', error_code: 'SENDER_ID_MISMATCH'))
      comvor_subscription
      perform

      expect(NotificationSubscription.exists?(comvor_subscription.id)).to be(false)
    end

    {
      'UNAVAILABLE (503)' => [503, 'UNAVAILABLE', 'UNAVAILABLE'],
      'INTERNAL (500)' => [500, 'INTERNAL', 'INTERNAL'],
      'QUOTA_EXCEEDED (429)' => [429, 'RESOURCE_EXHAUSTED', 'QUOTA_EXCEEDED'],
      'INVALID_ARGUMENT (400)' => [400, 'INVALID_ARGUMENT', 'INVALID_ARGUMENT'],
      'THIRD_PARTY_AUTH_ERROR (401)' => [401, 'UNAUTHENTICATED', 'THIRD_PARTY_AUTH_ERROR'],
      'a 404 with no FcmError detail (wrong project id)' => [404, 'NOT_FOUND', nil],
      'a 403 with no FcmError detail (service account lacks permission)' => [403, 'PERMISSION_DENIED', nil]
    }.each do |label, (code, status, error_code)|
      it "keeps the subscription on #{label}" do
        stub_request(:post, fcm_send_url).to_return(fcm_v1_error(code: code, status: status, error_code: error_code))
        comvor_subscription
        perform

        expect(NotificationSubscription.exists?(comvor_subscription.id)).to be(true)
      end
    end

    it 'reads the errorCode only from the FcmError detail' do
      response = fcm_v1_error(code: 404, status: 'NOT_FOUND')
      response[:body] = JSON.parse(response[:body]).tap do |body|
        body['error']['details'] = [{ '@type' => 'type.googleapis.com/google.rpc.ErrorInfo', 'errorCode' => 'UNREGISTERED' }]
      end.to_json
      stub_request(:post, fcm_send_url).to_return(response)
      comvor_subscription
      perform

      expect(NotificationSubscription.exists?(comvor_subscription.id)).to be(true)
    end

    it 'keeps the subscription on a non-JSON 502 from a proxy' do
      stub_request(:post, fcm_send_url).to_return(status: 502, body: '<html>Bad Gateway</html>')
      comvor_subscription
      perform

      expect(NotificationSubscription.exists?(comvor_subscription.id)).to be(true)
    end

    it 'logs a 200 as sent and keeps the subscription' do
      allow(Rails.logger).to receive(:info)
      comvor_subscription
      perform

      expect(Rails.logger).to have_received(:info).with("FCM push sent to #{user.email} with title #{notification.push_message_title}")
      expect(NotificationSubscription.exists?(comvor_subscription.id)).to be(true)
    end
  end
end
