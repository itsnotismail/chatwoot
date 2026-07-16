json.payload do
  @inbox_members.each do |inbox_member|
    next if inbox_member.user.blank?

    json.child! do
      json.id inbox_member.user.id
      json.name inbox_member.user.available_name
      json.avatar_url inbox_member.user.avatar_url
      json.availability_status inbox_member.user.account_users.find_by(account_id: @current_account.id)&.availability_status
    end
  end

  # Comvor: an inbox with an active agent bot always has an automated responder
  # online, so the widget must not render "We are away". Chatwoot's widget
  # availability (useAvailability#isOnline) is driven purely by online human
  # agents in this list — an attached AgentBot is never counted — so a bot-only
  # inbox always shows away. Surface the active bot here as an online "agent"
  # so hasOnlineAgents is true and the widget reflects that the AI is available.
  # Display-only (this endpoint feeds the widget availability indicator alone);
  # applies uniformly to demo, merchant-created, and existing inboxes with AI
  # enabled — no per-inbox provisioning needed.
  if @web_widget.inbox.active_bot? && (bot = @web_widget.inbox.agent_bot)
    json.child! do
      json.id "agent-bot-#{bot.id}"
      json.name bot.available_name
      json.avatar_url bot.avatar_url
      json.availability_status 'online'
    end
  end
end
