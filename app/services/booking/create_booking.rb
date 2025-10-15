module Booking
  class CreateBooking
    attr_reader :booking, :errors

    def self.call(customer_id:, service_id:, client_token:)
      new(customer_id: customer_id, service_id: service_id, client_token: client_token).call
    end

    def initialize(customer_id:, service_id:, client_token:)
      @customer_id = customer_id
      @service_id = service_id
      @client_token = client_token
      @errors = []
    end

    def call
      # Validate required parameters
      validate_params

      return failure_response unless @errors.empty?

      # Check for existing booking with same client_token (idempotency)
      existing_booking = find_existing_booking

      if existing_booking
        Rails.logger.info(
          "Existing booking found for client_token",
          {
            event: "existing_booking_found",
            booking_id: existing_booking.id,
            client_token: @client_token,
            status: existing_booking.status,
            timestamp: Time.current.iso8601
          }
        )

        return success_response(existing_booking)
      end

      # Create new booking
      @booking = ::Booking.new(
        customer_id: @customer_id,
        service_id: @service_id,
        client_token: @client_token,
        status: :pending
      )

      if @booking.save
        Rails.logger.info(
          "New booking created",
          {
            event: "new_booking_created",
            booking_id: @booking.id,
            customer_id: @customer_id,
            service_id: @service_id,
            client_token: @client_token,
            status: @booking.status,
            timestamp: Time.current.iso8601
          }
        )

        success_response(@booking)
      else
        Rails.logger.error(
          "Failed to save new booking",
          {
            event: "booking_save_failed",
            errors: @booking.errors.full_messages,
            customer_id: @customer_id,
            service_id: @service_id,
            client_token: @client_token,
            timestamp: Time.current.iso8601
          }
        )

        @errors = @booking.errors.full_messages
        failure_response
      end
    rescue ActiveRecord::RecordNotUnique => e
      # Handle race condition for duplicate client_token
      Rails.logger.warn(
        "Race condition detected for client_token",
        {
          event: "client_token_race_condition",
          client_token: @client_token,
          error: e.message,
          timestamp: Time.current.iso8601
        }
      )

      # Try to find the existing booking that was created by another process
      existing_booking = find_existing_booking
      if existing_booking
        return success_response(existing_booking)
      else
        @errors << "A booking with this client token already exists"
        failure_response
      end
    rescue StandardError => e
      Rails.logger.error(
        "Unexpected error in CreateBooking service",
        {
          event: "create_booking_error",
          error: e.message,
          error_class: e.class.name,
          customer_id: @customer_id,
          service_id: @service_id,
          client_token: @client_token,
          timestamp: Time.current.iso8601
        }
      )

      @errors << "An unexpected error occurred while creating the booking"
      failure_response
    end

    def success?
      @errors.empty? && @booking.present?
    end

    private

    def validate_params
      @errors << "customer_id is required" if @customer_id.blank?
      @errors << "service_id is required" if @service_id.blank?
      @errors << "client_token is required" if @client_token.blank?

      if @errors.any?
        Rails.logger.warn(
          "Validation failed for booking creation",
          {
            event: "booking_validation_failed",
            errors: @errors,
            customer_id: @customer_id,
            service_id: @service_id,
            client_token: @client_token,
            timestamp: Time.current.iso8601
          }
        )
      end
    end

    def find_existing_booking
      ::Booking.find_by(client_token: @client_token)
    end

    def success_response(booking)
      OpenStruct.new(success?: true, booking: booking, errors: [])
    end

    def failure_response
      OpenStruct.new(success?: false, booking: nil, errors: @errors)
    end
  end
end