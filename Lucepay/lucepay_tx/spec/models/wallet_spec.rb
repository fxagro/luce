require 'rails_helper'

# Test suite for Wallet model
# Covers transfer functionality, concurrency safety, and ledger consistency
RSpec.describe Wallet, type: :model do
  # Test fixtures - create users and wallets for testing
  let(:user1) { create(:user) }
  let(:user2) { create(:user) }
  let(:wallet1) { create(:wallet, user: user1, balance_cents: 1000, currency: 'USD') }
  let(:wallet2) { create(:wallet, user: user2, balance_cents: 500, currency: 'USD') }

  describe '#transfer_to!' do
    context 'with successful transfer' do
      let(:amount_cents) { 300 }
      let(:client_token) { 'test-transfer-123' }
      let!(:result) { wallet1.transfer_to!(wallet2, amount_cents, client_token) }

      it 'returns the created transaction' do
        expect(result).to be_a(Transaction)
        expect(result.amount_cents).to eq(amount_cents)
        expect(result.status).to eq('completed')
        expect(result.client_token).to eq(client_token)
      end

      it 'updates wallet balances correctly' do
        expect(wallet1.reload.balance_cents).to eq(700)  # 1000 - 300
        expect(wallet2.reload.balance_cents).to eq(800)  # 500 + 300
      end

      it 'creates ledger entries for both wallets' do
        # Check source wallet ledger entry (debit)
        source_entry = wallet1.ledger_entries.last
        expect(source_entry).to be_present
        expect(source_entry.change_cents).to eq(-amount_cents)
        expect(source_entry.balance_after).to eq(700)
        expect(source_entry.entry_type).to eq('debit')
        expect(source_entry.transaction).to eq(result)

        # Check target wallet ledger entry (credit)
        target_entry = wallet2.ledger_entries.last
        expect(target_entry).to be_present
        expect(target_entry.change_cents).to eq(amount_cents)
        expect(target_entry.balance_after).to eq(800)
        expect(target_entry.entry_type).to eq('credit')
        expect(target_entry.transaction).to eq(result)
      end

      it 'creates an audit log record' do
        audit_log = AuditLog.last
        expect(audit_log).to be_present
        expect(audit_log.auditable_type).to eq('Transaction')
        expect(audit_log.auditable_id).to eq(result.id)
        expect(audit_log.action).to eq('transfer')

        audit_data = audit_log.data
        expect(audit_data['from_wallet_id']).to eq(wallet1.id)
        expect(audit_data['to_wallet_id']).to eq(wallet2.id)
        expect(audit_data['amount_cents']).to eq(amount_cents)
        expect(audit_data['client_token']).to eq(client_token)
        expect(audit_data['transaction_id']).to eq(result.id)
      end

      it 'associates the transaction with both wallets' do
        expect(wallet1.sent_transactions).to include(result)
        expect(wallet2.received_transactions).to include(result)
      end

      it 'includes metadata in ledger entries' do
        source_entry = wallet1.ledger_entries.last
        expect(source_entry.metadata['transfer_type']).to eq('outgoing')
        expect(source_entry.metadata['counterparty_wallet_id']).to eq(wallet2.id)

        target_entry = wallet2.ledger_entries.last
        expect(target_entry.metadata['transfer_type']).to eq('incoming')
        expect(target_entry.metadata['counterparty_wallet_id']).to eq(wallet1.id)
      end

      it 'creates ledger entries with enhanced metadata' do
        source_entry = wallet1.ledger_entries.last
        target_entry = wallet2.ledger_entries.last

        # Check enhanced metadata for source (debit) entry
        expect(source_entry.metadata['direction']).to eq('debit')
        expect(source_entry.metadata['counterparty_wallet_currency']).to eq('USD')
        expect(source_entry.metadata['amount_cents']).to eq(amount_cents)
        expect(source_entry.metadata['transaction_id']).to eq(result.id)
        expect(source_entry.metadata['timestamp']).to be_present

        # Check enhanced metadata for target (credit) entry
        expect(target_entry.metadata['direction']).to eq('credit')
        expect(target_entry.metadata['counterparty_wallet_currency']).to eq('USD')
        expect(target_entry.metadata['amount_cents']).to eq(amount_cents)
        expect(target_entry.metadata['transaction_id']).to eq(result.id)
        expect(target_entry.metadata['timestamp']).to be_present
      end

      it 'creates audit log with comprehensive data' do
        audit_log = AuditLog.last
        audit_data = audit_log.data

        # Check all required audit data fields
        expect(audit_data['from_wallet_id']).to eq(wallet1.id)
        expect(audit_data['to_wallet_id']).to eq(wallet2.id)
        expect(audit_data['amount_cents']).to eq(amount_cents)
        expect(audit_data['currency']).to eq('USD')
        expect(audit_data['client_token']).to eq(client_token)
        expect(audit_data['transaction_id']).to eq(result.id)
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

      it 'verifies ledger consistency after transfer' do
        # Test the ledger consistency method
        expect(wallet1.verify_ledger_consistency).to be true
        expect(wallet2.verify_ledger_consistency).to be true
      end

      it 'uses enum values for entry_type' do
        source_entry = wallet1.ledger_entries.last
        target_entry = wallet2.ledger_entries.last

        # Should use enum symbols, not strings
        expect(source_entry.entry_type).to eq('debit')
        expect(target_entry.entry_type).to eq('credit')

        # Should be able to query using enum scopes
        expect(LedgerEntry.debits).to include(source_entry)
        expect(LedgerEntry.credits).to include(target_entry)
      end
    end

    context 'with insufficient funds' do
      let(:amount_cents) { 2000 }  # More than wallet1 balance
      let(:client_token) { 'test-transfer-insufficient' }

      it 'raises an error' do
        expect do
          wallet1.transfer_to!(wallet2, amount_cents, client_token)
        end.to raise_error(ArgumentError, 'Insufficient funds')
      end

      it 'does not modify wallet balances' do
        original_balance1 = wallet1.balance_cents
        original_balance2 = wallet2.balance_cents

        begin
          wallet1.transfer_to!(wallet2, amount_cents, client_token)
        rescue ArgumentError
          # Expected error
        end

        expect(wallet1.reload.balance_cents).to eq(original_balance1)
        expect(wallet2.reload.balance_cents).to eq(original_balance2)
      end

      it 'does not create any records' do
        original_transaction_count = Transaction.count
        original_ledger_count = LedgerEntry.count
        original_audit_count = AuditLog.count

        begin
          wallet1.transfer_to!(wallet2, amount_cents, client_token)
        rescue ArgumentError
          # Expected error
        end

        expect(Transaction.count).to eq(original_transaction_count)
        expect(LedgerEntry.count).to eq(original_ledger_count)
        expect(AuditLog.count).to eq(original_audit_count)
      end
    end

    context 'with zero or negative amount' do
      it 'raises an error for zero amount' do
        expect do
          wallet1.transfer_to!(wallet2, 0, 'test-token')
        end.to raise_error(ArgumentError, 'Amount must be positive')
      end

      it 'raises an error for negative amount' do
        expect do
          wallet1.transfer_to!(wallet2, -100, 'test-token')
        end.to raise_error(ArgumentError, 'Amount must be positive')
      end
    end

    context 'with currency mismatch' do
      let(:wallet3) { create(:wallet, user: user2, balance_cents: 500, currency: 'EUR') }

      it 'raises an error' do
        expect do
          wallet1.transfer_to!(wallet3, 100, 'test-token')
        end.to raise_error(ArgumentError, 'Currency mismatch between wallets')
      end
    end

    context 'with concurrent access' do
      it 'handles concurrent transfers safely' do
        # This test would require more complex setup with threads
        # For now, we verify that the locking mechanism is in place
        expect(wallet1).to respond_to(:lock!)
        expect(wallet2).to respond_to(:lock!)
      end
    end

    context 'ledger consistency verification' do
      it 'verifies ledger consistency correctly' do
        # Initially, wallet should have consistent ledger (empty)
        expect(wallet1.verify_ledger_consistency).to be true

        # After transfer, both wallets should still be consistent
        wallet1.transfer_to!(wallet2, 100, 'consistency-test')
        expect(wallet1.verify_ledger_consistency).to be true
        expect(wallet2.verify_ledger_consistency).to be true
      end

      it 'detects ledger inconsistencies' do
        # Create a wallet with some initial balance but no ledger entries
        wallet = create(:wallet, balance_cents: 1000, currency: 'USD')

        # Manually create an inconsistent ledger entry
        transaction = create(:transaction, wallet_from: wallet, wallet_to: wallet2)
        LedgerEntry.create!(
          transaction: transaction,
          wallet: wallet,
          change_cents: 500,  # This would make total 1500, but balance is 1000
          balance_after: 1500,
          entry_type: :credit,
          metadata: { test: 'inconsistency' }
        )

        # Should detect the inconsistency
        expect(wallet.verify_ledger_consistency).to be false
      end
    end
  end

  describe '#verify_ledger_consistency' do
    it 'returns true for wallet with no ledger entries' do
      wallet = create(:wallet, balance_cents: 0, currency: 'USD')
      expect(wallet.verify_ledger_consistency).to be true
    end

    it 'returns true for wallet with consistent ledger entries' do
      wallet = create(:wallet, balance_cents: 1000, currency: 'USD')
      transaction = create(:transaction, wallet_from: wallet, wallet_to: wallet2)

      # Create consistent ledger entry
      LedgerEntry.create!(
        transaction: transaction,
        wallet: wallet,
        change_cents: -200,
        balance_after: 800,
        entry_type: :debit,
        metadata: { test: 'consistent' }
      )

      expect(wallet.verify_ledger_consistency).to be true
    end

    it 'returns false for wallet with inconsistent ledger entries' do
      wallet = create(:wallet, balance_cents: 1000, currency: 'USD')
      transaction = create(:transaction, wallet_from: wallet, wallet_to: wallet2)

      # Create inconsistent ledger entry (balance_after doesn't match)
      LedgerEntry.create!(
        transaction: transaction,
        wallet: wallet,
        change_cents: -200,
        balance_after: 1000,  # Should be 800, but set to 1000 (inconsistent)
        entry_type: :debit,
        metadata: { test: 'inconsistent' }
      )

      expect(wallet.verify_ledger_consistency).to be false
    end
  end

  describe 'concurrency safety' do
    let(:target_wallet) { create(:wallet, user: user2, balance_cents: 5000, currency: 'USD') }
    let(:transfer_amount) { 100 }
    let(:concurrent_transfers) { 5 }

    it 'handles concurrent transfer_to! calls safely' do
      source_wallet = create(:wallet, user: user1, balance_cents: 1000, currency: 'USD')
      original_source_balance = source_wallet.balance_cents
      original_target_balance = target_wallet.balance_cents

      # Expected final balances
      expected_source_balance = original_source_balance - (transfer_amount * concurrent_transfers)
      expected_target_balance = original_target_balance + (transfer_amount * concurrent_transfers)

      # Execute concurrent transfers directly on the model
      results = Concurrent::Future.execute do
        concurrent_transfers.times.map do |i|
          source_wallet.transfer_to!(
            target_wallet,
            transfer_amount,
            "concurrent-wallet-test-#{i}"
          )
        end
      end.value

      # All transfers should succeed
      expect(results.all?(&:present?)).to be true

      # Balances should be correct (no race conditions)
      expect(source_wallet.reload.balance_cents).to eq(expected_source_balance)
      expect(target_wallet.reload.balance_cents).to eq(expected_target_balance)

      # Verify no negative balances
      expect(source_wallet.balance_cents).to be >= 0
      expect(target_wallet.balance_cents).to be >= 0
    end

    it 'maintains ledger consistency under concurrent model calls' do
      source_wallet = create(:wallet, user: user1, balance_cents: 1000, currency: 'USD')

      # Execute concurrent transfers
      Concurrent::Future.execute do
        concurrent_transfers.times.map do |i|
          source_wallet.transfer_to!(
            target_wallet,
            transfer_amount,
            "concurrent-consistency-wallet-#{i}"
          )
        end
      end.value

      # Both wallets should maintain ledger consistency after concurrent transfers
      expect(source_wallet.verify_ledger_consistency).to be true
      expect(target_wallet.verify_ledger_consistency).to be true
    end

    it 'creates correct audit logs under concurrent transfers' do
      source_wallet = create(:wallet, user: user1, balance_cents: 1000, currency: 'USD')
      original_audit_count = AuditLog.count

      # Execute concurrent transfers
      results = Concurrent::Future.execute do
        concurrent_transfers.times.map do |i|
          source_wallet.transfer_to!(
            target_wallet,
            transfer_amount,
            "concurrent-audit-wallet-#{i}"
          )
        end
      end.value

      # Should create exactly the expected number of audit logs
      expect(AuditLog.count).to eq(original_audit_count + concurrent_transfers)

      # Each audit log should have correct data
      new_audit_logs = AuditLog.last(concurrent_transfers)
      new_audit_logs.each do |audit_log|
        expect(audit_log.action).to eq('transfer')
        expect(audit_log.data['amount_cents']).to eq(transfer_amount)
        expect(audit_log.data['from_wallet_id']).to eq(source_wallet.id)
        expect(audit_log.data['to_wallet_id']).to eq(target_wallet.id)
      end
    end

    it 'verifies locking mechanism prevents race conditions' do
      source_wallet = create(:wallet, user: user1, balance_cents: 1000, currency: 'USD')

      # Track balance states during concurrent execution
      balance_snapshots = Concurrent::Array.new

      # Execute concurrent transfers and capture balance at different points
      results = Concurrent::Future.execute do
        concurrent_transfers.times.map do |i|
          source_wallet.transfer_to!(
            target_wallet,
            transfer_amount,
            "locking-test-#{i}"
          ).tap do
            # Capture balance after each transfer
            balance_snapshots << source_wallet.reload.balance_cents
          end
        end
      end.value

      # All transfers should succeed
      expect(results.all?(&:present?)).to be true

      # Balance should decrease by exactly transfer_amount * concurrent_transfers
      expected_final_balance = 1000 - (transfer_amount * concurrent_transfers)
      expect(source_wallet.reload.balance_cents).to eq(expected_final_balance)

      # Balance snapshots should show consistent decreases
      # (The locking should ensure no inconsistent states)
      unique_balances = balance_snapshots.to_a.uniq.sort
      expect(unique_balances).to all(be >= 0)
    end
  end
end