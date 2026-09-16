require 'rails_helper'

RSpec.describe 'Conversation Messages API', type: :request do
  let!(:account) { create(:account) }

  describe 'POST /api/v1/accounts/{account.id}/conversations/<id>/messages' do
    let!(:inbox) { create(:inbox, account: account) }
    let!(:conversation) { create(:conversation, inbox: inbox, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user with access to conversation' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
      end

      it 'creates a new outgoing message' do
        params = { content: 'test-message', private: true }

        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(response).to conform_schema(200)
        expect(conversation.messages.count).to eq(1)
        expect(conversation.messages.first.content).to eq(params[:content])
      end

      it 'does not create the message' do
        params = { content: "#{'h' * 150 * 1000}a", private: true }

        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)

        json_response = response.parsed_body

        expect(json_response['error']).to eq('Validation failed: Content is too long (maximum is 150000 characters)')
      end

      it 'creates an outgoing text message with a specific bot sender' do
        agent_bot = create(:agent_bot)
        time_stamp = Time.now.utc.to_s
        params = { content: 'test-message', external_created_at: time_stamp, sender_type: 'AgentBot', sender_id: agent_bot.id }

        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        response_data = response.parsed_body
        expect(response_data['content_attributes']['external_created_at']).to eq time_stamp
        expect(conversation.messages.count).to eq(1)
        expect(conversation.messages.last.sender_id).to eq(agent_bot.id)
        expect(conversation.messages.last.content_type).to eq('text')
      end

      it 'creates a new outgoing message with attachment' do
        file = fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png')
        params = { content: 'test-message', attachments: [file] }

        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: agent.create_new_auth_token

        expect(response).to have_http_status(:success)
        expect(conversation.messages.last.attachments.first.file.present?).to be(true)
        expect(conversation.messages.last.attachments.first.file_type).to eq('image')
      end

      context 'when api inbox' do
        let(:api_channel) { create(:channel_api, account: account) }
        let(:api_inbox) { create(:inbox, channel: api_channel, account: account) }
        let(:conversation) { create(:conversation, inbox: api_inbox, account: account) }

        it 'reopens the conversation with new incoming message' do
          create(:message, conversation: conversation, account: account)
          conversation.resolved!

          params = { content: 'test-message', private: false, message_type: 'incoming' }

          post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
               params: params,
               headers: agent.create_new_auth_token,
               as: :json

          expect(response).to have_http_status(:success)
          expect(conversation.reload.status).to eq('open')
          expect(Conversations::ActivityMessageJob)
            .to(have_been_enqueued.at_least(:once)
              .with(conversation, { account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity,
                                    content: 'System reopened the conversation due to a new incoming message.' }))
        end
      end
    end

    context 'when it is an authenticated agent bot' do
      let!(:agent_bot) { create(:agent_bot) }

      it 'creates a new outgoing message' do
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        params = { content: 'test-message' }

        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: { api_access_token: agent_bot.access_token.token },
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.messages.count).to eq(1)
        expect(conversation.messages.first.content).to eq(params[:content])
      end

      it 'creates a new outgoing input select message' do
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        select_item1 = build(:bot_message_select)
        select_item2 = build(:bot_message_select)
        params = { content_type: 'input_select', content_attributes: { items: [select_item1, select_item2] } }

        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: { api_access_token: agent_bot.access_token.token },
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.messages.count).to eq(1)
        expect(conversation.messages.first.content_type).to eq(params[:content_type])
        expect(conversation.messages.first.content).to be_nil
      end

      it 'creates a new outgoing cards message' do
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        card = build(:bot_message_card)
        params = { content_type: 'cards', content_attributes: { items: [card] } }

        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: { api_access_token: agent_bot.access_token.token },
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.messages.count).to eq(1)
        expect(conversation.messages.first.content_type).to eq(params[:content_type])
      end
    end

    context 'when an agent bot sends a client_idempotency_key' do
      let!(:agent_bot) { create(:agent_bot) }
      let(:bot_headers) { { api_access_token: agent_bot.access_token.token } }
      let(:messages_url) { api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id) }

      before { create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot) }

      it 'returns the first message on a retry without creating or sending another' do
        params = { content: 'order confirmed', client_idempotency_key: 'intent-1' }
        responses = []
        # The replay is answered from the lookup, never by attempting a second insert.
        expect(Messages::MessageBuilder).to receive(:new).once.and_call_original

        expect do
          2.times do
            post messages_url, params: params, headers: bot_headers, as: :json
            responses << [response.status, response.parsed_body]
          end
        end.to have_enqueued_job(SendReplyJob).exactly(:once)

        expect(responses.map(&:first)).to eq([200, 200])
        expect(responses[1][1]['id']).to eq(responses[0][1]['id'])
        expect(responses[1][1]['client_idempotency_key']).to eq('intent-1')
        expect(conversation.messages.count).to eq(1)
        expect(conversation.messages.first.client_idempotency_key).to eq('intent-1')
      end

      it 'creates a separate message for the same key in another conversation' do
        other_conversation = create(:conversation, inbox: inbox, account: account)
        create(:message, conversation: other_conversation, account: account, inbox: inbox, client_idempotency_key: 'intent-1')
        other_account_conversation = create(:conversation)
        create(:message, conversation: other_account_conversation, account: other_account_conversation.account,
                         inbox: other_account_conversation.inbox, client_idempotency_key: 'intent-1')

        post messages_url, params: { content: 'hello', client_idempotency_key: 'intent-1' }, headers: bot_headers, as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.messages.count).to eq(1)
        expect(response.parsed_body['id']).to eq(conversation.messages.first.id)
      end

      it 'creates a message per request when the key is absent' do
        expect do
          2.times { post messages_url, params: { content: 'hello' }, headers: bot_headers, as: :json }
        end.to have_enqueued_job(SendReplyJob).exactly(:twice)

        expect(conversation.messages.count).to eq(2)
        expect(conversation.messages.pluck(:client_idempotency_key)).to eq([nil, nil])
        expect(response.parsed_body).not_to have_key('client_idempotency_key')
      end

      it 'rejects a key longer than 128 characters' do
        post messages_url, params: { content: 'hello', client_idempotency_key: 'k' * 129 }, headers: bot_headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(conversation.messages.count).to eq(0)
      end

      it 'returns the winning row when a concurrent request inserts the same key first' do
        winner = nil
        allow(Messages::MessageBuilder).to receive(:new).and_wrap_original do |original, *args|
          original.call(*args).tap do |builder|
            allow(builder).to receive(:perform).and_wrap_original do |perform|
              # The concurrent request commits between this request's lookup and its insert.
              winner = create(:message, conversation: conversation, account: account, inbox: inbox,
                                        message_type: :outgoing, client_idempotency_key: 'intent-race')
              perform.call
            end
          end
        end

        post messages_url, params: { content: 'hello', client_idempotency_key: 'intent-race' }, headers: bot_headers, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['id']).to eq(winner.id)
        expect(conversation.messages.count).to eq(1)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/conversations/<id>/messages with expected_status_revision' do
    let!(:inbox) { create(:inbox, account: account) }
    let!(:agent_bot) { create(:agent_bot) }
    let!(:conversation) { create(:conversation, inbox: inbox, account: account, status: :pending) }
    let(:bot_headers) { { api_access_token: agent_bot.access_token.token } }
    let(:messages_url) { api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id) }

    before do
      create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
      conversation.open!
      conversation.pending!
    end

    it 'creates the message under a conversation row lock when the revision still matches' do
      locking_queries = []
      callback = lambda { |*, payload|
        locking_queries << payload[:sql] if payload[:sql].match?(/FROM "conversations".*FOR UPDATE/m)
      }

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        expect do
          post messages_url, params: { content: 'your order is confirmed', expected_status_revision: 2 }, headers: bot_headers, as: :json
        end.to have_enqueued_job(SendReplyJob).exactly(:once)
      end

      expect(response).to have_http_status(:success)
      expect(conversation.messages.count).to eq(1)
      expect(locking_queries.size).to eq(1)
    end

    it 'returns 409 with the current ownership and creates nothing when the revision moved' do
      conversation.open!

      expect do
        post messages_url, params: { content: 'your order is confirmed', expected_status_revision: 2 }, headers: bot_headers, as: :json
      end.not_to have_enqueued_job(SendReplyJob)

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq('error' => 'status_revision_mismatch', 'status' => 'open', 'status_revision' => 3)
      expect(conversation.messages.count).to eq(0)
    end

    it 'replays an already-created message even after the revision moved' do
      params = { content: 'your order is confirmed', expected_status_revision: 2, client_idempotency_key: 'intent-7' }
      post messages_url, params: params, headers: bot_headers, as: :json
      first_id = response.parsed_body['id']
      conversation.open!

      post messages_url, params: params, headers: bot_headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['id']).to eq(first_id)
      expect(conversation.messages.count).to eq(1)
    end

    it 'rejects a revision that is not an integer' do
      post messages_url, params: { content: 'hello', expected_status_revision: 'two' }, headers: bot_headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(conversation.messages.count).to eq(0)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/conversations/:id/messages' do
    let(:conversation) { create(:conversation, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user with access to conversation' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
      end

      it 'shows the conversation' do
        get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response).to conform_schema(200)
        expect(JSON.parse(response.body, symbolize_names: true)[:meta][:contact][:id]).to eq(conversation.contact_id)
      end
    end

    context 'when it is an authenticated agent bot' do
      let!(:agent_bot) { create(:agent_bot) }

      it 'lists the conversation messages' do
        create(:agent_bot_inbox, inbox: conversation.inbox, agent_bot: agent_bot)

        get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
            headers: { api_access_token: agent_bot.access_token.token },
            as: :json

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/conversations/:conversation_id/messages/:id' do
    let(:message) { create(:message, account: account, content_attributes: { bcc_emails: ['hello@chatwoot.com'] }) }
    let(:conversation) { message.conversation }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user with access to conversation' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
      end

      it 'deletes the message' do
        delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(message.reload.content).to eq 'This message was deleted'
        expect(message.reload.deleted).to be true
        expect(message.reload.content_attributes['bcc_emails']).to be_nil
      end

      it 'deletes interactive messages' do
        interactive_message = create(
          :message, message_type: :outgoing, content: 'test', content_type: 'input_select',
                    content_attributes: { 'items' => [{ 'title' => 'test', 'value' => 'test' }] },
                    conversation: conversation
        )

        delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{interactive_message.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(interactive_message.reload.deleted).to be true
      end
    end

    context 'when the message id is invalid' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
      end

      it 'returns not found error' do
        delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/99999",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/conversations/:conversation_id/messages/:id/retry' do
    let(:message) { create(:message, account: account, status: :failed, content_attributes: { external_error: 'error' }) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/conversations/#{message.conversation.display_id}/messages/#{message.id}/retry"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user with access to conversation' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: message.conversation.inbox, user: agent)
      end

      it 'retries the message' do
        post "/api/v1/accounts/#{account.id}/conversations/#{message.conversation.display_id}/messages/#{message.id}/retry",
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(message.reload.status).to eq('sent')
        expect(message.reload.content_attributes['external_error']).to be_nil
      end
    end

    context 'when the message id is invalid' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: message.conversation.inbox, user: agent)
      end

      it 'returns not found error' do
        post "/api/v1/accounts/#{account.id}/conversations/#{message.conversation.display_id}/messages/99999/retry",
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/conversations/:conversation_id/messages/:id' do
    let(:api_channel) { create(:channel_api, account: account) }
    let(:api_inbox) { create(:inbox, channel: api_channel, account: account) }
    let(:agent) { create(:user, account: account, role: :agent) }
    let!(:conversation) { create(:conversation, inbox: api_inbox, account: account) }
    let!(:message) { create(:message, conversation: conversation, account: account, status: :sent) }

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        patch api_v1_account_conversation_message_url(account_id: account.id, conversation_id: conversation.display_id, id: message.id)
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated agent' do
      context 'when agent has non-API inbox' do
        let(:inbox) { create(:inbox, account: account) }
        let(:agent) { create(:user, account: account, role: :agent) }
        let!(:conversation) { create(:conversation, inbox: inbox, account: account) }

        before { create(:inbox_member, inbox: inbox, user: agent) }

        it 'returns forbidden' do
          patch api_v1_account_conversation_message_url(
            account_id: account.id,
            conversation_id: conversation.display_id,
            id: message.id
          ), params: { status: 'failed', external_error: 'err' }, headers: agent.create_new_auth_token, as: :json
          expect(response).to have_http_status(:forbidden)
        end
      end

      context 'when agent has API inbox' do
        before { create(:inbox_member, inbox: api_inbox, user: agent) }

        it 'uses StatusUpdateService to perform status update' do
          service = instance_double(Messages::StatusUpdateService)
          expect(Messages::StatusUpdateService).to receive(:new)
            .with(message, 'failed', 'err123')
            .and_return(service)
          expect(service).to receive(:perform)
          patch api_v1_account_conversation_message_url(
            account_id: account.id,
            conversation_id: conversation.display_id,
            id: message.id
          ), params: { status: 'failed', external_error: 'err123' }, headers: agent.create_new_auth_token, as: :json
        end

        it 'updates status to failed with external_error' do
          patch api_v1_account_conversation_message_url(
            account_id: account.id,
            conversation_id: conversation.display_id,
            id: message.id
          ), params: { status: 'failed', external_error: 'err123' }, headers: agent.create_new_auth_token, as: :json

          expect(response).to have_http_status(:success)
          expect(message.reload.status).to eq('failed')
          expect(message.reload.external_error).to eq('err123')
        end
      end
    end
  end
end
