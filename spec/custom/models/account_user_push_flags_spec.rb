require 'rails_helper'

# Behaviour I: with COMVOR_AUTO_INBOX_MEMBERSHIP on, a new account user joins
# every inbox, so they are also alerted to new conversations and to new
# messages in the ones assigned to them (Custom::AccountUser). With it off the
# setting is upstream's.
RSpec.describe AccountUser do
  let(:account) { create(:account) }
  let(:user) { create(:user) }
  let(:setting) { user.notification_settings.find_by!(account_id: account.id) }

  context 'when auto inbox membership is on' do
    around { |example| with_modified_env(COMVOR_AUTO_INBOX_MEMBERSHIP: 'true') { example.run } }

    it 'turns on the new-conversation and assigned-message push alerts next to the upstream ones' do
      create(:inbox, account: account)
      create(:account_user, account: account, user: user)

      expect(setting.selected_push_flags)
        .to contain_exactly(:push_conversation_assignment, :push_conversation_creation, :push_assigned_conversation_new_message)
      expect(setting.selected_email_flags).to eq([:email_conversation_assignment])
    end
  end

  context 'when auto inbox membership is off' do
    around { |example| with_modified_env(COMVOR_AUTO_INBOX_MEMBERSHIP: 'false') { example.run } }

    it 'keeps the upstream push alerts only' do
      create(:account_user, account: account, user: user)

      expect(setting.selected_push_flags).to eq([:push_conversation_assignment])
    end
  end
end
