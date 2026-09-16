require 'rails_helper'

RSpec.describe 'Conversation reply eligibility API', type: :request do
  let(:account) { create(:account) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:bot_headers) { { api_access_token: agent_bot.access_token.token } }
  let(:inbox) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  def eligibility_url(conv, account_id: account.id)
    "/api/v1/accounts/#{account_id}/conversations/#{conv.display_id}/reply_eligibility"
  end

  describe 'GET /api/v1/accounts/{account_id}/conversations/{conversation_id}/reply_eligibility' do
    it 'returns unauthorized without a token' do
      get eligibility_url(conversation)

      expect(response).to have_http_status(:unauthorized)
    end

    context 'when it is an agent bot connected to the inbox' do
      before { create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot) }

      it 'returns exactly the eligibility fields inside the WhatsApp window' do
        incoming = create(:message, message_type: :incoming, conversation: conversation, account: account, inbox: inbox, created_at: 2.hours.ago)
        create(:message, message_type: :outgoing, conversation: conversation, account: account, inbox: inbox)
        conversation.update!(status: :pending)

        get eligibility_url(conversation), headers: bot_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq(
          'channel' => 'Channel::Whatsapp',
          'can_reply' => true,
          'status' => 'pending',
          'status_revision' => conversation.reload.status_revision,
          'last_incoming_at' => incoming.reload.created_at.iso8601(6)
        )
        expect(response.parsed_body['status_revision']).to be_positive
      end

      it 'reports can_reply false once the last incoming message is older than the WhatsApp window' do
        create(:message, message_type: :incoming, conversation: conversation, account: account, inbox: inbox, created_at: 25.hours.ago)

        get eligibility_url(conversation), headers: bot_headers, as: :json

        expect(response.parsed_body['can_reply']).to be(false)
        expect(response.parsed_body['last_incoming_at']).to be_present
      end

      it 'reports can_reply false and a null last_incoming_at when the customer never wrote' do
        get eligibility_url(conversation), headers: bot_headers, as: :json

        expect(response.parsed_body).to include('can_reply' => false, 'last_incoming_at' => nil)
      end
    end

    context 'when it is an agent bot outside its scope' do
      it 'returns not found for a conversation in an inbox the bot is not connected to' do
        create(:agent_bot_inbox, inbox: create(:channel_api, account: account).inbox, agent_bot: agent_bot)

        get eligibility_url(conversation), headers: bot_headers, as: :json

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body.keys).to eq(['error'])
      end

      it 'returns not found for a conversation of another account' do
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        foreign = create(:conversation)
        foreign.update_column(:display_id, conversation.display_id + 1000) # rubocop:disable Rails/SkipsModelValidations

        get "/api/v1/accounts/#{account.id}/conversations/#{foreign.display_id}/reply_eligibility", headers: bot_headers, as: :json

        expect(response).to have_http_status(:not_found)
      end

      it 'refuses another account in the path' do
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        foreign = create(:conversation)

        get eligibility_url(foreign, account_id: foreign.account_id), headers: bot_headers, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an administrator' do
      it 'returns the eligibility without a bot connection' do
        admin = create(:user, account: account, role: :administrator)

        get eligibility_url(conversation), headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['channel']).to eq('Channel::Whatsapp')
      end
    end
  end
end
