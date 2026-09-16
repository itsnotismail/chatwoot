class AddClientIdempotencyKeyIndexToMessages < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :messages, [:account_id, :conversation_id, :client_idempotency_key],
              unique: true,
              where: 'client_idempotency_key IS NOT NULL',
              name: 'index_messages_on_client_idempotency_key',
              algorithm: :concurrently
  end
end
