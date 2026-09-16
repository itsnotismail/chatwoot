module Enterprise::Conversation
  attr_accessor :captain_activity_reason, :captain_activity_reason_type
  # Set to :deferred by Enterprise::Message on the instance that opens a bot-pending conversation inside an agent reply's
  # transaction; the reply's commit chain then runs this instance's commit callbacks exactly once (see below).
  attr_accessor :human_takeover_callbacks

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

  # The takeover instance's own commit callbacks are unreliable: with run_commit_callbacks_on_first_saved_instances_in_transaction
  # (load_defaults 7.0), they never run when another instance of the conversation was saved earlier in the same transaction
  # (conversations#create with an initial agent message, channel builders). So they are skipped on that instance and
  # the reply's commit chain runs them once, as the system, as they ran when the takeover saved on its own.
  def dispatch_human_takeover_callbacks
    return unless human_takeover_callbacks == :deferred

    self.human_takeover_callbacks = :dispatched
    previous_user = Current.user
    previous_executed_by = Current.executed_by
    Current.user = nil
    Current.executed_by = nil
    @dispatching_human_takeover_callbacks = true
    execute_after_update_commit_callbacks
    notify_assignment_change
    process_assignment_changes
  ensure
    @dispatching_human_takeover_callbacks = false
    Current.user = previous_user
    Current.executed_by = previous_executed_by
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

  def execute_after_update_commit_callbacks
    super unless skip_human_takeover_callback?
  end

  def notify_assignment_change
    super unless skip_human_takeover_callback?
  end

  def process_assignment_changes
    super unless skip_human_takeover_callback?
  end

  def skip_human_takeover_callback?
    human_takeover_callbacks.present? && !@dispatching_human_takeover_callbacks
  end

  def dispatch_captain_inference_event(event_name)
    dispatcher_dispatch(event_name)
  end
end
