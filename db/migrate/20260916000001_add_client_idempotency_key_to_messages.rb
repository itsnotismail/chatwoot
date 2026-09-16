class AddClientIdempotencyKeyToMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :messages, :client_idempotency_key, :string
  end
end
