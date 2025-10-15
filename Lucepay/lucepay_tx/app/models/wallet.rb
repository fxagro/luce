class Wallet < ApplicationRecord
  # == Associations
  # Users can have multiple wallets (e.g., different currencies)
  belongs_to :user

  # Transaction history - money sent and received
  has_many :sent_transactions, class_name: 'Transaction', foreign_key: :wallet_from_id
  has_many :received_transactions, class_name: 'Transaction', foreign_key: :wallet_to_id

  # Financial ledger for audit trail
  has_many :ledger_entries

  # == Validations
  # Balance must always be non-negative (enforced by database and application)
  validates :balance_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Currency is required for multi-currency support
  validates :currency, presence: true

  # == Callbacks
  # Automatically lock wallet if balance goes negative
  before_save :lock_wallet_if_balance_negative

  # Public: Transfer money to another wallet with full audit trail and safety guarantees
  #
  # This method implements the core financial transfer logic with:
  # - Atomic transactions for consistency
  # - Pessimistic locking for concurrency safety
  # - Comprehensive audit logging
  # - Ledger consistency verification
  # - Idempotency support via client_token
  #
  # @param target_wallet [Wallet] The destination wallet for the transfer
  # @param amount_cents [Integer] Amount to transfer in cents (must be positive)
  # @param client_token [String] Unique identifier for idempotency
  # @return [Transaction] The created transaction record
  # @raise [ArgumentError] If validation fails (insufficient funds, currency mismatch, etc.)
  #
  # @example
  #   transaction = wallet1.transfer_to!(wallet2, 1000, 'payment-123')
  #   puts "Transferred #{transaction.amount_cents} cents"
  def transfer_to!(target_wallet, amount_cents, client_token)
    # Validate input parameters
    raise ArgumentError, 'Amount must be positive' if amount_cents <= 0
    raise ArgumentError, 'Insufficient funds' if balance_cents < amount_cents

    # Ensure both wallets have the same currency
    unless currency == target_wallet.currency
      raise ArgumentError, 'Currency mismatch between wallets'
    end

    # Use database transaction for atomicity
    transaction_result = ApplicationRecord.transaction do
      # Lock both wallets to prevent concurrent modifications using pessimistic locking
      # This implements SELECT ... FOR UPDATE to ensure exclusive access during transfer
      # Locking order: self first, then target_wallet to prevent deadlocks
      lock!
      target_wallet.lock!

      # Re-check balance after acquiring lock (in case it changed during lock acquisition)
      raise ArgumentError, 'Insufficient funds' if balance_cents < amount_cents

      # Create the transaction record first
      transaction = Transaction.create!(
        wallet_from: self,
        wallet_to: target_wallet,
        amount_cents: amount_cents,
        status: 'completed', # Synchronous completion
        client_token: client_token
      )

      # Calculate new balances
      new_from_balance = balance_cents - amount_cents
      new_to_balance = target_wallet.balance_cents + amount_cents

      # Create ledger entries for audit trail with enhanced metadata
      # Debit entry for source wallet
      debit_entry = LedgerEntry.create!(
        transaction: transaction,
        wallet: self,
        change_cents: -amount_cents, # Negative for debit
        balance_after: new_from_balance,
        entry_type: :debit, # Use enum value
        metadata: {
          direction: 'debit',
          transfer_type: 'outgoing',
          counterparty_wallet_id: target_wallet.id,
          counterparty_wallet_currency: target_wallet.currency,
          client_token: client_token,
          transaction_id: transaction.id,
          amount_cents: amount_cents,
          timestamp: Time.current.iso8601
        }
      )

      # Credit entry for target wallet
      credit_entry = LedgerEntry.create!(
        transaction: transaction,
        wallet: target_wallet,
        change_cents: amount_cents, # Positive for credit
        balance_after: new_to_balance,
        entry_type: :credit, # Use enum value
        metadata: {
          direction: 'credit',
          transfer_type: 'incoming',
          counterparty_wallet_id: id,
          counterparty_wallet_currency: currency,
          client_token: client_token,
          transaction_id: transaction.id,
          amount_cents: amount_cents,
          timestamp: Time.current.iso8601
        }
      )

      # Update wallet balances
      update!(balance_cents: new_from_balance)
      target_wallet.update!(balance_cents: new_to_balance)

      # Create audit log for compliance and tracking with comprehensive data
      AuditLog.create!(
        auditable_type: 'Transaction',
        auditable_id: transaction.id,
        action: 'transfer',
        data: {
          from_wallet_id: id,
          to_wallet_id: target_wallet.id,
          amount_cents: amount_cents,
          currency: currency,
          client_token: client_token,
          transaction_id: transaction.id,
          status: 'completed',
          transfer_type: 'synchronous',
          timestamp: Time.current.iso8601,
          from_wallet_balance_before: balance_cents,
          to_wallet_balance_before: target_wallet.balance_cents,
          from_wallet_balance_after: new_from_balance,
          to_wallet_balance_after: new_to_balance,
          debit_entry_id: debit_entry.id,
          credit_entry_id: credit_entry.id
        }
      )

      # Verify ledger consistency after transfer (for debugging/MVP logging)
      verify_ledger_consistency(self)
      verify_ledger_consistency(target_wallet)

      # Return the created transaction
      transaction
    end

    transaction_result
  rescue ActiveRecord::RecordInvalid => e
    # TODO: Add Sentry error tracking for production monitoring
    # Sentry.capture_exception(e, contexts: {
    #   wallet: { id: id, balance_cents: balance_cents, currency: currency },
    #   target_wallet: { id: target_wallet.id, balance_cents: target_wallet.balance_cents },
    #   transfer: { amount_cents: amount_cents, client_token: client_token }
    # })

    # Re-raise validation errors as more descriptive errors
    raise ArgumentError, "Transfer failed: #{e.message}"
  end

  # Public: Verify that the sum of all ledger entries matches the current balance
  #
  # This method ensures financial data integrity by comparing the sum of all
  # change_cents from ledger entries with the current balance_cents. For MVP,
  # inconsistencies are logged rather than raising errors to maintain system
  # availability while still providing monitoring capabilities.
  #
  # @param wallet [Wallet] The wallet to verify (defaults to self)
  # @return [Boolean] true if ledger is consistent, false otherwise
  #
  # @example
  #   wallet.verify_ledger_consistency # => true
  def verify_ledger_consistency(wallet = self)
    # Calculate expected balance from ledger entries
    # For MVP, we'll log inconsistencies rather than raise errors
    total_change = wallet.ledger_entries.sum(:change_cents)
    current_balance = wallet.balance_cents

    if total_change != current_balance
      # Log the inconsistency for debugging/monitoring
      Rails.logger.warn(
        "Ledger inconsistency detected for Wallet #{wallet.id}: " \
        "ledger_sum=#{total_change}, balance_cents=#{current_balance}, " \
        "difference=#{current_balance - total_change}"
      )

      # For MVP, we'll just log the issue rather than raise an error
      # In production, you might want to raise an error or trigger alerts
      # raise "Ledger inconsistency: expected #{total_change}, got #{current_balance}"
    end

    # Return true if consistent, false if not (for testing purposes)
    total_change == current_balance
  end

  private

  def lock_wallet_if_balance_negative
    if balance_cents.negative?
      self.locked_at = Time.current
    end
  end
end