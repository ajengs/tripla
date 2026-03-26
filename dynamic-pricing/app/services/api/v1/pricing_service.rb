module Api::V1
  class PricingService < BaseService
    RETRY_EXCEPTIONS = [Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED].freeze

    def initialize(period:, hotel:, room:)
      @period = period
      @hotel = hotel
      @room = room
    end

    def run
      data = PricingCache.find(period: @period, hotel: @hotel, room: @room) do
        fetch_rates
      end

      return unless valid?

      assign_result(data)
    end

    private
    
    def assign_result(data)
      @result = data&.dig('rate')

      return if data.blank? || @result.present?

      handle_missing_rate
    end

    # --- API ---
    def fetch_rates
      instrument_api_call do |payload|
        response = safe_api_call

        payload[:http_status] = response&.code
        payload[:success] = response&.success?

        if response.success?
          extract_rates(response)
        else
          message = response.parsed_response&.dig('error').presence || "Unexpected error from Pricing API"
          handle_failure(message)
        end
      end
    rescue Stoplight::Error::RedLight => e
      handle_unavailable(e)
    rescue *RETRY_EXCEPTIONS => e
      handle_unavailable(e)
    end

    def safe_api_call
      with_circuit_breaker do
        with_retry { RateApiClient.get_all_rates }
      end
    end

    def extract_rates(response)
      rates = response.parsed_response&.dig('rates')

      return handle_failure("Empty response from pricing API") if rates.blank?

      rates
    end

    # --- Error handling ---
    def handle_missing_rate
      PricingCache.invalidate
      fail_upstream!("Rate value missing from pricing API response")

      ActiveSupport::Notifications.instrument(
        "rate_missing.pricing",
        period: @period, hotel: @hotel, room: @room
      )
    end

    def handle_failure(message)
      fail_upstream!(message)
      nil
    end

    def handle_unavailable(exception)
      ActiveSupport::Notifications.instrument(
        "rate_api_unavailable.pricing",
        exception: exception.class,
        period: @period, hotel: @hotel, room: @room
      )

      fail_upstream!("Pricing API is unavailable")
      nil
    end

    def fail_upstream!(message)
      upstream_error!
      errors << message
    end

    # --- Infra ---
    def instrument_api_call(&block)
      ActiveSupport::Notifications.instrument(
        "rate_api.pricing",
        period: @period, hotel: @hotel, room: @room,
        &block
      )
    end

    def with_retry(&block)
      Retriable.retriable(
        on: RETRY_EXCEPTIONS,
        tries: 2,
        base_interval: 0.25,
        multiplier: 2,
        on_retry: lambda { |exception, try, _elapsed, next_interval|
          ActiveSupport::Notifications.instrument("rate_api_retry.pricing",
            exception: exception.class, try: try, next_interval: next_interval,
            period: @period, hotel: @hotel, room: @room)
        }
      ) do
        block.call
      end
    end

    def with_circuit_breaker(&block)
      Stoplight("rate_api", threshold: 3, cool_off_time: 60).run(&block)
    end
  end
end
