class Api::V1::Accounts::Conversations::MessagesController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_api_inbox, only: :update

  def index
    @messages = message_finder.perform
  end

  def create
    # A client_idempotency_key replay returns the message the first request created, with nothing re-created or re-sent.
    # It is checked before expected_status_revision, so a retry still gets its message after ownership has changed.
    @message = idempotent_message
    return if @message.present?

    # key?, not present?: a null, false or blank revision is a malformed guard (422), never an unguarded create.
    if params.key?(:expected_status_revision)
      create_at_expected_status_revision
    else
      @message = build_message
    end
  rescue ActiveRecord::RecordNotUnique => e
    # A concurrent request with the same key won the unique index; return its row.
    @message = idempotent_message
    render_could_not_create_error(e.message) if @message.blank?
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def update
    Messages::StatusUpdateService.new(message, permitted_params[:status], permitted_params[:external_error]).perform
    @message = message
  end

  def destroy
    ActiveRecord::Base.transaction do
      message.update!(content: I18n.t('conversations.messages.deleted'), content_type: :text, content_attributes: { deleted: true })
      message.attachments.destroy_all
    end
  end

  def retry
    return if message.blank?

    service = Messages::StatusUpdateService.new(message, 'sent')
    service.perform
    message.update!(content_attributes: {})
    ::SendReplyJob.perform_later(message.id)
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def translate
    return head :ok if already_translated_content_available?

    translated_content = Integrations::GoogleTranslate::ProcessorService.new(
      message: message,
      target_language: permitted_params[:target_language]
    ).perform

    if translated_content.present?
      translations = {}
      translations[permitted_params[:target_language]] = translated_content
      translations = message.translations.merge!(translations) if message.translations.present?
      message.update!(translations: translations)
    end

    render json: { content: translated_content }
  end

  private

  def message
    @message ||= @conversation.messages.find(permitted_params[:id])
  end

  def build_message
    user = Current.user || @resource
    Messages::MessageBuilder.new(user, @conversation, params, client_idempotency_key: params[:client_idempotency_key]).perform
  end

  # Creates the message only while the conversation is still at the status revision the client last saw. The row lock
  # makes a concurrent status change (toggle_status, the agent-reply takeover) wait for this commit, so it lands after the
  # message instead of in between the check and the insert. A committed message's channel send cannot be recalled.
  def create_at_expected_status_revision
    expected_revision = Integer(params[:expected_status_revision].to_s, 10)
    @conversation.with_lock do
      @message = idempotent_message
      next if @message.present?

      if @conversation.status_revision == expected_revision
        @message = build_message
      else
        render_status_revision_mismatch
      end
    end
  end

  def render_status_revision_mismatch
    render json: { error: 'status_revision_mismatch', status: @conversation.status, status_revision: @conversation.status_revision },
           status: :conflict
  end

  def idempotent_message
    return if params[:client_idempotency_key].blank?

    @conversation.messages.find_by(account_id: @conversation.account_id, client_idempotency_key: params[:client_idempotency_key])
  end

  def message_finder
    @message_finder ||= MessageFinder.new(@conversation, params)
  end

  def permitted_params
    params.permit(:id, :target_language, :status, :external_error)
  end

  def already_translated_content_available?
    message.translations.present? && message.translations[permitted_params[:target_language]].present?
  end

  # API inbox check
  def ensure_api_inbox
    # Only API inboxes can update messages
    render json: { error: 'Message status update is only allowed for API inboxes' }, status: :forbidden unless @conversation.inbox.api?
  end
end
