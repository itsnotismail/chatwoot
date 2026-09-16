class AddStatusRevisionToConversations < ActiveRecord::Migration[7.1]
  # A constant default is metadata-only on PostgreSQL 11+, so this does not rewrite the table.
  def change
    add_column :conversations, :status_revision, :bigint, null: false, default: 0
  end
end
