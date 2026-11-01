# frozen_string_literal: true

# Merchant takeover (behaviour H): a human's public reply on a conversation
# the bot holds, i.e. pending in an inbox with an active agent bot (or a
# Captain one), hands it to that human. Inside the reply's transaction the
# conversation opens, which bumps its status_revision, and the replying agent
# is assigned when nobody is (Custom::Conversation#take_over_for). So a bot
# message guarded by expected_status_revision either committed before the
# reply or is refused after it: there is no gap after the reply commits in
# which it could pass at the old revision.
module Custom::Message
  def self.prepended(base)
    base.after_create :take_over_bot_conversation
  end

  private

  # Runs from the reply's after_create_commit, after the takeover committed.
  # Without super: upstream opens the conversation here, after the commit,
  # which is too late for the revision guard.
  def mark_pending_conversation_as_open_for_human_response
    return if @bot_takeover.nil?

    @bot_takeover.run_takeover_commit_callbacks
    content = I18n.t('conversations.activity.captain.auto_opened_after_agent_reply', locale: conversation.account.locale)
    ::Conversations::ActivityMessageJob.perform_later(conversation, { account_id: conversation.account_id, inbox_id: conversation.inbox_id,
                                                                      message_type: :activity, content: content })
  ensure
    @bot_takeover = nil
  end

  # The conversation is locked on an instance of its own: lock! reloads, and
  # the reply's instance may carry state this transaction still needs (it is
  # the one conversations#create just saved). The lock also orders the
  # takeover against a guarded bot message, which holds the same row lock
  # from its revision check to its commit. Status is re-read under the lock,
  # so a second reply that waited for this one finds it open and does nothing.
  def take_over_bot_conversation
    return unless takes_over_bot_conversation?

    owner = Conversation.find(conversation_id)
    owner.lock!
    return unless owner.pending?

    owner.take_over_for(sender)
    mirror_takeover(owner)
    @bot_takeover = owner
  end

  # sender.is_a?(User) is not redundant with human_response?, which also
  # accepts an external echo. A bot reply carrying an image becomes two Meta
  # sends that overwrite each other's source_id, so the image's echo comes
  # back as a new outgoing message with no sender: without the check the bot
  # would take the conversation over from itself.
  def takes_over_bot_conversation?
    return false if private? || !human_response? || !conversation.pending?

    captain_pending_conversation? || (conversation.inbox.active_bot? && sender.is_a?(User))
  end

  # The reply's message_created payload is built from its own conversation
  # instance, so it gets the state the takeover just wrote, without becoming
  # a change of that instance.
  def mirror_takeover(owner)
    attributes = %w[status status_revision assignee_id assignee_agent_bot_id]
    attributes.each { |attribute| conversation[attribute] = owner[attribute] }
    conversation.clear_attribute_changes(attributes)
  end
end
