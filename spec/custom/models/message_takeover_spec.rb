require 'rails_helper'

# Behaviour H, merchant takeover: a human's public reply on a conversation the
# agent bot holds hands it to that human (Custom::Message, Custom::Conversation).
# The examples down to the external echo are ported from
# spec/enterprise/models/message_spec.rb, so they hold with enterprise/ removed.
RSpec.describe Message do
  describe '#mark_pending_conversation_as_open_for_human_response (agent bot takeover)' do
    let(:conversation) { create(:conversation, status: :pending) }

    before { create(:agent_bot_inbox, inbox: conversation.inbox, status: 'active') }

    it 'opens a bot-handled conversation when an agent replies' do
      create(:message, conversation: conversation, message_type: :outgoing, sender: create(:user))
      expect(conversation.reload.status).to eq('open')
    end

    it 'advances the status revision when an agent reply takes the conversation over' do
      expect do
        create(:message, conversation: conversation, message_type: :outgoing, sender: create(:user))
      end.to change { conversation.reload.status_revision }.by(1)
    end

    it 'opens the conversation and bumps its revision inside the reply transaction, before commit' do
      in_transaction = nil

      ActiveRecord::Base.transaction do
        create(:message, conversation: conversation, message_type: :outgoing, sender: create(:user))
        in_transaction = Conversation.where(id: conversation.id).pick(:status, :status_revision)
        expect(Conversations::ActivityMessageJob).not_to have_been_enqueued
      end

      expect(in_transaction).to eq(['open', 1])
      expect(Conversations::ActivityMessageJob).to have_been_enqueued.exactly(:once)
    end

    it 'runs the takeover as the system and dispatches its status webhooks exactly once, before message_created' do
      agent = create(:user, account: conversation.account)
      agent_bot = create(:agent_bot, outgoing_url: 'https://bot.example.com/webhook')
      create(:agent_bot_inbox, inbox: conversation.inbox, agent_bot: agent_bot)
      events = []
      allow(AgentBots::WebhookJob).to receive(:perform_later) do |_url, payload, *|
        conversation_data = payload[:conversation] || payload
        events << [payload[:event], conversation_data[:status], conversation_data[:status_revision]]
      end

      Current.user = agent
      expect do
        create(:message, conversation: conversation, message_type: :outgoing, sender: agent)
      end.to have_enqueued_job(Conversations::ActivityMessageJob).exactly(:once)
      Current.user = nil

      names = events.map(&:first)
      expect(names.count('conversation_opened')).to eq(1)
      expect(names.count('conversation_status_changed')).to eq(1)
      expect(names.index('conversation_status_changed')).to be < names.index('message_created')
      expect(events.map { |event| event.drop(1) }.uniq).to eq([['open', 1]])
    end

    it "the takeover's assignee reaches message_created" do
      agent = create(:user, account: conversation.account)
      create(:inbox_member, inbox: conversation.inbox, user: agent)
      payloads = []
      allow(Rails.configuration.dispatcher).to receive(:dispatch) do |event, _time, data|
        payloads << [event, data[:message].conversation.assignee_id] if event == Message::MESSAGE_CREATED
      end

      create(:message, conversation: conversation, message_type: :outgoing, sender: agent)

      expect(payloads).to eq([[Message::MESSAGE_CREATED, agent.id]])
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

    # Comvor's own examples from here on.
    describe 'the replying agent' do
      let(:agent) { create(:user, account: conversation.account) }

      # No agent is online, so the inbox's own auto-assignment finds nobody:
      # the assignee can only come from the takeover.
      before { create(:inbox_member, inbox: conversation.inbox, user: agent) }

      it 'is assigned the conversation, which the agent bot no longer holds' do
        bot = create(:agent_bot, account: conversation.account)
        conversation.update!(assignee_agent_bot: bot)

        create(:message, conversation: conversation, message_type: :outgoing, sender: agent)

        expect(conversation.reload.slice(:assignee_id, :assignee_agent_bot_id)).to eq('assignee_id' => agent.id, 'assignee_agent_bot_id' => nil)
      end

      it 'does not replace an agent who already holds it' do
        colleague = create(:user, account: conversation.account)
        create(:inbox_member, inbox: conversation.inbox, user: colleague)
        conversation.update!(assignee: colleague)

        create(:message, conversation: conversation, message_type: :outgoing, sender: agent)

        expect(conversation.reload.slice(:status, :assignee_id)).to eq('status' => 'open', 'assignee_id' => colleague.id)
      end

      # The inbox's own auto-assignment would hand it to an online colleague,
      # in a second save that also hid the status change from the commit
      # callbacks, so conversation_opened was never dispatched.
      it 'is assigned over an online colleague, and the status events still go out once' do
        owner = create(:user, account: conversation.account, role: :administrator) # not an inbox member
        allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ agent.id.to_s => 'online' })
        events = []
        allow(Rails.configuration.dispatcher).to receive(:dispatch) { |event, *| events << event }

        create(:message, conversation: conversation, message_type: :outgoing, sender: owner)

        expect(conversation.reload.assignee_id).to eq(owner.id)
        expect(events.count(Conversation::CONVERSATION_OPENED)).to eq(1)
        expect(events.count(Conversation::CONVERSATION_STATUS_CHANGED)).to eq(1)
      end

      # The takeover's callbacks run as the system (Current.user cleared), so
      # the community self-assign check cannot see that the replier assigned
      # themselves.
      it 'is not notified of the assignment their own reply made' do
        notifiable = []
        allow(Rails.configuration.dispatcher).to receive(:dispatch).and_wrap_original do |original, event, time, data|
          notifiable << data[:notifiable_assignee_change] if event == Conversation::ASSIGNEE_CHANGED
          original.call(event, time, data)
        end

        perform_enqueued_jobs(only: EventDispatcherJob) do
          create(:message, conversation: conversation, message_type: :outgoing, sender: agent)
        end

        expect(conversation.reload.assignee_id).to eq(agent.id)
        expect(notifiable).to eq([false])
        expect(agent.notifications.where(notification_type: 'conversation_assignment')).to be_empty
      end

      it 'is still notified when someone else assigns them' do
        conversation.update!(status: :open)
        Current.user = create(:user, account: conversation.account, role: :administrator)

        perform_enqueued_jobs(only: EventDispatcherJob) { conversation.update!(assignee: agent) }

        expect(agent.notifications.where(notification_type: 'conversation_assignment').count).to eq(1)
      ensure
        Current.user = nil
      end

      it 'is not assigned when the inbox is not theirs to work in' do
        outsider = create(:user, account: conversation.account)

        create(:message, conversation: conversation, message_type: :outgoing, sender: outsider)

        expect(conversation.reload.slice(:status, :assignee_id)).to eq('status' => 'open', 'assignee_id' => nil)
      end
    end

    it 'writes the takeover activity message once, as the system' do
      content = I18n.t('conversations.activity.captain.auto_opened_after_agent_reply', locale: conversation.account.locale)

      expect do
        create(:message, conversation: conversation, message_type: :outgoing, sender: create(:user))
      end.to have_enqueued_job(Conversations::ActivityMessageJob).exactly(:once).with(
        conversation, { account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity, content: content }
      )
    end

    it 'takes the conversation over only once' do
      create(:message, conversation: conversation, message_type: :outgoing, sender: create(:user))

      clear_enqueued_jobs
      expect do
        create(:message, conversation: conversation, message_type: :outgoing, sender: create(:user))
      end.not_to(change { conversation.reload.status_revision })
      expect(Conversations::ActivityMessageJob).not_to have_been_enqueued
    end

    it 'forgets a takeover that rolled back when the same reply is saved again' do
      reply = build(:message, conversation: conversation, message_type: :outgoing, sender: create(:user))
      ActiveRecord::Base.transaction do
        reply.save!
        raise ActiveRecord::Rollback
      end
      Conversation.find(conversation.id).update!(status: :open) # someone else opened it meanwhile
      clear_enqueued_jobs

      reply.save!

      expect(Conversations::ActivityMessageJob).not_to have_been_enqueued
    end

    it 'leaves an open conversation alone' do
      conversation.update!(status: :open)

      expect do
        create(:message, conversation: conversation, message_type: :outgoing, sender: create(:user))
      end.not_to(change { conversation.reload.status_revision })
    end

    it 'leaves a pending conversation in an inbox without an active bot alone' do
      conversation.inbox.agent_bot_inbox.update!(status: :inactive)

      create(:message, conversation: conversation, message_type: :outgoing, sender: create(:user))

      expect(conversation.reload.status).to eq('pending')
    end
  end
end
