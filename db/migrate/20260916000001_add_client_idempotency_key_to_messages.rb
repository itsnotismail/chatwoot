class AddClientIdempotencyKeyToMessages < ActiveRecord::Migration[7.1]
  def up
    # Adding a nullable column is catalogue-only, but it still needs a brief ACCESS EXCLUSIVE lock on a hot table.
    # Fail fast instead of queueing every messages query behind a long-running transaction. SET LOCAL ends with the
    # migration's transaction.
    execute "SET LOCAL lock_timeout = '5s'"
    add_column :messages, :client_idempotency_key, :string
  end

  def down
    execute "SET LOCAL lock_timeout = '5s'"
    remove_column :messages, :client_idempotency_key
  end
end
