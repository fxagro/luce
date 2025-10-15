module Api
  module V1
    class BookingsController < ApplicationController
      # POST /api/v1/bookings
      # Creates a new booking with idempotency support
      # Returns HTTP 202 (Accepted) immediately and processes asynchronously
      def create
        # Log booking request received
        Rails.logger.info(
          "Booking request received",
          {
            event: "booking_received",
            customer_id: booking_params[:customer_id],
            service_id: booking_params[:service_id],
            client_token: booking_params[:client_token],
            timestamp: Time.current.iso8601
          }.compact
        )

        # Use service object for booking creation
        result = Booking::CreateBooking.call(
          customer_id: booking_params[:customer_id],
          service_id: booking_params[:service_id],
          client_token: booking_params[:client_token]
        )

        if result.success?
          # Log successful booking creation
          Rails.logger.info(
            "Booking created successfully",
            {
              event: "booking_created",
              booking_id: result.booking.id,
              customer_id: result.booking.customer_id,
              service_id: result.booking.service_id,
              status: result.booking.status,
              client_token: result.booking.client_token,
              timestamp: Time.current.iso8601
            }
          )

          # Enqueue background job for provider matching
          Booking::MatchProviderJob.perform_async(result.booking.id)

          # Return HTTP 202 with booking details
          render json: {
            booking_id: result.booking.id,
            status: result.booking.status,
            message: "Booking created successfully. Provider matching in progress.",
            client_token: result.booking.client_token,
            created_at: result.booking.created_at
          }, status: :accepted
        else
          # Log booking creation failure
          Rails.logger.error(
            "Booking creation failed",
            {
              event: "booking_creation_failed",
              errors: result.errors,
              customer_id: booking_params[:customer_id],
              service_id: booking_params[:service_id],
              client_token: booking_params[:client_token],
              timestamp: Time.current.iso8601
            }
          )

          # Return validation errors
          render json: {
            error: "Booking creation failed",
            errors: result.errors,
            client_token: booking_params[:client_token]
          }, status: :unprocessable_entity
        end
      end

      private

      def booking_params
        params.require(:booking).permit(:customer_id, :service_id, :client_token)
      end
    end
  end
end