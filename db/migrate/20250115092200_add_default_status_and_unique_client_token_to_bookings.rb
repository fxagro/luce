class AddDefaultStatusAndUniqueClientTokenToBookings < ActiveRecord::Migration[7.0]
  def up
    # Add default status to existing bookings if the column doesn't exist yet
    if column_exists?(:bookings, :status)
      # Update any NULL status values to 'pending'
      execute <<-SQL
        UPDATE bookings SET status = 'pending' WHERE status IS NULL
      SQL
    else
      # Add status column with default value
      add_column :bookings, :status, :string, default: 'pending', null: false
    end

    # Add client_token column if it doesn't exist
    unless column_exists?(:bookings, :client_token)
      add_column :bookings, :client_token, :string
    end

    # Add unique index on client_token (only if it doesn't exist)
    unless index_exists?(:bookings, :client_token, unique: true)
      add_index :bookings, :client_token, unique: true
    end

    # Add matching_attempts column if it doesn't exist
    unless column_exists?(:bookings, :matching_attempts)
      add_column :bookings, :matching_attempts, :integer, default: 0, null: false
    end

    # Add database-level validation comments for documentation
    execute <<-SQL
      COMMENT ON COLUMN bookings.status IS 'Current booking status: pending, confirmed, failed';
      COMMENT ON COLUMN bookings.client_token IS 'Unique token for idempotency - prevents duplicate bookings';
      COMMENT ON COLUMN bookings.matching_attempts IS 'Number of provider matching attempts made';
    SQL
  end

  def down
    # Remove the unique index on client_token
    if index_exists?(:bookings, :client_token, unique: true)
      remove_index :bookings, :client_token, unique: true
    end

    # Remove columns in reverse order
    remove_column :bookings, :matching_attempts if column_exists?(:bookings, :matching_attempts)
    remove_column :bookings, :client_token if column_exists?(:bookings, :client_token)

    # Note: We don't remove the status column as it might be used by existing data
    # If you want to remove it completely, uncomment the line below:
    # remove_column :bookings, :status if column_exists?(:bookings, :status)
  end
end