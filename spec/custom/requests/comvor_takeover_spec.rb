require 'rails_helper'

# Behaviour H, merchant takeover, through the API: an agent's reply on a
# conversation the agent bot holds hands it to the agent, and the bot's
# expected_status_revision guard then refuses what the bot had queued.
RSpec.describe 'Comvor: merchant takeover', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:inbox) { create(:inbox, account: account) }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot, status: 'active')
  end

  # Ported from spec/enterprise/controllers/api/v1/accounts/conversations_controller_spec.rb.
  describe 'POST /api/v1/accounts/{account.id}/conversations with an initial agent message in a bot inbox' do
    let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: create(:contact, account: account)) }

    # The conversation is created (pending, bot inbox) and then taken over by the agent's message in the same
    # transaction, so the takeover's own conversation instance never gets commit callbacks.
    it 'dispatches the takeover status events exactly once at status_revision 1' do
      events = []
      allow(Rails.configuration.dispatcher).to receive(:dispatch) do |event, _time, data|
        events << [event, data[:conversation]&.status, data[:conversation]&.status_revision] if data[:conversation]
      end

      post "/api/v1/accounts/#{account.id}/conversations",
           headers: agent.create_new_auth_token,
           params: { source_id: contact_inbox.source_id, message: { content: 'hi, a human here' } },
           as: :json

      expect(response).to have_http_status(:success)
      conversation = account.conversations.find_by(display_id: response.parsed_body['id'])
      expect(conversation.slice(:status, :status_revision)).to eq('status' => 'open', 'status_revision' => 1)
      expect(events.select { |event| event.first == Conversation::CONVERSATION_OPENED }).to eq([[Conversation::CONVERSATION_OPENED, 'open', 1]])
      expect(events.select { |event| event.first == Conversation::CONVERSATION_STATUS_CHANGED })
        .to eq([[Conversation::CONVERSATION_STATUS_CHANGED, 'open', 1]])
    end
  end

  describe 'a bot reply queued before the takeover' do
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let(:messages_url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages" }
    let(:bot_headers) { { api_access_token: agent_bot.access_token.token } }

    before { create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming) }

    # The bot reads the revision, the agent replies, and only then does the
    # bot's reply arrive: it carries the revision from before the takeover.
    it 'is refused by the revision guard, and the agent holds the conversation' do
      get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/reply_eligibility", headers: bot_headers, as: :json
      expect(response.parsed_body).to include('status' => 'pending')
      seen_revision = response.parsed_body['status_revision']

      post messages_url, params: { content: 'a human here, I will sort it out' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)

      expect do
        post messages_url, params: { content: 'your order is confirmed', expected_status_revision: seen_revision }, headers: bot_headers, as: :json
      end.not_to change(Message, :count)

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq('error' => 'status_revision_mismatch', 'status' => 'open', 'status_revision' => seen_revision + 1)
      expect(conversation.reload.slice(:status, :assignee_id, :assignee_agent_bot_id))
        .to eq('status' => 'open', 'assignee_id' => agent.id, 'assignee_agent_bot_id' => nil)
    end

    it 'goes through when no agent replied in between' do
      get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/reply_eligibility", headers: bot_headers, as: :json
      seen_revision = response.parsed_body['status_revision']

      post messages_url, params: { content: 'your order is confirmed', expected_status_revision: seen_revision }, headers: bot_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(conversation.reload.status).to eq('pending')
    end
  end
end
