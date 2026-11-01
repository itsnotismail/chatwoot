# frozen_string_literal: true

# Behaviour I: with auto inbox membership on, a new account user joins every
# inbox (AccountUser#join_account_inboxes), so they are also alerted to new
# conversations and to new messages in the ones assigned to them. Set here and
# not in join_account_inboxes: after-commit callbacks run in reverse order, so
# join_account_inboxes runs before this creates the setting.
module Custom::AccountUser
  INBOX_MEMBER_PUSH_FLAGS = %i[push_conversation_creation push_assigned_conversation_new_message].freeze

  def create_notification_setting
    super
    return unless InboxMember.auto_membership?

    setting = user.notification_settings.find_by!(account_id: account.id)
    setting.selected_push_flags = (setting.selected_push_flags + INBOX_MEMBER_PUSH_FLAGS).uniq
    setting.save!
  end
end
