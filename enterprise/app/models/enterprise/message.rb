module Enterprise::Message
  def self.prepended(base)
    # Runs inside the message's insert transaction, so the takeover's row lock and status_revision bump commit together
    # with the human reply. A bot create guarded by expected_status_revision therefore either commits before this
    # reply (and the takeover lands after it) or sees the bumped revision; it can no longer slip in between the reply
    # committing and the conversation opening.
    base.after_create :open_pending_conversation_for_human_response
  end

  private

  def open_pending_conversation_for_human_response
    return unless captain_pending_conversation?
    return unless human_response?
    return if private?
    return if template_bootstrap_message?

    # A separate instance, so the message's after_create_commit updates to the association instance (waiting_since,
    # first_reply_created_at) cannot overwrite the saved status change before its commit callbacks run.
    takeover = ::Conversation.find(conversation_id)
    takeover.lock!
    return unless takeover.pending?

    open_as_system(takeover)
    conversation.sync_takeover_status_from(takeover)
    @opened_pending_conversation_for_human_response = true
  end

  def open_as_system(takeover)
    previous_user = Current.user
    previous_executed_by = Current.executed_by
    Current.user = nil
    Current.executed_by = nil
    takeover.opened_by_human_takeover = true
    takeover.open!
  ensure
    Current.user = previous_user
    Current.executed_by = previous_executed_by
  end

  # Called from the core after_create_commit chain; the status change itself already happened in
  # open_pending_conversation_for_human_response, so only the activity job is left, and it is enqueued after commit.
  def mark_pending_conversation_as_open_for_human_response
    return unless @opened_pending_conversation_for_human_response

    @opened_pending_conversation_for_human_response = false
    create_captain_auto_open_activity_message
  end

  def captain_pending_conversation?
    return false unless conversation.pending?

    return true if ::CaptainInbox.exists?(inbox_id: conversation.inbox_id)

    # An agent-bot-handled conversation is taken over when a HUMAN AGENT
    # replies into it.
    #
    # sender.is_a?(User) is NOT redundant with the human_response? check the
    # caller already makes, and it is the important part. human_response?
    # passes on EITHER a User sender OR content_attributes['external_echo'],
    # and the echo arm is a live hazard: a bot reply carrying an image becomes
    # two Meta sends that overwrite each other's source_id, so the attachment's
    # echo never dedupes and returns as a NEW outgoing message with a nil
    # sender and external_echo set. Without this clause the bot would take
    # conversations over from ITSELF whenever it sent a product photo.
    conversation.inbox.active_bot? && sender.is_a?(User)
  end

  def template_bootstrap_message?
    additional_attributes['template_params'].present? &&
      !conversation.messages.incoming.exists?
  end

  def create_captain_auto_open_activity_message
    ::Conversations::ActivityMessageJob.perform_later(
      conversation,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      content: I18n.t('conversations.activity.captain.auto_opened_after_agent_reply', locale: conversation.account.locale)
    )
  end
end
