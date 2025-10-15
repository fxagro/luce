module Wallet
  # Result object to encapsulate the outcome of wallet operations
  #
  # This class implements the Result pattern to provide a consistent interface
  # for success/failure responses across wallet operations. It encapsulates
  # the outcome of operations like transfers while maintaining immutability
  # and providing a clean API for result handling.
  #
  # @example Success result
  #   result = Wallet::Result.success(transaction_id: 123)
  #   result.success? # => true
  #   result.transaction_id # => 123
  #
  # @example Failure result
  #   result = Wallet::Result.failure(error: 'Insufficient funds')
  #   result.success? # => false
  #   result.error # => 'Insufficient funds'
  class Result
    attr_reader :success, :transaction_id, :error

    # Initialize with success status, transaction_id, and optional error
    #
    # @param success [Boolean] Whether the operation was successful
    # @param transaction_id [Integer, nil] ID of the created transaction (if successful)
    # @param error [String, nil] Error message (if failed)
    def initialize(success:, transaction_id: nil, error: nil)
      @success = success
      @transaction_id = transaction_id
      @error = error
    end

    # Public: Check if the operation was successful
    #
    # An operation is considered successful if success is true AND error is nil.
    # This ensures we don't have false positives from partially successful operations.
    #
    # @return [Boolean] true if operation was successful
    #
    # @example
    #   result = Wallet::Result.success(transaction_id: 123)
    #   result.success? # => true
    #
    #   result = Wallet::Result.failure(error: 'Something went wrong')
    #   result.success? # => false
    def success?
      @success && @error.nil?
    end

    # Public: Check if the operation failed
    #
    # Convenience method that returns the opposite of success?
    #
    # @return [Boolean] true if operation failed
    def failure?
      !success?
    end

    # Public: Class method to create a successful result
    #
    # @param transaction_id [Integer] ID of the successful transaction
    # @return [Result] Success result object
    def self.success(transaction_id:)
      new(success: true, transaction_id: transaction_id)
    end

    # Public: Class method to create a failure result
    #
    # @param error [String] Error message describing the failure
    # @return [Result] Failure result object
    def self.failure(error:)
      new(success: false, error: error)
    end
  end
end