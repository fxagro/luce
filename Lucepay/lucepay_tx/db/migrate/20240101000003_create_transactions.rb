class CreateTransactions < ActiveRecord::Migration[7.1]
  def up
    create_table :transactions do |t|
      t.references :wallet_from, null: false, foreign_key: { to_table: :wallets }
      t.references :wallet_to, null: false, foreign_key: { to_table: :wallets }
      t.integer :amount_cents, null: false
      t.string :status, null: false
      t.string :client_token, null: false

      t.timestamps
    end

    add_index :transactions, :client_token, unique: true
  end

  def down
    drop_table :transactions
  end
end