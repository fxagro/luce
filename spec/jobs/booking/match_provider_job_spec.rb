require 'rails_helper'

RSpec.describe Booking::MatchProviderJob, type: :job do
  include ActiveJob::TestHelper

  let!(:pending_booking) { create(:booking, status: :pending) }
  let!(:confirmed_booking) { create(:booking, status: :confirmed) }
  let!(:failed_booking) { create(:booking, status: :failed) }

  before do
    # Clear metrics before each test
    $BOOKING_METRICS = Hash.new(0)

    # Clear job queues
    clear_enqueued_jobs
    clear_performed_jobs
  end

  after do
    # Clear job queues after each test
    clear_enqueued_jobs
    clear_performed_jobs
  end

  describe "#perform" do
    context "with valid pending booking" do
      it "updates booking status to confirmed on successful matching" do
        # Mock successful provider matching
        allow_any_instance_of(described_class).to receive(:simulate_provider_matching).and_return(true)

        perform_enqueued_jobs do
          described_class.perform_later(pending_booking.id)
        end

        pending_booking.reload
        expect(pending_booking.status).to eq("confirmed")
        expect(pending_booking.matching_attempts).to eq(1)
      end

      it "updates booking status to failed on unsuccessful matching" do
        # Mock failed provider matching
        allow_any_instance_of(described_class).to receive(:simulate_provider_matching).and_return(false)

        perform_enqueued_jobs do
          described_class.perform_later(pending_booking.id)
        end

        pending_booking.reload
        expect(pending_booking.status).to eq("failed")
        expect(pending_booking.matching_attempts).to eq(1)
      end

      it "logs job start" do
        expect(Rails.logger).to receive(:info).with(
          hash_including(
            "event" => "job_started",
            "job_class" => "Booking::MatchProviderJob",
            "booking_id" => pending_booking.id
          )
        )

        perform_enqueued_jobs do
          described_class.perform_later(pending_booking.id)
        end
      end

      it "logs successful provider matching" do
        allow_any_instance_of(described_class).to receive(:simulate_provider_matching).and_return(true)

        expect(Rails.logger).to receive(:info).with(
          hash_including(
            "event" => "provider_matching_success",
            "booking_id" => pending_booking.id,
            "new_status" => "confirmed"
          )
        )

        perform_enqueued_jobs do
          described_class.perform_later(pending_booking.id)
        end
      end

      it "logs failed provider matching" do
        allow_any_instance_of(described_class).to receive(:simulate_provider_matching).and_return(false)

        expect(Rails.logger).to receive(:warn).with(
          hash_including(
            "event" => "provider_matching_failed",
            "booking_id" => pending_booking.id,
            "new_status" => "failed",
            "reason" => "no_providers_available"
          )
        )

        perform_enqueued_jobs do
          described_class.perform_later(pending_booking.id)
        end
      end

      it "updates metrics on successful matching" do
        allow_any_instance_of(described_class).to receive(:simulate_provider_matching).and_return(true)

        perform_enqueued_jobs do
          described_class.perform_later(pending_booking.id)
        end

        expect($BOOKING_METRICS[:matching_completed]).to eq(1)
        expect($BOOKING_METRICS[:matching_failed]).to eq(0)
        expect($BOOKING_METRICS[:matching_error]).to eq(0)
      end

      it "updates metrics on failed matching" do
        allow_any_instance_of(described_class).to receive(:simulate_provider_matching).and_return(false)

        perform_enqueued_jobs do
          described_class.perform_later(pending_booking.id)
        end

        expect($BOOKING_METRICS[:matching_completed]).to eq(0)
        expect($BOOKING_METRICS[:matching_failed]).to eq(1)
        expect($BOOKING_METRICS[:matching_error]).to eq(0)
      end

      it "logs metrics update" do
        allow_any_instance_of(described_class).to receive(:simulate_provider_matching).and_return(true)

        expect(Rails.logger).to receive(:info).with(
          hash_including(
            "event" => "metrics_updated",
            "metric_type" => :matching_completed,
            "current_value" => 1
          )
        )

        perform_enqueued_jobs do
          described_class.perform_later(pending_booking.id)
        end
      end
    end

    context "with non-existent booking" do
      it "handles missing booking gracefully" do
        expect(Rails.logger).to receive(:error).with(
          hash_including(
            "event" => "booking_not_found",
            "booking_id" => 99999
          )
        )

        perform_enqueued_jobs do
          described_class.perform_later(99999)
        end
      end
    end

    context "with non-pending booking" do
      it "skips processing for confirmed booking" do
        expect(Rails.logger).to receive(:warn).with(
          hash_including(
            "event" => "invalid_booking_state",
            "booking_id" => confirmed_booking.id,
            "current_status" => "confirmed"
          )
        )

        perform_enqueued_jobs do
          described_class.perform_later(confirmed_booking.id)
        end

        # Status should remain unchanged
        confirmed_booking.reload
        expect(confirmed_booking.status).to eq("confirmed")
      end

      it "skips processing for failed booking" do
        expect(Rails.logger).to receive(:warn).with(
          hash_including(
            "event" => "invalid_booking_state",
            "booking_id" => failed_booking.id,
            "current_status" => "failed"
          )
        )

        perform_enqueued_jobs do
          described_class.perform_later(failed_booking.id)
        end

        # Status should remain unchanged
        failed_booking.reload
        expect(failed_booking.status).to eq("failed")
      end
    end

    context "with job errors" do
      it "handles and logs errors during processing" do
        # Mock an error during processing
        allow_any_instance_of(described_class).to receive(:simulate_external_api_call).and_raise(StandardError.new("API Error"))

        expect(Rails.logger).to receive(:error).with(
          hash_including(
            "event" => "job_error",
            "booking_id" => pending_booking.id,
            "error" => "API Error",
            "error_class" => "StandardError"
          )
        )

        expect {
          perform_enqueued_jobs do
            described_class.perform_later(pending_booking.id)
          end
        }.to raise_error(StandardError, "API Error")

        # Booking status should be set to failed
        pending_booking.reload
        expect(pending_booking.status).to eq("failed")

        # Metrics should be updated for error
        expect($BOOKING_METRICS[:matching_error]).to eq(1)
      end

      it "updates metrics on error" do
        allow_any_instance_of(described_class).to receive(:simulate_external_api_call).and_raise(StandardError.new("API Error"))

        expect {
          perform_enqueued_jobs do
            described_class.perform_later(pending_booking.id)
          end
        }.to raise_error(StandardError, "API Error")

        expect($BOOKING_METRICS[:matching_error]).to eq(1)
      end
    end

    context "job retry configuration" do
      it "has correct retry settings" do
        expect(described_class.get_sidekiq_options["retry"]).to eq(3)
        expect(described_class.get_sidekiq_options["backtrace"]).to eq(true)
      end
    end

    context "external API simulation" do
      it "simulates external API call with delay" do
        # Mock sleep to avoid actual delay in tests
        allow_any_instance_of(described_class).to receive(:sleep)

        expect_any_instance_of(described_class).to receive(:sleep).with(a_value >= 0.5)

        perform_enqueued_jobs do
          described_class.perform_later(pending_booking.id)
        end
      end
    end
  end
end