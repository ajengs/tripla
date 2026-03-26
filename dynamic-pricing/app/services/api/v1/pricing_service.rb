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

      if valid?
        @result = cached&.dig('rate')
      end
    end

    private
    
    def fetch_from_api
      rate = RateApiClient.get_all_rates
      if rate.success?
        rate.parsed_response&.dig('rates').tap do |rates|
          errors << "Empty response from pricing API" if rates.nil?
        end
      else
        upstream_error!
        message = rate.parsed_response&.dig('error').presence || "Unexpected error from Pricing API"
        Rails.logger.error("PricingService API error: #{message} [period=#{@period}, hotel=#{@hotel}, room=#{@room}]")
        errors << message
        nil
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
      upstream_error!
      Rails.logger.error("PricingService API error: #{e.class} [period=#{@period}, hotel=#{@hotel}, room=#{@room}]")
      errors << "Pricing API is unavailable"
      nil
    end
  end
end
