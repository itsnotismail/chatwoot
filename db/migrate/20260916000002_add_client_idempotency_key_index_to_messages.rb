class AddClientIdempotencyKeyIndexToMessages < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  INDEX_NAME = 'index_messages_on_client_idempotency_key'.freeze

  def up
    # A failed CREATE INDEX CONCURRENTLY leaves an INVALID index behind under the same name; drop it so a rerun rebuilds.
    remove_index :messages, name: INDEX_NAME, algorithm: :concurrently if invalid_index_exists?
    add_index :messages, [:account_id, :conversation_id, :client_idempotency_key],
              unique: true,
              where: 'client_idempotency_key IS NOT NULL',
              name: INDEX_NAME,
              algorithm: :concurrently,
              if_not_exists: true
  end

  def down
    remove_index :messages, name: INDEX_NAME, algorithm: :concurrently, if_exists: true
  end

  private

  def invalid_index_exists?
    select_value(<<~SQL.squish)
      SELECT NOT pg_index.indisvalid
      FROM pg_index JOIN pg_class ON pg_class.oid = pg_index.indexrelid
      WHERE pg_class.relname = #{connection.quote(INDEX_NAME)}
    SQL
  end
end
