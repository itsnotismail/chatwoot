require 'rails_helper'

# Behaviour H: two agents reply to the same bot-held conversation at once.
# The takeover locks the conversation row and re-reads it before opening it,
# so the second reply finds it already open and does not take it over again.
# Real concurrency needs rows other database connections can see, so this
# group runs without transactional fixtures and deletes what it created.
RSpec.describe 'Comvor: concurrent takeover replies', type: :model do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:conversation) { create(:conversation, inbox: inbox, account: account, status: :pending) }
  let!(:first_agent) { create(:user, account: account) }
  let!(:second_agent) { create(:user, account: account) }
  # Every barrier and thread is registered so a failing or hanging example still releases and joins them.
  let(:releases) { [] }
  let(:threads) { [] }

  before { create(:agent_bot_inbox, inbox: inbox, status: 'active') }

  after do
    releases.each { |queue| queue << true }
    threads.each { |thread| thread.join(10) }
    bot_ids = AgentBotInbox.where(inbox_id: inbox.id).pluck(:agent_bot_id)
    ContactInbox.where(inbox_id: inbox.id).delete_all
    ActiveRecord::Base.connection.tables.each do |table|
      next unless ActiveRecord::Base.connection.column_exists?(table, :account_id)

      ActiveRecord::Base.connection.exec_delete("DELETE FROM #{table} WHERE account_id = #{account.id.to_i}")
    end
    AgentBot.where(id: bot_ids).delete_all
    agent_ids = [first_agent.id, second_agent.id]
    AccessToken.where(owner_type: 'AgentBot', owner_id: bot_ids).or(AccessToken.where(owner_type: 'User', owner_id: agent_ids)).delete_all
    User.where(id: agent_ids).delete_all
    # Audits carry no account_id column, so the sweep above misses them; left behind they break later audit-count specs.
    Audited::Audit.where(associated_type: 'Account', associated_id: account.id).delete_all
    Account.where(id: account.id).delete_all
  end

  def barrier
    Queue.new.tap { |queue| releases << queue }
  end

  def spawn(&)
    Thread.new(&).tap { |thread| threads << thread }
  end

  # Fails the example instead of hanging it when a regression means the other side never arrives.
  def pop!(queue)
    queue.pop(timeout: 10) || raise('timed out waiting on a concurrency barrier')
  end

  def value!(thread)
    thread.join(10) || raise('timed out waiting for a concurrent reply')
    thread.value
  end

  def reply(agent)
    Rails.application.executor.wrap do
      create(:message, conversation: Conversation.find(conversation.id), account: account, inbox: inbox, message_type: :outgoing, sender: agent)
    end
  end

  it 'opens the conversation and bumps its revision once' do
    revision = conversation.reload.status_revision
    taken_over = Queue.new
    release = barrier

    first = spawn do
      Rails.application.executor.wrap do
        ActiveRecord::Base.transaction do
          reply(first_agent)
          taken_over << true
          pop!(release) # holds the first takeover uncommitted
        end
      end
    end
    pop!(taken_over)

    second = spawn { reply(second_agent) }
    sleep 0.5
    second_blocked = second.alive?
    release << true
    value!(first)
    value!(second)

    expect(second_blocked).to be(true) # the second takeover waited for the first one's row lock
    expect(conversation.reload.slice(:status, :status_revision)).to eq('status' => 'open', 'status_revision' => revision + 1)
  end
end
