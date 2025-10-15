module Booking
  class MatchProviderJob
    include Sidekiq::Job

    # Retry configuration for failed jobs
    sidekiq_options retry: 3, backtrace: true

    def perform(booking_id)
      start_time = Time.current

      Rails.logger.info(
        "Provider matching job started",
        {
          event: "job_started",
          job_class: self.class.name,
          booking_id: booking_id,
          job_id: jid,
          timestamp: start_time.iso8601
        }
      )

      # Find the booking
      booking = ::Booking.find_by(id: booking_id)

      unless booking
        Rails.logger.error(
          "Booking not found for provider matching",
          {
            event: "booking_not_found",
            job_class: self.class.name,
            booking_id: booking_id,
            job_id: jid,
            timestamp: Time.current.iso8601
          }
        )
        return
      end

      # Check if booking is in correct state
      unless booking.pending?
        Rails.logger.warn(
          "Booking not in pending state, skipping provider matching",
          {
            event: "invalid_booking_state",
            job_class: self.class.name,
            booking_id: booking_id,
            current_status: booking.status,
            job_id: jid,
            timestamp: Time.current.iso8601
          }
        )
        return
      end

      begin
        # Simulate external API call with random delay (0.5-1.0 seconds)
        simulate_external_api_call

        # Simulate provider matching logic
        # In real implementation, this would call external APIs
        provider_matched = simulate_provider_matching

        if provider_matched
          # Update booking status to confirmed
          booking.update!(status: :confirmed)

          Rails.logger.info(
            "Provider matching completed successfully",
            {
              event: "provider_matching_success",
              job_class: self.class.name,
              booking_id: booking_id,
              new_status: booking.status,
              job_id: jid,
              duration_ms: ((Time.current - start_time) * 1000).round,
              timestamp: Time.current.iso8601
            }
          )

          # Update metrics
          update_metrics(:matching_completed)
        else
          # Update booking status to failed
          booking.update!(status: :failed)

          Rails.logger.warn(
            "Provider matching failed - no providers available",
            {
              event: "provider_matching_failed",
              job_class: self.class.name,
              booking_id: booking_id,
              new_status: booking.status,
              reason: "no_providers_available",
              job_id: jid,
              duration_ms: ((Time.current - start_time) * 1000).round,
              timestamp: Time.current.iso8601
            }
          )

          # Update metrics
          update_metrics(:matching_failed)
        end

        # Increment matching attempts counter
        booking.increment!(:matching_attempts)

      rescue StandardError => e
        # Update booking status to failed
        booking.update!(status: :failed) if booking.persisted?

        Rails.logger.error(
          "Provider matching job failed with error",
          {
            event: "job_error",
            job_class: self.class.name,
            booking_id: booking_id,
            error: e.message,
            error_class: e.class.name,
            job_id: jid,
            duration_ms: ((Time.current - start_time) * 1000).round,
            timestamp: Time.current.iso8601
          }
        )

        # Update metrics
        update_metrics(:matching_error)

        # Re-raise to trigger Sidekiq retry mechanism
        raise e
      end
    end

    private

    def simulate_external_api_call
      # Simulate network delay for external API call
      delay = 0.5 + rand * 0.5  # Random delay between 0.5-1.0 seconds
      sleep delay
    end

    def simulate_provider_matching
      # Simulate provider availability check
      # In real implementation, this would call external APIs to find available providers
      # For demo purposes, randomly return true/false with 80% success rate
      rand < 0.8
    end

    def update_metrics(metric_type)
      # Update global metrics counter
      # In real implementation, this would use a proper metrics library like Prometheus
      $BOOKING_METRICS ||= Hash.new(0)
      $BOOKING_METRICS[metric_type] += 1

      Rails.logger.info(
        "Metrics updated",
        {
          event: "metrics_updated",
          metric_type: metric_type,
          current_value: $BOOKING_METRICS[metric_type],
          timestamp: Time.current.iso8601
        }
      )
    end
  end
end