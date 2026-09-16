module Enterprise::Conversation
  attr_accessor :captain_activity_reason, :captain_activity_reason_type
  # Set by Enterprise::Message when an agent reply opens a bot-pending conversation inside the reply's transaction.
  attr_accessor :opened_by_human_takeover

  def dispatch_captain_inference_resolved_event
    dispatch_captain_inference_event(Events::Types::CONVERSATION_CAPTAIN_INFERENCE_RESOLVED)
  end

  def dispatch_captain_inference_handoff_event
    dispatch_captain_inference_event(Events::Types::CONVERSATION_CAPTAIN_INFERENCE_HANDOFF)
  end

  # Mirror a takeover saved on another instance of this row without marking this one dirty, so payloads built from it
  # show the open conversation and a later save of it does not rewrite the status (or bump status_revision again).
  def sync_takeover_status_from(takeover)
    %w[status status_revision updated_at].each do |attribute|
      self[attribute] = takeover[attribute]
      clear_attribute_change(attribute)
    end
  end

  def list_of_keys
    super + %w[sla_policy_id]
  end

  def with_captain_activity_context(reason:, reason_type:)
    previous_reason = captain_activity_reason
    previous_reason_type = captain_activity_reason_type

    self.captain_activity_reason = reason
    self.captain_activity_reason_type = reason_type
    yield
  ensure
    self.captain_activity_reason = previous_reason
    self.captain_activity_reason_type = previous_reason_type
  end

  # Include select additional_attributes keys (call related) for update events
  def allowed_keys?
    return true if super

    attrs_change = previous_changes['additional_attributes']
    return false unless attrs_change.is_a?(Array) && attrs_change[1].is_a?(Hash)

    changed_attr_keys = attrs_change[1].keys
    changed_attr_keys.intersect?(%w[call_status])
  end

  private

  # The takeover's status change commits with the agent's reply, while Current.user is the agent again. Run its commit
  # callbacks (status webhooks, activity, action cable) as the system, as they ran when the takeover saved on its own.
  def execute_after_update_commit_callbacks
    return super unless opened_by_human_takeover

    self.opened_by_human_takeover = false
    previous_user = Current.user
    previous_executed_by = Current.executed_by
    Current.user = nil
    Current.executed_by = nil
    begin
      super
    ensure
      Current.user = previous_user
      Current.executed_by = previous_executed_by
    end
  end

  def dispatch_captain_inference_event(event_name)
    dispatcher_dispatch(event_name)
  end
end
