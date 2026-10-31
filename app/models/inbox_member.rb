# == Schema Information
#
# Table name: inbox_members
#
#  id         :integer          not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  inbox_id   :integer          not null
#  user_id    :integer          not null
#
# Indexes
#
#  index_inbox_members_on_inbox_id              (inbox_id)
#  index_inbox_members_on_inbox_id_and_user_id  (inbox_id,user_id) UNIQUE
#

class InboxMember < ApplicationRecord
  validates :inbox_id, presence: true

  # Comvor: whether a new inbox starts with every account user and a new account user joins every inbox
  # (Inbox#add_account_users_as_members, AccountUser#join_account_inboxes). Dark unless the deployment sets
  # COMVOR_AUTO_INBOX_MEMBERSHIP=true, so upstream behaviour (and upstream specs) are unchanged without it.
  def self.auto_membership?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('COMVOR_AUTO_INBOX_MEMBERSHIP', false))
  end

  # Comvor: the [inbox, user] pairs of an account where the user is not a member, for the one-off backfill of
  # inboxes created before auto membership (lib/tasks/ops/comvor_backfill_inbox_members.rake).
  def self.missing_account_pairs(account)
    user_ids = account.account_users.pluck(:user_id)
    account.inboxes.order(:id).flat_map do |inbox|
      (user_ids - inbox.inbox_members.pluck(:user_id)).sort.map { |user_id| [inbox, user_id] }
    end
  end
  validates :user_id, presence: true
  validates :user_id, uniqueness: { scope: :inbox_id }

  belongs_to :user
  belongs_to :inbox

  after_create :add_agent_to_round_robin
  after_destroy :remove_agent_from_round_robin

  private

  def add_agent_to_round_robin
    ::AutoAssignment::InboxRoundRobinService.new(inbox: inbox).add_agent_to_queue(user_id)
  end

  def remove_agent_from_round_robin
    ::AutoAssignment::InboxRoundRobinService.new(inbox: inbox).remove_agent_from_queue(user_id) if inbox.present?
  end
end

InboxMember.include_mod_with('Audit::InboxMember')
