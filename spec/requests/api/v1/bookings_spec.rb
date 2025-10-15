require 'rails_helper'

RSpec.describe "Api::V1::Bookings", type: :request do
  describe "POST /api/v1/bookings" do
    let(:valid_params) do
      {
        booking: {
          customer_id: 1,
          service_id: 2,
          client_token: "unique-client-token-123"
        }
      }
    end

    let(:invalid_params) do
      {
        booking: {
          customer_id: "",
          service_id: "",
          client_token: ""
        }
      }
    end

    before do
      # Clear metrics before each test
      $BOOKING_METRICS = Hash.new(0)
    end

    context "with valid parameters" do
      it "creates a new booking successfully" do
        expect {
          post "/api/v1/bookings", params: valid_params
        }.to change(Booking, :count).by(1)

        expect(response).to have_http_status(:accepted)

        json_response = JSON.parse(response.body)
        expect(json_response["booking_id"]).to be_present
        expect(json_response["status"]).to eq("pending")
        expect(json_response["message"]).to eq("Booking created successfully. Provider matching in progress.")
        expect(json_response["client_token"]).to eq("unique-client-token-123")
        expect(json_response["created_at"]).to be_present
      end

      it "enqueues a MatchProviderJob" do
        expect {
          post "/api/v1/bookings", params: valid_params
        }.to change(Booking::MatchProviderJob.jobs, :size).by(1)

        job = Booking::MatchProviderJob.jobs.last
        expect(job["args"]).to eq([Booking.last.id])
      end

      it "logs booking creation" do
        expect(Rails.logger).to receive(:info).with(
          hash_including(
            "event" => "booking_received",
            "customer_id" => 1,
            "service_id" => 2,
            "client_token" => "unique-client-token-123"
          )
        )

        expect(Rails.logger).to receive(:info).with(
          hash_including(
            "event" => "booking_created",
            "status" => "pending"
          )
        )

        post "/api/v1/bookings", params: valid_params
      end
    end

    context "with invalid parameters" do
      it "returns unprocessable entity status" do
        post "/api/v1/bookings", params: invalid_params

        expect(response).to have_http_status(:unprocessable_entity)

        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Booking creation failed")
        expect(json_response["errors"]).to be_present
        expect(json_response["client_token"]).to eq("")
      end

      it "does not create a booking" do
        expect {
          post "/api/v1/bookings", params: invalid_params
        }.not_to change(Booking, :count)
      end

      it "logs validation failure" do
        expect(Rails.logger).to receive(:warn).with(
          hash_including(
            "event" => "booking_validation_failed"
          )
        )

        expect(Rails.logger).to receive(:error).with(
          hash_including(
            "event" => "booking_creation_failed"
          )
        )

        post "/api/v1/bookings", params: invalid_params
      end
    end

    context "idempotency" do
      let!(:existing_booking) { create(:booking, client_token: "existing-token") }

      it "returns existing booking for duplicate client_token" do
        duplicate_params = {
          booking: {
            customer_id: 999,
            service_id: 999,
            client_token: "existing-token"
          }
        }

        expect {
          post "/api/v1/bookings", params: duplicate_params
        }.not_to change(Booking, :count)

        expect(response).to have_http_status(:accepted)

        json_response = JSON.parse(response.body)
        expect(json_response["booking_id"]).to eq(existing_booking.id)
        expect(json_response["client_token"]).to eq("existing-token")
      end

      it "logs existing booking found" do
        duplicate_params = {
          booking: {
            customer_id: 999,
            service_id: 999,
            client_token: "existing-token"
          }
        }

        expect(Rails.logger).to receive(:info).with(
          hash_including(
            "event" => "existing_booking_found",
            "booking_id" => existing_booking.id,
            "client_token" => "existing-token"
          )
        )

        post "/api/v1/bookings", params: duplicate_params
      end
    end

    context "race condition handling" do
      it "handles concurrent requests with same client_token" do
        # This test would require more complex setup to properly test race conditions
        # For now, we test that the service handles RecordNotUnique errors gracefully
        allow_any_instance_of(Booking).to receive(:save).and_raise(ActiveRecord::RecordNotUnique.new("Duplicate entry"))

        post "/api/v1/bookings", params: valid_params

        # Should handle the race condition gracefully
        expect(response).to have_http_status(:accepted)
      end
    end
  end
end