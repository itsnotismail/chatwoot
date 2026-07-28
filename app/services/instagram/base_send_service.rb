class Instagram::BaseSendService < Base::SendOnChannelService
  pattr_initialize [:message!]

  private

  delegate :additional_attributes, to: :contact

  def perform_reply
    send_attachments if message.attachments.present?
    send_content if message.content.present?
  rescue StandardError => e
    handle_error(e)
  end

  def send_attachments
    message.attachments.each do |attachment|
      send_message(attachment_message_params(attachment))
    end
  end

  def send_content
    send_message(message_params)
  end

  def handle_error(error)
    ChatwootExceptionTracker.new(error, account: message.account, user: message.sender).capture_exception
  end

  def message_params
    params = {
      recipient: { id: contact.get_source_id(inbox.id) },
      message: instagram_message_payload
    }

    merge_human_agent_tag(params)
  end

  # Instagram quick replies. Mirrors Facebook::SendOnFacebookService's
  # fb_text_message_payload (send_on_facebook_service.rb): both channels are
  # Meta Messenger-shaped and take the same quick_replies structure, but
  # upstream only ever implemented it for Facebook — confirmed still absent on
  # master v4.16.2 (2026-07-28), so this is a fork addition. Both Instagram
  # send services (Instagram::SendOnInstagramService and
  # Instagram::Messenger::SendOnInstagramService) inherit this base, so one
  # definition covers both.
  #
  # The `.any?` guard is the Facebook original's and is load-bearing: an
  # input_select with an empty items list would otherwise produce
  # quick_replies: [] and Meta rejects the send outright, losing the words.
  # `.to_a.any?` rather than the original's bare `.any?` only because
  # content_attributes['items'] can be nil here (Facebook's own call site is
  # reached through a path that guarantees the key); nil.any? would raise
  # inside perform_reply's rescue and surface as a silent send failure.
  def instagram_message_payload
    if message.content_type == 'input_select' && message.content_attributes['items'].to_a.any?
      {
        text: message.content,
        quick_replies: message.content_attributes['items'].map do |item|
          {
            content_type: 'text',
            payload: item['title'],
            title: item['title']
          }
        end
      }
    else
      { text: message.outgoing_content }
    end
  end

  def attachment_message_params(attachment)
    params = {
      recipient: { id: contact.get_source_id(inbox.id) },
      message: {
        attachment: {
          type: attachment_type(attachment),
          payload: {
            url: attachment.download_url
          }
        }
      }
    }

    merge_human_agent_tag(params)
  end

  def process_response(response, message_content)
    parsed_response = response.parsed_response
    if response.success? && parsed_response['error'].blank?
      message.update!(source_id: parsed_response['message_id'])
      parsed_response
    else
      external_error = external_error(parsed_response)
      Rails.logger.error("Instagram response: #{external_error} : #{message_content}")
      Messages::StatusUpdateService.new(message, 'failed', external_error).perform
      nil
    end
  end

  def external_error(response)
    error_message = response.dig('error', 'message')
    error_code = response.dig('error', 'code')

    # https://developers.facebook.com/docs/messenger-platform/error-codes
    # Access token has expired or become invalid. This may be due to a password change,
    # removal of the connected app from Instagram account settings, or other reasons.
    channel.authorization_error! if error_code == 190

    "#{error_code} - #{error_message}"
  end

  def attachment_type(attachment)
    return attachment.file_type if %w[image audio video file].include? attachment.file_type

    'file'
  end

  # Methods to be implemented by child classes
  def send_message(message_content)
    raise NotImplementedError, 'Subclasses must implement send_message'
  end

  def merge_human_agent_tag(params)
    raise NotImplementedError, 'Subclasses must implement merge_human_agent_tag'
  end
end
