require 'rails_helper'

# Real concurrency needs rows other database connections can see, so this group runs without transactional fixtures
# and deletes what it created.
RSpec.describe 'Conversation Messages API expected_status_revision locking', type: :request do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:agent_bot) { create(:agent_bot, account: account) }
  let!(:conversation) { create(:conversation, inbox: inbox, account: account, status: :pending) }
  let(:path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages" }
  # Every barrier and thread is registered so a failing or hanging example still releases and joins them.
  let(:releases) { [] }
  let(:threads) { [] }

  before do
    create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
    # Load the request path once on this thread so no constant autoloading happens while threads hold locks.
    guarded_post(content: 'warm up', expected_status_revision: conversation.reload.status_revision)
    Message.where(conversation_id: conversation.id).delete_all
  end

  after do
    releases.each { |queue| queue << true }
    threads.each { |thread| thread.join(10) }
    ContactInbox.where(inbox_id: inbox.id).delete_all
    ActiveRecord::Base.connection.tables.each do |table|
      next unless ActiveRecord::Base.connection.column_exists?(table, :account_id)

      ActiveRecord::Base.connection.exec_delete("DELETE FROM #{table} WHERE account_id = #{account.id.to_i}")
    end
    AccessToken.where(owner: agent_bot).delete_all
    # Audits carry no account_id column, so the sweep above misses them; left behind they break later audit-count specs.
    Audited::Audit.where(associated_type: 'Account', associated_id: account.id).delete_all
    Account.where(id: account.id).delete_all
  end

  def guarded_post(body)
    headers = { 'CONTENT_TYPE' => 'application/json', 'HTTP_API_ACCESS_TOKEN' => agent_bot.access_token.token, 'HTTP_HOST' => 'www.example.com' }
    env = Rack::MockRequest.env_for(path, method: 'POST', input: body.to_json).merge(headers)
    status, _headers, response_body = Rails.application.call(env)
    body_text = +''
    response_body.each { |part| body_text << part }
    response_body.close if response_body.respond_to?(:close)
    [status, JSON.parse(body_text)]
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
    thread.join(10) || raise('timed out waiting for a concurrent request')
    thread.value
  end

  # Holds the guarded create after its revision check and before its insert (MessageBuilder#perform runs there).
  def hold_guarded_create_before_insert(reached, release)
    allow(Messages::MessageBuilder).to receive(:new).and_wrap_original do |original, *args, **kwargs|
      original.call(*args, **kwargs).tap do |builder|
        allow(builder).to receive(:perform).and_wrap_original do |perform|
          reached << true
          pop!(release)
          perform.call
        end
      end
    end
  end

  it 'makes a concurrent status change wait until the guarded message has committed' do
    revision = conversation.reload.status_revision
    reached = Queue.new
    release = barrier
    statements = Queue.new
    hold_guarded_create_before_insert(reached, release)

    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      statements << [payload[:sql], Time.now.to_f] if Thread.current[:guarded_create]
    end

    guarded = spawn do
      Thread.current[:guarded_create] = true
      guarded_post(content: 'your order is confirmed', expected_status_revision: revision)
    end
    pop!(reached)

    takeover = spawn do
      Rails.application.executor.wrap do
        Conversation.find(conversation.id).open!
        Time.now.to_f
      end
    end

    sleep 0.5
    takeover_blocked = takeover.alive?
    release << true
    expect(takeover_blocked).to be(true) # the status change waited on the row lock the guarded create holds

    status, body = value!(guarded)
    takeover_done_at = value!(takeover)
    ActiveSupport::Notifications.unsubscribe(subscriber)

    expect([status, Message.exists?(body['id'])]).to eq([200, true])
    expect(conversation.reload.slice(:status, :status_revision)).to eq('status' => 'open', 'status_revision' => revision + 1)

    entries = [].tap { |list| list << statements.pop until statements.empty? }
    sql = entries.map(&:first)
    lock_at = sql.index { |query| query.match?(/FROM "conversations".*FOR UPDATE/m) }
    insert_at = sql.index { |query| query.start_with?('INSERT INTO "messages"') }
    begin_at = sql[0...lock_at.to_i].rindex('BEGIN')
    commit_at = (insert_at.to_i...sql.size).find { |index| sql[index] == 'COMMIT' }
    # The lock and the insert run in one transaction, and its COMMIT is what lets the status change through.
    expect([lock_at, insert_at, begin_at, commit_at]).to all(be_an(Integer))
    expect(lock_at).to be < insert_at
    expect(sql[begin_at..insert_at]).not_to include('COMMIT', 'ROLLBACK')
    expect(takeover_done_at).to be > entries[commit_at].last
  end

  it 'refuses the guarded message when a status change commits while it waits for the lock' do
    revision = conversation.reload.status_revision
    locked = Queue.new
    release = barrier

    takeover = spawn do
      Rails.application.executor.wrap do
        Conversation.transaction do
          owner = Conversation.find(conversation.id)
          owner.lock!
          owner.open!
          locked << true
          pop!(release)
        end
      end
    end
    pop!(locked)

    guarded = spawn { guarded_post(content: 'your order is confirmed', expected_status_revision: revision) }
    sleep 0.5
    guarded_blocked = guarded.alive?
    release << true
    expect(guarded_blocked).to be(true) # the guarded create waited for the conversation row lock
    value!(takeover)
    status, body = value!(guarded)

    expect(status).to eq(409)
    expect(body).to eq('error' => 'status_revision_mismatch', 'status' => 'open', 'status_revision' => revision + 1)
    expect(Message.where(conversation_id: conversation.id, message_type: :outgoing).count).to eq(0)
  end
end
