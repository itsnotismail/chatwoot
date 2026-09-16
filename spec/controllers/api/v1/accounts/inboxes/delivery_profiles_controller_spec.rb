require 'rails_helper'

RSpec.describe 'Inbox delivery profile API', type: :request do
  let(:account) { create(:account) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:bot_headers) { { api_access_token: agent_bot.access_token.token } }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false, message_templates: templates)
  end
  let(:inbox) { whatsapp_channel.inbox }
  let(:templates) do
    [
      {
        'name' => 'order_shipped', 'status' => 'APPROVED', 'category' => 'UTILITY', 'language' => 'en_US',
        'namespace' => 'secret_namespace_value', 'id' => '555000111', 'parameter_format' => 'POSITIONAL',
        'components' => [
          { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Order {{1}}', 'example' => { 'header_text' => ['A1'] } },
          { 'type' => 'BODY', 'text' => 'Hi {{1}}, order {{2}} ships {{1}}.', 'example' => { 'body_text' => [%w[Ali A1]] } },
          { 'type' => 'FOOTER', 'text' => 'Thanks' },
          { 'type' => 'BUTTONS', 'buttons' => [
            { 'type' => 'URL', 'text' => 'Track', 'url' => 'https://track.example.com/{{1}}' },
            { 'type' => 'QUICK_REPLY', 'text' => 'Stop' }
          ] }
        ]
      },
      {
        'name' => 'payment_reminder', 'status' => 'approved', 'category' => 'UTILITY', 'language' => 'dv', 'parameter_format' => 'NAMED',
        'components' => [
          { 'type' => 'HEADER', 'format' => 'IMAGE' },
          { 'type' => 'BODY', 'text' => 'Hello {{customer_name}}, pay {{amount}}' }
        ]
      },
      { 'name' => 'rejected_one', 'status' => 'REJECTED', 'category' => 'MARKETING', 'language' => 'en',
        'components' => [{ 'type' => 'BODY', 'text' => 'Nope {{1}}' }] },
      { 'name' => 'pending_one', 'status' => 'PENDING', 'category' => 'UTILITY', 'language' => 'en',
        'components' => [{ 'type' => 'BODY', 'text' => 'Wait' }] }
    ]
  end

  def profile_url(inbox_id, account_id: account.id)
    "/api/v1/accounts/#{account_id}/inboxes/#{inbox_id}/delivery_profile"
  end

  describe 'GET /api/v1/accounts/{account_id}/inboxes/{inbox_id}/delivery_profile' do
    it 'returns unauthorized without a token' do
      get profile_url(inbox.id)

      expect(response).to have_http_status(:unauthorized)
    end

    context 'when it is an agent bot connected to the inbox' do
      before { create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot) }

      it 'returns the channel type and only the approved templates with their variables' do
        get profile_url(inbox.id), headers: bot_headers, as: :json

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body.keys).to contain_exactly('inbox_id', 'channel_type', 'templates', 'templates_last_updated_at')
        expect(body['inbox_id']).to eq(inbox.id)
        expect(body['channel_type']).to eq('Channel::Whatsapp')
        expect(body['templates']).to eq(
          [
            {
              'name' => 'order_shipped', 'language' => 'en_US', 'category' => 'UTILITY', 'status' => 'APPROVED',
              'parameter_format' => 'POSITIONAL',
              'header' => { 'format' => 'TEXT', 'variables' => ['1'] },
              'body' => { 'variables' => %w[1 2] },
              'buttons' => [
                { 'index' => 0, 'type' => 'URL', 'variables' => ['1'] },
                { 'index' => 1, 'type' => 'QUICK_REPLY', 'variables' => [] }
              ]
            },
            {
              'name' => 'payment_reminder', 'language' => 'dv', 'category' => 'UTILITY', 'status' => 'approved',
              'parameter_format' => 'NAMED',
              'header' => { 'format' => 'IMAGE', 'variables' => [] },
              'body' => { 'variables' => %w[customer_name amount] },
              'buttons' => []
            }
          ]
        )
      end

      it 'exposes no channel configuration or provider secrets' do
        get profile_url(inbox.id), headers: bot_headers, as: :json

        raw = response.body
        [whatsapp_channel.phone_number, 'test_key', 'random_id', 'secret_namespace_value', '555000111',
         'provider_config', 'api_key', 'phone_number_id', 'webhook_verify_token', 'namespace', 'example'].each do |forbidden|
          expect(raw).not_to include(forbidden)
        end
      end

      it 'returns only the channel type for a non-WhatsApp inbox' do
        api_inbox = create(:channel_api, account: account).inbox
        create(:agent_bot_inbox, inbox: api_inbox, agent_bot: agent_bot)

        get profile_url(api_inbox.id), headers: bot_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq('inbox_id' => api_inbox.id, 'channel_type' => 'Channel::Api')
      end
    end

    context 'when it is an agent bot outside its scope' do
      it 'returns not found when the bot connection to the inbox is inactive' do
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot, status: :inactive)

        get profile_url(inbox.id), headers: bot_headers, as: :json

        expect(response).to have_http_status(:not_found)
      end

      it 'returns not found for an inbox of the same account the bot is not connected to' do
        other_inbox = create(:channel_api, account: account).inbox
        create(:agent_bot_inbox, inbox: other_inbox, agent_bot: agent_bot)

        get profile_url(inbox.id), headers: bot_headers, as: :json

        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include('order_shipped')
      end

      it 'returns not found for an inbox of another account' do
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        foreign_inbox = create(:channel_whatsapp, sync_templates: false, validate_provider_config: false).inbox

        get profile_url(foreign_inbox.id), headers: bot_headers, as: :json

        expect(response).to have_http_status(:not_found)
      end

      it 'refuses another account in the path' do
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        foreign_inbox = create(:channel_whatsapp, sync_templates: false, validate_provider_config: false).inbox

        get profile_url(foreign_inbox.id, account_id: foreign_inbox.account_id), headers: bot_headers, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an administrator of another account' do
      it 'returns not found for that account\'s inbox id under their own account path' do
        other_account = create(:account)
        admin = create(:user, account: other_account, role: :administrator)

        get profile_url(inbox.id, account_id: other_account.id), headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include('order_shipped')
      end
    end

    context 'when it is an agent' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'returns unauthorized for an inbox the agent is not a member of' do
        get profile_url(inbox.id), headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns the profile for an inbox the agent is a member of' do
        create(:inbox_member, user: agent, inbox: inbox)

        get profile_url(inbox.id), headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['templates'].pluck('name')).to eq(%w[order_shipped payment_reminder])
      end
    end
  end
end
