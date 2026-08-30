require 'rails_helper'

RSpec.describe Message do
  let!(:conversation) { create(:conversation) }

  it 'updates first reply if the message is human and even if there are messages from captain' do
    captain_assistant = create(:captain_assistant, account: conversation.account)
    expect(conversation.first_reply_created_at).to be_nil

    ## There is a difference on how the time is stored in the database and how it is retrieved
    # This is because of the precision of the time stored in the database
    # In the test, we will check whether the time is within the range
    expect(conversation.waiting_since).to be_within(0.000001.seconds).of(conversation.created_at)

    create(:message, message_type: :outgoing, conversation: conversation, sender: captain_assistant)

    # Captain::Assistant responses clear waiting_since (like AgentBot)
    expect(conversation.first_reply_created_at).to be_nil
    expect(conversation.waiting_since).to be_nil

    create(:message, message_type: :outgoing, conversation: conversation)

    expect(conversation.first_reply_created_at).not_to be_nil
    expect(conversation.waiting_since).to be_nil
  end

  describe '#mark_pending_conversation_as_open_for_human_response' do
    let(:conversation) { create(:conversation, status: :pending) }
    let(:captain_assistant) { create(:captain_assistant, account: conversation.account) }
    let(:auto_open_activity_content) { I18n.t('conversations.activity.captain.auto_opened_after_agent_reply', locale: conversation.account.locale) }

    before do
      create(:captain_inbox, inbox: conversation.inbox, captain_assistant: captain_assistant)
    end

    it 'marks the conversation open when a human sends a public outgoing message' do
      create(:message, message_type: :outgoing, conversation: conversation)

      expect(conversation.reload.open?).to be true
    end

    it 'creates an activity message when a human sends a public outgoing message' do
      expect do
        create(:message, message_type: :outgoing, conversation: conversation)
      end.to have_enqueued_job(Conversations::ActivityMessageJob).with(
        conversation,
        {
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id,
          message_type: :activity,
          content: auto_open_activity_content
        }
      )
    end

    it 'creates an activity message for external echo replies' do
      message = build(
        :message,
        message_type: :outgoing,
        conversation: conversation,
        content_attributes: { external_echo: true }
      )
      message.sender = nil

      expect do
        message.save!
      end.to have_enqueued_job(Conversations::ActivityMessageJob).with(
        conversation,
        {
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id,
          message_type: :activity,
          content: auto_open_activity_content
        }
      )
    end

    it 'does not mark the conversation open for private outgoing messages' do
      create(:message, message_type: :outgoing, conversation: conversation, private: true)

      expect(conversation.reload.pending?).to be true
    end

    it 'does not mark the conversation open for bot outgoing messages' do
      agent_bot = create(:agent_bot, account: conversation.account)
      create(:message, message_type: :outgoing, conversation: conversation, sender: agent_bot)

      expect(conversation.reload.pending?).to be true
    end
  end

  # Sibling to the Captain-specific describe above: this inbox has an active
  # agent bot but NO CaptainInbox, so it exercises the second arm of
  # captain_pending_conversation? (the agent-takeover clause) rather than the
  # Captain clause.
  describe '#mark_pending_conversation_as_open_for_human_response (agent bot takeover)' do
    let(:conversation) { create(:conversation, status: :pending) }

    before { create(:agent_bot_inbox, inbox: conversation.inbox, status: 'active') }

    it 'opens a bot-handled conversation when an agent replies' do
      create(:message, conversation: conversation, message_type: :outgoing, sender: create(:user))
      expect(conversation.reload.status).to eq('open')
    end

    it 'leaves it pending for a private note' do
      create(:message, conversation: conversation, message_type: :outgoing,
                        sender: create(:user), private: true)
      expect(conversation.reload.status).to eq('pending')
    end

    it "leaves it pending for the bot's own reply" do
      create(:message, conversation: conversation, message_type: :outgoing, sender: create(:agent_bot))
      expect(conversation.reload.status).to eq('pending')
    end

    # THE ONE THAT MATTERS. A bot reply carrying an image becomes TWO Meta sends
    # that overwrite each other's source_id, so the attachment's echo never
    # dedupes and returns as a new outgoing message with sender nil and
    # external_echo true. human_response? accepts that through its external_echo
    # arm, so without the sender check the bot would take the conversation over
    # from ITSELF, on the retail happy path.
    it "leaves it pending for an external echo of the bot's own message" do
      create(:message, :bot_message, conversation: conversation, message_type: :outgoing,
                        content_attributes: { external_echo: true })
      expect(conversation.reload.status).to eq('pending')
    end
  end
end
