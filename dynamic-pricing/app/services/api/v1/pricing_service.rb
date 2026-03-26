module Api::V1
  class PricingService < BaseService
    RETRY_EXCEPTIONS = [Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED].freeze

    def initialize(period:, hotel:, room:)
      @period = period
      @hotel = hotel
      @room = room
    end

    def run
      cached = PricingCache.find(period: @period, hotel: @hotel, room: @room) do
        fetch_from_api
      end

      return unless valid?

      @result = cached&.dig('rate')
      if cached && @result.nil?
        PricingCache.invalidate
        upstream_error!
        errors << "Rate value missing from pricing API response"
      end
    end

    private
    
    def fetch_from_api
      ActiveSupport::Notifications.instrument("rate_api.pricing", period: @period, hotel: @hotel, room: @room) do |payload|
        response = with_circuit_breaker { with_retry { RateApiClient.get_all_rates } }
        payload[:http_status] = response.code

        if response.success?
          payload[:success] = true
          response.parsed_response&.dig('rates').tap do |rates|
            errors << "Empty response from pricing API" if rates.nil?
          end
        else
          payload[:success] = false
          upstream_error!
          message = response.parsed_response&.dig('error').presence || "Unexpected error from Pricing API"
          errors << message
          nil
        end
      end
    rescue Stoplight::Error::RedLight
      upstream_error!
      ActiveSupport::Notifications.instrument("rate_api_unavailable.pricing",
        exception: Stoplight::Error::RedLight, period: @period, hotel: @hotel, room: @room)
      errors << "Pricing API is temporarily unavailable"
      nil
    rescue *RETRY_EXCEPTIONS => e
      upstream_error!
      ActiveSupport::Notifications.instrument("rate_api_unavailable.pricing", exception: e, period: @period, hotel: @hotel, room: @room)
      errors << "Pricing API is unavailable"
      nil
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
