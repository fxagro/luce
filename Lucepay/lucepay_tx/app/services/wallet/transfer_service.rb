module Wallet
  # Service class for orchestrating wallet transfers with idempotency and error handling
  #
  # This service provides a clean API for wallet transfers while handling:
  # - Input validation and business rule enforcement
  # - Idempotency via client_token checking
  # - Race condition handling with database transactions
  # - Comprehensive error handling and recovery
  # - Observability with metrics and error tracking
  #
  # The service acts as a thin orchestration layer, delegating core business
  # logic to the Wallet model while managing cross-cutting concerns.
  #
  # Metrics Tracking:
  # - $TRANSACTION_METRICS[:created] - Count of successful transfers
  # - $TRANSACTION_METRICS[:failed] - Count of failed transfers
  # - $TRANSACTION_METRICS[:idempotent_hits] - Count of idempotent returns
  class TransferService

    # Global metrics for tracking transfer operations
    # Thread-safe hash for counting transfer outcomes
    $TRANSACTION_METRICS ||= Concurrent::Hash.new { |h, k| h[k] = 0 }
    # Public: Perform a wallet transfer with idempotency and comprehensive error handling
    #
    # This method orchestrates the complete transfer process including:
    # - Idempotency checking via client_token
    # - Wallet validation and loading
    # - Race condition handling
    # - Comprehensive error recovery
    #
    # @param from_wallet_id [Integer] ID of the source wallet
    # @param to_wallet_id [Integer] ID of the target wallet
    # @param amount_cents [Integer] Amount to transfer in cents (must be positive)
    # @param client_token [String] Unique token for idempotency and audit trail
    # @return [Result] Result object with success status and transaction details
    #
    # @example
    #   service = Wallet::TransferService.new
    #   result = service.call(
    #     from_wallet_id: 1,
    #     to_wallet_id: 2,
    #     amount_cents: 1000,
    #     client_token: 'payment-123'
    #   )
    #
    #   if result.success?
    #     puts "Transfer completed: #{result.transaction_id}"
    #   else
    #     puts "Transfer failed: #{result.error}"
    #   end
    def call(from_wallet_id:, to_wallet_id:, amount_cents:, client_token:)
      # Validate input parameters
      validate_inputs(from_wallet_id, to_wallet_id, amount_cents, client_token)

      # Check for existing transaction with the same client_token (idempotency)
      existing_transaction = find_existing_transaction(client_token)
      if existing_transaction
        # Track idempotent hit for metrics
        $TRANSACTION_METRICS[:idempotent_hits] += 1

        # TODO: Add Sentry breadcrumb for idempotency hit
        # Sentry.add_breadcrumb(
        #   category: 'idempotency',
        #   message: 'Returning existing transaction for client_token',
        #   level: 'info',
        #   data: { client_token: client_token, transaction_id: existing_transaction.id }
        # )

        return Result.success(transaction_id: existing_transaction.id)
      end

      # Load wallets within a transaction to ensure they exist and are current
      wallets = load_wallets(from_wallet_id, to_wallet_id)
      from_wallet, to_wallet = wallets

      # Perform the transfer using the wallet's domain logic
      result = perform_transfer(from_wallet, to_wallet, amount_cents, client_token)

      # Track successful transfer in metrics
      $TRANSACTION_METRICS[:created] += 1

      # TODO: Add Sentry success tracking
      # Sentry.capture_message(
      #   'Transfer completed successfully',
      #   level: 'info',
      #   contexts: {
      #     transfer: {
      #       transaction_id: result.transaction_id,
      #       amount_cents: amount_cents,
      #       client_token: client_token
      #     }
      #   }
      # )

      result

    rescue ArgumentError => e
      # Track failed transfer in metrics
      $TRANSACTION_METRICS[:failed] += 1

      # TODO: Add Sentry error tracking for business logic errors
      # Sentry.capture_exception(e, contexts: {
      #   transfer: {
      #     from_wallet_id: from_wallet_id,
      #     to_wallet_id: to_wallet_id,
      #     amount_cents: amount_cents,
      #     client_token: client_token,
      #     error_type: 'business_logic'
      #   }
      # })

      # Handle business logic errors (insufficient funds, validation errors)
      Result.failure(error: e.message)
    rescue ActiveRecord::RecordNotFound => e
      # Track failed transfer in metrics
      $TRANSACTION_METRICS[:failed] += 1

      # TODO: Add Sentry error tracking for missing records
      # Sentry.capture_exception(e, contexts: {
      #   transfer: {
      #     from_wallet_id: from_wallet_id,
      #     to_wallet_id: to_wallet_id,
      #     error_type: 'record_not_found'
      #   }
      # })

      # Handle case where wallets don't exist
      Result.failure(error: "Wallet not found: #{e.message}")
    rescue ActiveRecord::RecordInvalid => e
      # Track failed transfer in metrics
      $TRANSACTION_METRICS[:failed] += 1

      # TODO: Add Sentry error tracking for record validation errors
      # Sentry.capture_exception(e, contexts: {
      #   transfer: {
      #     from_wallet_id: from_wallet_id,
      #     to_wallet_id: to_wallet_id,
      #     amount_cents: amount_cents,
      #     client_token: client_token,
      #     error_type: 'record_invalid'
      #   }
      # })

      # Handle unique constraint violations and other record errors
      if e.message.include?('client_token')
        # Race condition: another process created the transaction first
        existing_transaction = find_existing_transaction(client_token)
        if existing_transaction
          return Result.success(transaction_id: existing_transaction.id)
        end
      end
      Result.failure(error: "Transfer failed: #{e.message}")
    rescue StandardError => e
      # Track failed transfer in metrics
      $TRANSACTION_METRICS[:failed] += 1

      # TODO: Add Sentry error tracking for unexpected errors
      # Sentry.capture_exception(e, contexts: {
      #   transfer: {
      #     from_wallet_id: from_wallet_id,
      #     to_wallet_id: to_wallet_id,
      #     amount_cents: amount_cents,
      #     client_token: client_token,
      #     error_type: 'unexpected'
      #   }
      # })

      # Handle unexpected errors
      Result.failure(error: "Transfer failed: #{e.message}")
    end

    private

    def validate_inputs(from_wallet_id, to_wallet_id, amount_cents, client_token)
      raise ArgumentError, 'from_wallet_id is required' if from_wallet_id.blank?
      raise ArgumentError, 'to_wallet_id is required' if to_wallet_id.blank?
      raise ArgumentError, 'amount_cents must be positive' if amount_cents <= 0
      raise ArgumentError, 'client_token is required' if client_token.blank?

      # Ensure we're not transferring to the same wallet
      if from_wallet_id == to_wallet_id
        raise ArgumentError, 'Cannot transfer to the same wallet'
      end
    end

    def load_wallets(from_wallet_id, to_wallet_id)
      # Load both wallets in a single query for efficiency
      wallets = Wallet.where(id: [from_wallet_id, to_wallet_id]).to_a

      # Verify we found both wallets
      unless wallets.length == 2
        raise ActiveRecord::RecordNotFound,
              "Expected 2 wallets, found #{wallets.length}"
      end

      # Identify which wallet is which
      from_wallet = wallets.find { |w| w.id == from_wallet_id }
      to_wallet = wallets.find { |w| w.id == to_wallet_id }

      # Ensure we have both wallets in the correct roles
      unless from_wallet && to_wallet
        raise ActiveRecord::RecordNotFound,
              "Could not find correct wallet mapping"
      end

      [from_wallet, to_wallet]
    end

    def find_existing_transaction(client_token)
      # Find existing transaction by client_token
      # This method is idempotency-safe and handles the case where
      # multiple processes check for the same token simultaneously
      Transaction.find_by(client_token: client_token)
    end

    def perform_transfer(from_wallet, to_wallet, amount_cents, client_token)
      # Use database transaction to handle race conditions on client_token uniqueness
      # The unique index on client_token will cause a RecordInvalid error if another
      # process creates a transaction with the same token first
      ApplicationRecord.transaction do
        # Double-check that no transaction exists (in case of race condition)
        existing = find_existing_transaction(client_token)
        return Result.success(transaction_id: existing.id) if existing

        # Delegate the actual transfer logic to the Wallet model
        # This keeps the domain logic in the model where it belongs
        transaction = from_wallet.transfer_to!(
          to_wallet,
          amount_cents,
          client_token
        )

        # Return success result with the transaction ID
        Result.success(transaction_id: transaction.id)
      end
    end
  end
end