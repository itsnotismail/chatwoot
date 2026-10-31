# frozen_string_literal: true

require 'rails_helper'

# Comvor: with COMVOR_AUTO_INBOX_MEMBERSHIP on, a new inbox starts with every account user and a new
# account user joins every inbox; with it off, upstream behaviour is unchanged.
RSpec.describe InboxMember do
  let(:account) { create(:account) }
  let!(:owner) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }

  context 'when the flag is on' do
    around { |example| with_modified_env(COMVOR_AUTO_INBOX_MEMBERSHIP: 'true') { example.run } }

    it 'adds every account user, the owner included, to a new inbox' do
      inbox = create(:inbox, account: account)
      expect(inbox.reload.members).to contain_exactly(owner, agent)
    end

    it 'does not touch users of another account' do
      outsider = create(:user, account: create(:account))
      inbox = create(:inbox, account: account)
      expect(inbox.reload.members).not_to include(outsider)
    end

    it 'adds a new team member to every existing inbox of the account' do
      first = create(:inbox, account: account)
      second = create(:inbox, account: account)
      newcomer = create(:user)
      create(:account_user, account: account, user: newcomer)
      expect(first.reload.members).to include(newcomer)
      expect(second.reload.members).to include(newcomer)
    end

    it 'keeps an owner removal: the wizard replaces the list and nothing adds the agent back' do
      inbox = create(:inbox, account: account)
      inbox.remove_members([agent.id])
      inbox.update!(name: 'Renamed')
      expect(inbox.reload.members).to contain_exactly(owner)
    end

    it 'does not fail when the new team member is already in an inbox' do
      inbox = create(:inbox, account: account)
      newcomer = create(:user)
      inbox.add_members([newcomer.id])
      expect { create(:account_user, account: account, user: newcomer) }.not_to raise_error
      expect(inbox.reload.members.where(id: newcomer.id).count).to eq(1)
    end
  end

  context 'when the flag is off' do
    it 'leaves a new inbox with no members' do
      inbox = create(:inbox, account: account)
      expect(inbox.reload.members).to be_empty
    end

    it 'does not add a new team member to existing inboxes' do
      inbox = create(:inbox, account: account)
      create(:account_user, account: account, user: create(:user))
      expect(inbox.reload.members).to be_empty
    end
  end

  describe '.missing_account_pairs' do
    it 'lists each account user missing from each inbox, and nothing for full inboxes' do
      account = create(:account)
      owner = create(:user, account: account, role: :administrator)
      agent = create(:user, account: account, role: :agent)
      full = create(:inbox, account: account)
      full.add_members([owner.id, agent.id])
      partial = create(:inbox, account: account)
      partial.add_members([owner.id])
      create(:inbox, account: create(:account)).add_members([create(:user).id])

      expect(described_class.missing_account_pairs(account)).to eq([[partial, agent.id]])
    end
  end
end
