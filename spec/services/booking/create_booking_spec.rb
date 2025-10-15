require 'rails_helper'

RSpec.describe Booking::CreateBooking do
  describe '.call' do
    let(:valid_params) do
      {
        customer_id: 1,
        service_id: 2,
        client_token: "unique-client-token-123"
      }
    end

    let(:invalid_params) do
      {
        customer_id: "",
        service_id: "",
        client_token: ""
      }
    end

    before do
      # Clear any existing bookings
      Booking.delete_all
    end

    context "with valid parameters" do
      it "creates a new booking" do
        result = described_class.call(valid_params)

        expect(result.success?).to be true
        expect(result.booking).to be_persisted
        expect(result.booking.customer_id).to eq(1)
        expect(result.booking.service_id).to eq(2)
        expect(result.booking.client_token).to eq("unique-client-token-123")
        expect(result.booking.status).to eq("pending")
        expect(result.errors).to be_empty
      end

      it "logs booking creation" do
        expect(Rails.logger).to receive(:info).with(
          hash_including(
            "event" => "new_booking_created",
            "customer_id" => 1,
            "service_id" => 2,
            "client_token" => "unique-client-token-123",
            "status" => "pending"
          )
        )

        described_class.call(valid_params)
      end
    end

    context "with invalid parameters" do
      it "fails validation for missing customer_id" do
        params = valid_params.merge(customer_id: "")
        result = described_class.call(params)

        expect(result.success?).to be false
        expect(result.booking).to be_nil
        expect(result.errors).to include("customer_id is required")
      end

      it "fails validation for missing service_id" do
        params = valid_params.merge(service_id: "")
        result = described_class.call(params)

        expect(result.success?).to be false
        expect(result.booking).to be_nil
        expect(result.errors).to include("service_id is required")
      end

      it "fails validation for missing client_token" do
        params = valid_params.merge(client_token: "")
        result = described_class.call(params)

        expect(result.success?).to be false
        expect(result.booking).to be_nil
        expect(result.errors).to include("client_token is required")
      end

      it "logs validation failure" do
        expect(Rails.logger).to receive(:warn).with(
          hash_including(
            "event" => "booking_validation_failed"
          )
        )

        described_class.call(invalid_params)
      end
    end

    context "idempotency" do
      let!(:existing_booking) { create(:booking, client_token: "existing-token") }

      it "returns existing booking for duplicate client_token" do
        result = described_class.call(
          customer_id: 999,
          service_id: 999,
          client_token: "existing-token"
        )

        expect(result.success?).to be true
        expect(result.booking).to eq(existing_booking)
        expect(result.booking.customer_id).to eq(existing_booking.customer_id)
      end

      it "logs existing booking found" do
        expect(Rails.logger).to receive(:info).with(
          hash_including(
            "event" => "existing_booking_found",
            "booking_id" => existing_booking.id,
            "client_token" => "existing-token"
          )
        )

        described_class.call(
          customer_id: 999,
          service_id: 999,
          client_token: "existing-token"
        )
      end
    end

    context "race condition handling" do
      it "handles RecordNotUnique errors gracefully" do
        # Create a booking first
        existing_booking = create(:booking, client_token: "race-condition-token")

        # Mock the save method to raise RecordNotUnique
        allow_any_instance_of(Booking).to receive(:save).and_raise(ActiveRecord::RecordNotUnique.new("Duplicate entry"))

        # Mock find_by to return the existing booking
        allow(Booking).to receive(:find_by).with(client_token: "race-condition-token").and_return(existing_booking)

        result = described_class.call(
          customer_id: 1,
          service_id: 2,
          client_token: "race-condition-token"
        )

        expect(result.success?).to be true
        expect(result.booking).to eq(existing_booking)
      end

      it "logs race condition detection" do
        allow_any_instance_of(Booking).to receive(:save).and_raise(ActiveRecord::RecordNotUnique.new("Duplicate entry"))
        allow(Booking).to receive(:find_by).and_return(nil)

        expect(Rails.logger).to receive(:warn).with(
          hash_including(
            "event" => "client_token_race_condition"
          )
        )

        described_class.call(valid_params)
      end
    end

    context "unexpected errors" do
      it "handles unexpected errors gracefully" do
        # Mock an unexpected error during save
        allow_any_instance_of(Booking).to receive(:save).and_raise(StandardError.new("Unexpected error"))

        expect(Rails.logger).to receive(:error).with(
          hash_including(
            "event" => "create_booking_error",
            "error" => "Unexpected error",
            "error_class" => "StandardError"
          )
        )

        result = described_class.call(valid_params)

        expect(result.success?).to be false
        expect(result.errors).to include("An unexpected error occurred while creating the booking")
      end
    end

    context "database constraint violations" do
      it "handles unique constraint violations" do
        # Create first booking
        create(:booking, client_token: "constraint-token")

        # Try to create another with same token (this should be caught by unique index)
        result = described_class.call(
          customer_id: 1,
          service_id: 2,
          client_token: "constraint-token"
        )

        # Should find existing booking due to unique constraint
        expect(result.success?).to be true
        expect(Booking.count).to eq(1)
      end
    end
  end
end