class CreateLedgerEntries < ActiveRecord::Migration[7.1]
  def up
    create_table :ledger_entries do |t|
      t.references :transaction, null: false, foreign_key: true
      t.references :wallet, null: false, foreign_key: true
      t.integer :change_cents, null: false
      t.integer :balance_after, null: false
      t.string :entry_type, null: false
      t.jsonb :metadata, default: {}

      t.timestamps
    end
  end

  def down
    drop_table :ledger_entries
  end
end