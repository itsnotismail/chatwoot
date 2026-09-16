class AddStatusRevisionToConversations < ActiveRecord::Migration[7.1]
  def up
    # A constant default is metadata-only on PostgreSQL 11+, so this does not rewrite the table. It still needs a brief
    # ACCESS EXCLUSIVE lock; fail fast rather than block conversation writes behind a long-running transaction.
    # SET LOCAL ends with the migration's transaction.
    execute "SET LOCAL lock_timeout = '5s'"
    add_column :conversations, :status_revision, :bigint, null: false, default: 0
  end

  def down
    execute "SET LOCAL lock_timeout = '5s'"
    remove_column :conversations, :status_revision
  end
end
