require 'rails_helper'

# The Comvor Agent app tags its FCM subscription with app_id, which routes it
# to Comvor's own Firebase project (Custom::Notification::PushNotificationService).
# Upstream's controller permits subscription_attributes open-ended, so the tag
# is stored without a controller change; this pins that.
RSpec.describe 'Notification subscription app tag', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def register(attributes)
    post '/api/v1/notification_subscriptions',
         params: { notification_subscription: { subscription_type: 'fcm', subscription_attributes: attributes } },
         headers: agent.create_new_auth_token,
         as: :json
  end

  it 'stores app_id with the FCM subscription' do
    register(push_token: 'comvor-token', device_id: 'device-1', app_id: 'com.comvor.agent')

    expect(response).to have_http_status(:success)
    subscription = agent.notification_subscriptions.find_by!(identifier: 'device-1')
    expect(subscription.subscription_attributes).to include('app_id' => 'com.comvor.agent', 'push_token' => 'comvor-token')
    expect(response.parsed_body.dig('subscription_attributes', 'app_id')).to eq('com.comvor.agent')
  end

  it 'drops the tag when the same device re-registers without it (official app on that device)' do
    register(push_token: 'comvor-token', device_id: 'device-1', app_id: 'com.comvor.agent')
    register(push_token: 'official-token', device_id: 'device-1')

    subscription = agent.notification_subscriptions.find_by!(identifier: 'device-1')
    expect(subscription.subscription_attributes).not_to have_key('app_id')
    expect(subscription.subscription_attributes['push_token']).to eq('official-token')
  end
end
