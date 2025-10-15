class CreateAuditLogs < ActiveRecord::Migration[7.1]
  def up
    create_table :audit_logs do |t|
      t.string :auditable_type, null: false
      t.bigint :auditable_id, null: false
      t.string :action, null: false
      t.jsonb :data, null: false, default: {}

      t.timestamps
    end

    add_index :audit_logs, [:auditable_type, :auditable_id]
  end

  def down
    drop_table :audit_logs
  end
end