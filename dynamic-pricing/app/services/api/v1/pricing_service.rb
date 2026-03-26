module Api::V1
  class PricingService < BaseService
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
        response = RateApiClient.get_all_rates
        payload[:http_status] = response.code

        if response.success?
          payload[:success] = true
          response.parsed_response&.dig('rates').tap do |rates|
            errors << "Empty response from pricing API" if rates.nil?
          end
        else
          payload[:success] = true
          upstream_error!
          message = response.parsed_response&.dig('error').presence || "Unexpected error from Pricing API"
          errors << message
          nil
        end
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
      upstream_error!
      Rails.logger.error("event=rate_api_unavailable exception=#{e.class} period=#{@period} hotel=#{@hotel} room=#{@room}")
      errors << "Pricing API is unavailable"
      nil
    end
  end
end
