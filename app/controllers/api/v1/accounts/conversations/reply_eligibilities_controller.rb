# Send-time reply eligibility for one conversation, so a bot does not have to trust a stale webhook.
class Api::V1::Accounts::Conversations::ReplyEligibilitiesController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_agent_bot_connected

  def show
    window = Conversations::MessageWindowService.new(@conversation)
    render json: {
      channel: @conversation.inbox.channel_type,
      can_reply: window.can_reply?,
      status: @conversation.status,
      status_revision: @conversation.status_revision,
      last_incoming_at: window.last_incoming_message_at&.iso8601(6)
    }
  end

  private

  def ensure_agent_bot_connected
    raise ActiveRecord::RecordNotFound unless agent_bot_connected_to_inbox?(@conversation.inbox)
  end
end
