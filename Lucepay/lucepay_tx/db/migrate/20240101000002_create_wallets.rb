class CreateWallets < ActiveRecord::Migration[7.1]
  def up
    create_table :wallets do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :balance_cents, limit: 8, null: false, default: 0
      t.string :currency, null: false, default: 'USD'
      t.datetime :locked_at

      t.timestamps
    end
  end

  def down
    drop_table :wallets
  end
end