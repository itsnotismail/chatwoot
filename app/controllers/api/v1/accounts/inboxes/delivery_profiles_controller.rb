# Read-only delivery metadata for one inbox: its channel type and, for WhatsApp, the approved templates.
# Agent bots may read it only for inboxes they are connected to.
class Api::V1::Accounts::Inboxes::DeliveryProfilesController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox

  def show
    profile = { inbox_id: @inbox.id, channel_type: @inbox.channel_type }
    profile.merge!(whatsapp_templates) if @inbox.channel_type == 'Channel::Whatsapp'
    render json: profile
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :show?
    raise ActiveRecord::RecordNotFound unless agent_bot_connected_to_inbox?(@inbox)
  end

  def whatsapp_templates
    channel = @inbox.channel
    {
      templates: Whatsapp::ApprovedTemplatesSummaryService.new(channel: channel).perform,
      templates_last_updated_at: channel.message_templates_last_updated&.iso8601
    }
  end
end
