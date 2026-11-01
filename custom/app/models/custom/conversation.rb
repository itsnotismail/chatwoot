# frozen_string_literal: true

# The conversation side of the merchant takeover (behaviour H, see
# Custom::Message). take_over_for runs on a locked instance of its own inside
# the reply's transaction, and that instance's commit callbacks are deferred
# to the reply, which runs them once from its own after_create_commit.
#
# Why deferred: with load_defaults 7.0
# (run_commit_callbacks_on_first_saved_instances_in_transaction) Rails runs
# commit callbacks only on the first instance of a record saved in a
# transaction. When the conversation was saved earlier in the same
# transaction (conversations#create with an initial message, the channel
# builders), this instance would get none, and conversation_opened and
# conversation_status_changed would be lost. When it was not, they would run
# at the commit after the reply's message_created, and as the agent, which
# adds an agent status activity and a performer to the events.
#
# The takeover picks the assignee itself, so the inbox's auto-assignment does
# not run on its save: it would hand the conversation to an online colleague
# (an administrator who replies is not an inbox member), and its second save
# replaces the saved changes the commit callbacks read, so the status change,
# and with it conversation_opened, would not be seen.
module Custom::Conversation
  def take_over_for(agent)
    @takeover_commit_callbacks_deferred = true
    if assignee_id.blank? && agent.is_a?(User) && inbox.assignable_agents.include?(agent)
      self.assignee = agent
      @takeover_assigned_replier_id = agent.id
    end
    update!(status: :open)
  end

  # The replier assigned themselves by replying, as a self-assign in the UI
  # does, which never notifies. The community check (self_assign?) compares
  # with Current.user, which the takeover's callbacks run without.
  def notifiable_assignee_change?
    return false if @takeover_commit_callbacks_deferred && assignee_id.present? && assignee_id == @takeover_assigned_replier_id

    super
  end

  # As the system: no agent status activity, no performer on the events.
  def run_takeover_commit_callbacks
    user = Current.user
    executed_by = Current.executed_by
    Current.user = Current.executed_by = nil
    _run_commit_callbacks
  ensure
    Current.user = user
    Current.executed_by = executed_by
    @takeover_commit_callbacks_deferred = false
  end

  # Rails asks this when it picks the instance whose commit callbacks run.
  def trigger_transactional_callbacks?
    return false if @takeover_commit_callbacks_deferred

    super
  end

  private

  def run_auto_assignment
    super unless @takeover_commit_callbacks_deferred
  end
end
