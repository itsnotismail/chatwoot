# Send-time reply eligibility for one conversation, so a bot does not have to trust a stale webhook.
class Api::V1::Accounts::Conversations::ReplyEligibilitiesController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_agent_bot_connected

  def show
    window = Conversations::MessageWindowService.new(@conversation)
    body = {
      channel: @conversation.inbox.channel_type,
      can_reply: window.can_reply?,
      status: @conversation.status,
      status_revision: @conversation.status_revision,
      last_incoming_at: window.last_incoming_message_at&.iso8601(6)
    }
    # Opt-in, so the bot's existing reply check keeps its exact shape. The unanswered-chat alert asks for it.
    body[:window_ends_at] = window.window_ends_at&.iso8601(6) if params[:include] == 'window_ends_at'
    render json: body
  end

  private

  def ensure_agent_bot_connected
    raise ActiveRecord::RecordNotFound unless agent_bot_connected_to_inbox?(@conversation.inbox)
  end
end
