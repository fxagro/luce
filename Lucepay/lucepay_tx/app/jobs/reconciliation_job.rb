# Sidekiq job for daily ledger reconciliation
# Performs consistency checks across all wallets to ensure financial data integrity
class ReconciliationJob
  include Sidekiq::Job

  # Perform daily reconciliation of all wallet ledgers
  #
  # This job iterates through all wallets and verifies that the sum of their
  # ledger entries matches their current balance. Any inconsistencies are logged
  # for investigation and can trigger alerts in production environments.
  #
  # In a production system, this job would typically:
  # - Run daily during low-traffic periods
  # - Send alerts for critical inconsistencies
  # - Generate compliance reports
  # - Trigger automatic recovery procedures if configured
  #
  # @example Schedule with sidekiq-scheduler
  #   ReconciliationJob.perform_at_daily('2:00 AM')
  def perform
    Rails.logger.info('Starting daily ledger reconciliation')

    total_wallets = 0
    inconsistent_wallets = 0
    start_time = Time.current

    # Process all wallets for ledger consistency verification
    Wallet.find_each do |wallet|
      total_wallets += 1

      begin
        # Use the existing verify_ledger_consistency method from Day 3
        is_consistent = wallet.verify_ledger_consistency

        unless is_consistent
          inconsistent_wallets += 1

          # Log detailed information about the inconsistency
          Rails.logger.warn(
            'Ledger inconsistency detected during reconciliation',
            wallet_id: wallet.id,
            user_id: wallet.user_id,
            currency: wallet.currency,
            balance_cents: wallet.balance_cents,
            ledger_sum: wallet.ledger_entries.sum(:change_cents),
            difference: wallet.balance_cents - wallet.ledger_entries.sum(:change_cents),
            reconciliation_job_id: jid,
            timestamp: Time.current.iso8601
          )

          # TODO: In production, trigger alerts here
          # SlackNotificationService.call(:ledger_inconsistency, wallet)
          # PagerDutyAlertService.call(:critical, wallet) if critical_threshold_exceeded?
        end

      rescue StandardError => e
        # Log any errors during reconciliation process
        Rails.logger.error(
          'Error during wallet reconciliation',
          wallet_id: wallet.id,
          error: e.message,
          backtrace: e.backtrace.first,
          reconciliation_job_id: jid
        )

        inconsistent_wallets += 1
      end
    end

    # Log reconciliation summary
    duration = Time.current - start_time
    Rails.logger.info(
      'Completed daily ledger reconciliation',
      total_wallets: total_wallets,
      inconsistent_wallets: inconsistent_wallets,
      duration_seconds: duration,
      reconciliation_job_id: jid,
      timestamp: Time.current.iso8601
    )

    # TODO: Send daily reconciliation report
    # ReconciliationReportService.call(total_wallets, inconsistent_wallets, duration)
  end

  # Schedule this job to run daily at 2:00 AM
  # This method assumes sidekiq-scheduler is configured
  def self.schedule_daily
    # Set to run at 2:00 AM daily
    perform_at_daily('2:00 AM')
  rescue StandardError => e
    Rails.logger.error('Failed to schedule reconciliation job', error: e.message)
  end

  # Alternative scheduling for different intervals (for testing or different environments)
  def self.schedule_hourly
    perform_in(1.hour)
  end

  def self.schedule_weekly
    perform_at_weekly('sunday', '2:00 AM')
  end
end