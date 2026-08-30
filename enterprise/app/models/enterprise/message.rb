module Enterprise::Message
  private

  def mark_pending_conversation_as_open_for_human_response
    return unless captain_pending_conversation?
    return unless human_response?
    return if private?
    return if template_bootstrap_message?

    previous_user = Current.user
    previous_executed_by = Current.executed_by
    Current.user = nil
    Current.executed_by = nil

    begin
      conversation.open!
      return unless conversation.saved_change_to_status?

      create_captain_auto_open_activity_message
    ensure
      Current.user = previous_user
      Current.executed_by = previous_executed_by
    end
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
