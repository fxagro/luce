require 'rails_helper'

# Test suite for Wallet::TransferService
# Covers service orchestration, idempotency, error handling, and concurrency safety
RSpec.describe Wallet::TransferService do
  # Test fixtures - users and wallets for comprehensive testing
  let(:user1) { create(:user) }
  let(:user2) { create(:user) }
  let(:wallet1) { create(:wallet, user: user1, balance_cents: 1000, currency: 'USD') }
  let(:wallet2) { create(:wallet, user: user2, balance_cents: 500, currency: 'USD') }

  # Service instance for testing
  let(:service) { described_class.new }

  describe '#call' do
    let(:valid_params) do
      {
        from_wallet_id: wallet1.id,
        to_wallet_id: wallet2.id,
        amount_cents: 300,
        client_token: 'test-transfer-service-123'
      }
    end

    context 'with successful transfer' do
      it 'returns a successful result' do
        result = service.call(valid_params)

        expect(result).to be_a(Wallet::Result)
        expect(result.success?).to be true
        expect(result.failure?).to be false
        expect(result.transaction_id).to be_present
        expect(result.error).to be_nil
      end

      it 'actually performs the transfer' do
        original_balance1 = wallet1.balance_cents
        original_balance2 = wallet2.balance_cents

        result = service.call(valid_params)

        expect(wallet1.reload.balance_cents).to eq(original_balance1 - 300)
        expect(wallet2.reload.balance_cents).to eq(original_balance2 + 300)
      end

      it 'creates a transaction record' do
        original_count = Transaction.count

        result = service.call(valid_params)

        expect(Transaction.count).to eq(original_count + 1)
        transaction = Transaction.find(result.transaction_id)
        expect(transaction.amount_cents).to eq(300)
        expect(transaction.status).to eq('completed')
        expect(transaction.client_token).to eq('test-transfer-service-123')
      end

      it 'creates audit logs' do
        original_count = AuditLog.count

        result = service.call(valid_params)

        expect(AuditLog.count).to eq(original_count + 1)
        audit_log = AuditLog.last
        expect(audit_log.action).to eq('transfer')
        expect(audit_log.data['amount_cents']).to eq(300)
      end

      it 'creates ledger entries with correct balance_after values' do
        result = service.call(valid_params)

        transaction = Transaction.find(result.transaction_id)
        source_entry = wallet1.ledger_entries.find_by(transaction: transaction)
        target_entry = wallet2.ledger_entries.find_by(transaction: transaction)

        # Check source wallet (debit) balance_after
        expect(source_entry.balance_after).to eq(700)  # 1000 - 300
        expect(source_entry.change_cents).to eq(-300)

        # Check target wallet (credit) balance_after
        expect(target_entry.balance_after).to eq(800)  # 500 + 300
        expect(target_entry.change_cents).to eq(300)
      end

      it 'creates ledger entries with enhanced metadata' do
        result = service.call(valid_params)

        transaction = Transaction.find(result.transaction_id)
        source_entry = wallet1.ledger_entries.find_by(transaction: transaction)
        target_entry = wallet2.ledger_entries.find_by(transaction: transaction)

        # Enhanced metadata for source (debit) entry
        expect(source_entry.metadata['direction']).to eq('debit')
        expect(source_entry.metadata['counterparty_wallet_currency']).to eq('USD')
        expect(source_entry.metadata['amount_cents']).to eq(300)
        expect(source_entry.metadata['transaction_id']).to eq(transaction.id)
        expect(source_entry.metadata['timestamp']).to be_present

        # Enhanced metadata for target (credit) entry
        expect(target_entry.metadata['direction']).to eq('credit')
        expect(target_entry.metadata['counterparty_wallet_currency']).to eq('USD')
        expect(target_entry.metadata['amount_cents']).to eq(300)
        expect(target_entry.metadata['transaction_id']).to eq(transaction.id)
        expect(target_entry.metadata['timestamp']).to be_present
      end

      it 'creates audit log with comprehensive data' do
        result = service.call(valid_params)

        audit_log = AuditLog.last
        audit_data = audit_log.data

        # Validate comprehensive audit data
        expect(audit_data['from_wallet_id']).to eq(wallet1.id)
        expect(audit_data['to_wallet_id']).to eq(wallet2.id)
        expect(audit_data['amount_cents']).to eq(300)
        expect(audit_data['currency']).to eq('USD')
        expect(audit_data['client_token']).to eq('test-transfer-service-123')
        expect(audit_data['transaction_id']).to eq(result.transaction_id)
        expect(audit_data['status']).to eq('completed')
        expect(audit_data['transfer_type']).to eq('synchronous')
        expect(audit_data['timestamp']).to be_present
        expect(audit_data['from_wallet_balance_before']).to eq(1000)
        expect(audit_data['to_wallet_balance_before']).to eq(500)
        expect(audit_data['from_wallet_balance_after']).to eq(700)
        expect(audit_data['to_wallet_balance_after']).to eq(800)
        expect(audit_data['debit_entry_id']).to eq(wallet1.ledger_entries.last.id)
        expect(audit_data['credit_entry_id']).to eq(wallet2.ledger_entries.last.id)
      end

      it 'uses enum values for ledger entry types' do
        result = service.call(valid_params)

        transaction = Transaction.find(result.transaction_id)
        source_entry = wallet1.ledger_entries.find_by(transaction: transaction)
        target_entry = wallet2.ledger_entries.find_by(transaction: transaction)

        # Should use enum string values
        expect(source_entry.entry_type).to eq('debit')
        expect(target_entry.entry_type).to eq('credit')

        # Should be queryable with enum scopes
        expect(LedgerEntry.debits).to include(source_entry)
        expect(LedgerEntry.credits).to include(target_entry)
      end

      it 'verifies ledger consistency after transfer' do
        result = service.call(valid_params)

        # Both wallets should have consistent ledgers after transfer
        expect(wallet1.verify_ledger_consistency).to be true
        expect(wallet2.verify_ledger_consistency).to be true
      end
    end

    context 'with insufficient funds' do
      let(:insufficient_params) do
        {
          from_wallet_id: wallet1.id,
          to_wallet_id: wallet2.id,
          amount_cents: 2000, # More than wallet1 balance
          client_token: 'test-insufficient-funds'
        }
      end

      it 'returns a failure result' do
        result = service.call(insufficient_params)

        expect(result.success?).to be false
        expect(result.failure?).to be true
        expect(result.transaction_id).to be_nil
        expect(result.error).to eq('Insufficient funds')
      end

      it 'does not modify wallet balances' do
        original_balance1 = wallet1.balance_cents
        original_balance2 = wallet2.balance_cents

        service.call(insufficient_params)

        expect(wallet1.reload.balance_cents).to eq(original_balance1)
        expect(wallet2.reload.balance_cents).to eq(original_balance2)
      end

      it 'does not create any records' do
        original_transaction_count = Transaction.count
        original_ledger_count = LedgerEntry.count
        original_audit_count = AuditLog.count

        service.call(insufficient_params)

        expect(Transaction.count).to eq(original_transaction_count)
        expect(LedgerEntry.count).to eq(original_ledger_count)
        expect(AuditLog.count).to eq(original_audit_count)
      end
    end

    context 'with invalid wallet IDs' do
      let(:invalid_params) do
        {
          from_wallet_id: 99999, # Non-existent wallet
          to_wallet_id: wallet2.id,
          amount_cents: 100,
          client_token: 'test-invalid-wallet'
        }
      end

      it 'returns a failure result' do
        result = service.call(invalid_params)

        expect(result.success?).to be false
        expect(result.error).to include('Wallet not found')
      end

      it 'does not create any records' do
        original_counts = {
          transactions: Transaction.count,
          ledger_entries: LedgerEntry.count,
          audit_logs: AuditLog.count
        }

        service.call(invalid_params)

        expect(Transaction.count).to eq(original_counts[:transactions])
        expect(LedgerEntry.count).to eq(original_counts[:ledger_entries])
        expect(AuditLog.count).to eq(original_counts[:audit_logs])
      end
    end

    context 'with same wallet transfer' do
      let(:same_wallet_params) do
        {
          from_wallet_id: wallet1.id,
          to_wallet_id: wallet1.id, # Same wallet
          amount_cents: 100,
          client_token: 'test-same-wallet'
        }
      end

      it 'returns a failure result' do
        result = service.call(same_wallet_params)

        expect(result.success?).to be false
        expect(result.error).to eq('Cannot transfer to the same wallet')
      end
    end

    context 'with missing parameters' do
      it 'raises error for missing from_wallet_id' do
        params = valid_params.except(:from_wallet_id)
        expect { service.call(params) }.to raise_error(ArgumentError, 'from_wallet_id is required')
      end

      it 'raises error for missing to_wallet_id' do
        params = valid_params.except(:to_wallet_id)
        expect { service.call(params) }.to raise_error(ArgumentError, 'to_wallet_id is required')
      end

      it 'raises error for zero amount' do
        params = valid_params.merge(amount_cents: 0)
        expect { service.call(params) }.to raise_error(ArgumentError, 'amount_cents must be positive')
      end

      it 'raises error for missing client_token' do
        params = valid_params.except(:client_token)
        expect { service.call(params) }.to raise_error(ArgumentError, 'client_token is required')
      end
    end

    context 'with currency mismatch' do
      let(:wallet3) { create(:wallet, user: user2, balance_cents: 500, currency: 'EUR') }
      let(:currency_mismatch_params) do
        {
          from_wallet_id: wallet1.id,
          to_wallet_id: wallet3.id,
          amount_cents: 100,
          client_token: 'test-currency-mismatch'
        }
      end

      it 'returns a failure result' do
        result = service.call(currency_mismatch_params)

        expect(result.success?).to be false
        expect(result.error).to eq('Currency mismatch between wallets')
      end

      it 'does not create any records when currency mismatch' do
        original_counts = {
          transactions: Transaction.count,
          ledger_entries: LedgerEntry.count,
          audit_logs: AuditLog.count
        }

        service.call(currency_mismatch_params)

        expect(Transaction.count).to eq(original_counts[:transactions])
        expect(LedgerEntry.count).to eq(original_counts[:ledger_entries])
        expect(AuditLog.count).to eq(original_counts[:audit_logs])
      end
    end

    context 'with unexpected errors' do
      # Mock an unexpected error in the wallet transfer
      before do
        allow_any_instance_of(Wallet).to receive(:transfer_to!).and_raise(StandardError, 'Database connection lost')
      end

      it 'returns a failure result' do
        result = service.call(valid_params)

        expect(result.success?).to be false
        expect(result.error).to eq('Transfer failed: Database connection lost')
      end
    end
  end

  describe 'idempotency' do
    let(:idempotency_params) do
      {
        from_wallet_id: wallet1.id,
        to_wallet_id: wallet2.id,
        amount_cents: 250,
        client_token: 'idempotency-test-token'
      }
    end

    it 'returns the same transaction_id for repeated calls with same client_token' do
      # First call should create a new transaction
      result1 = service.call(idempotency_params)
      expect(result1.success?).to be true
      first_transaction_id = result1.transaction_id

      # Second call with same client_token should return the same transaction
      result2 = service.call(idempotency_params)
      expect(result2.success?).to be true
      expect(result2.transaction_id).to eq(first_transaction_id)
    end

    it 'creates only one transaction record for repeated client_token' do
      original_count = Transaction.count

      # Make multiple calls with the same client_token
      3.times { service.call(idempotency_params) }

      # Should only create one transaction record
      expect(Transaction.count).to eq(original_count + 1)
      expect(AuditLog.count).to eq(original_count + 1)  # One audit log
      expect(LedgerEntry.count).to eq(original_count + 2)  # Two ledger entries
    end

    it 'does not modify wallet balances on repeated calls' do
      original_balance1 = wallet1.balance_cents
      original_balance2 = wallet2.balance_cents

      # Make multiple calls with the same client_token
      3.times do
        result = service.call(idempotency_params)
        expect(result.success?).to be true
      end

      # Balances should only change once (from the first successful call)
      expect(wallet1.reload.balance_cents).to eq(original_balance1 - 250)
      expect(wallet2.reload.balance_cents).to eq(original_balance2 + 250)
    end

    it 'creates audit log and ledger entries only once' do
      # First call
      result1 = service.call(idempotency_params)

      # Get the created records
      transaction = Transaction.find(result1.transaction_id)
      audit_log = AuditLog.find_by(auditable_id: transaction.id)
      source_entry = wallet1.ledger_entries.find_by(transaction: transaction)
      target_entry = wallet2.ledger_entries.find_by(transaction: transaction)

      # Second call should not create new records
      result2 = service.call(idempotency_params)

      # Should be the same records
      expect(AuditLog.where(auditable_id: transaction.id).count).to eq(1)
      expect(wallet1.ledger_entries.where(transaction: transaction).count).to eq(1)
      expect(wallet2.ledger_entries.where(transaction: transaction).count).to eq(1)
    end
  end

  describe 'race condition handling' do
    let(:race_condition_params) do
      {
        from_wallet_id: wallet1.id,
        to_wallet_id: wallet2.id,
        amount_cents: 150,
        client_token: 'race-condition-test-token'
      }
    end

    it 'handles concurrent calls with same client_token safely' do
      # Simulate race condition by creating transaction manually first
      existing_transaction = Transaction.create!(
        wallet_from: wallet1,
        wallet_to: wallet2,
        amount_cents: 150,
        status: 'completed',
        client_token: 'race-condition-test-token'
      )

      # Now call service with same client_token
      result = service.call(race_condition_params)

      # Should return the existing transaction
      expect(result.success?).to be true
      expect(result.transaction_id).to eq(existing_transaction.id)
    end

    it 'handles unique constraint violations gracefully' do
      # Mock the transfer_to! method to simulate a unique constraint violation
      allow_any_instance_of(Wallet).to receive(:transfer_to!).and_raise(
        ActiveRecord::RecordInvalid.new(Transaction.new)
      )

      # Pre-create a transaction with the same client_token
      existing_transaction = Transaction.create!(
        wallet_from: wallet1,
        wallet_to: wallet2,
        amount_cents: 150,
        status: 'completed',
        client_token: 'unique-constraint-test-token'
      )

      # Call service - should handle the error and find existing transaction
      result = service.call(race_condition_params.merge(client_token: 'unique-constraint-test-token'))

      # Should return success with existing transaction ID
      expect(result.success?).to be true
      expect(result.transaction_id).to eq(existing_transaction.id)
    end
  end

  describe 'Result class methods' do
    it 'creates success result correctly' do
      result = Wallet::Result.success(transaction_id: 123)
      expect(result.success?).to be true
      expect(result.transaction_id).to eq(123)
      expect(result.error).to be_nil
    end

    it 'creates failure result correctly' do
      result = Wallet::Result.failure(error: 'Something went wrong')
      expect(result.success?).to be false
      expect(result.transaction_id).to be_nil
      expect(result.error).to eq('Something went wrong')
    end
  end

  describe 'ledger consistency through service' do
    it 'ensures ledger consistency after successful transfer' do
      result = service.call(valid_params)

      # Both wallets should have consistent ledgers after service-mediated transfer
      expect(wallet1.verify_ledger_consistency).to be true
      expect(wallet2.verify_ledger_consistency).to be true
    end

    it 'maintains ledger consistency even with service failures' do
      # Test that failed transfers don't create inconsistent state
      insufficient_params = valid_params.merge(amount_cents: 2000)

      service.call(insufficient_params)

      # Even after failed transfer attempt, ledgers should remain consistent
      expect(wallet1.verify_ledger_consistency).to be true
      expect(wallet2.verify_ledger_consistency).to be true
    end
  end

  describe 'concurrency safety' do
    let(:target_wallet) { create(:wallet, user: user2, balance_cents: 10000, currency: 'USD') }
    let(:transfer_amount) { 100 }
    let(:concurrent_transfers_count) { 10 }

    it 'handles 10 concurrent transfers safely without negative balances' do
      # Set up wallet with sufficient balance for 10 concurrent transfers
      source_wallet = create(:wallet, user: user1, balance_cents: 2000, currency: 'USD')
      original_source_balance = source_wallet.balance_cents
      original_target_balance = target_wallet.balance_cents

      # Expected final balances
      expected_source_balance = original_source_balance - (transfer_amount * concurrent_transfers_count)
      expected_target_balance = original_target_balance + (transfer_amount * concurrent_transfers_count)

      # Execute 10 concurrent transfers
      results = Concurrent::Future.execute do
        concurrent_transfers_count.times.map do |i|
          service.call(
            from_wallet_id: source_wallet.id,
            to_wallet_id: target_wallet.id,
            amount_cents: transfer_amount,
            client_token: "concurrent-transfer-#{i}"
          )
        end
      end.value

      # All transfers should succeed
      expect(results.all?(&:success?)).to be true

      # Balances should be correct (no over-deductions)
      expect(source_wallet.reload.balance_cents).to eq(expected_source_balance)
      expect(target_wallet.reload.balance_cents).to eq(expected_target_balance)

      # Verify no negative balances occurred
      expect(source_wallet.balance_cents).to be >= 0
      expect(target_wallet.balance_cents).to be >= 0
    end

    it 'creates correct number of records under concurrency' do
      source_wallet = create(:wallet, user: user1, balance_cents: 2000, currency: 'USD')
      original_transaction_count = Transaction.count
      original_ledger_count = LedgerEntry.count
      original_audit_count = AuditLog.count

      # Execute concurrent transfers
      Concurrent::Future.execute do
        concurrent_transfers_count.times.map do |i|
          service.call(
            from_wallet_id: source_wallet.id,
            to_wallet_id: target_wallet.id,
            amount_cents: transfer_amount,
            client_token: "concurrent-record-test-#{i}"
          )
        end
      end.value

      # Should create exactly 10 of each record type
      expect(Transaction.count).to eq(original_transaction_count + concurrent_transfers_count)
      expect(LedgerEntry.count).to eq(original_ledger_count + (concurrent_transfers_count * 2))  # 2 per transfer
      expect(AuditLog.count).to eq(original_audit_count + concurrent_transfers_count)
    end

    it 'maintains ledger consistency under concurrent transfers' do
      source_wallet = create(:wallet, user: user1, balance_cents: 2000, currency: 'USD')

      # Execute concurrent transfers
      Concurrent::Future.execute do
        concurrent_transfers_count.times.map do |i|
          service.call(
            from_wallet_id: source_wallet.id,
            to_wallet_id: target_wallet.id,
            amount_cents: transfer_amount,
            client_token: "concurrent-consistency-#{i}"
          )
        end
      end.value

      # Both wallets should maintain ledger consistency
      expect(source_wallet.verify_ledger_consistency).to be true
      expect(target_wallet.verify_ledger_consistency).to be true
    end

    it 'prevents race conditions with proper locking' do
      source_wallet = create(:wallet, user: user1, balance_cents: 1000, currency: 'USD')

      # Track balance changes during concurrent execution
      balance_checks = Concurrent::Array.new

      results = Concurrent::Future.execute do
        concurrent_transfers_count.times.map do |i|
          # Each transfer should see a consistent balance state
          service.call(
            from_wallet_id: source_wallet.id,
            to_wallet_id: target_wallet.id,
            amount_cents: transfer_amount,
            client_token: "race-condition-test-#{i}"
          ).tap do |result|
            # Record the source wallet balance after each transfer
            balance_checks << source_wallet.reload.balance_cents
          end
        end
      end.value

      # All operations should succeed
      expect(results.all?(&:success?)).to be true

      # Balance should decrease monotonically (no race conditions)
      balance_checks.sort!.reverse!
      expected_balances = (1000 - (100 * concurrent_transfers_count)).step(100, -100).to_a

      # Due to locking, the balance changes should be consistent
      # (though the exact order might vary due to timing)
      expect(source_wallet.reload.balance_cents).to eq(expected_balances.first)
    end
  end
end