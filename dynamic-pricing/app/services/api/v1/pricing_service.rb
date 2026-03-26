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
      rate = RateApiClient.get_rate(period: @period, hotel: @hotel, room: @room)
      if rate.success?
        rate.parsed_response['rates']
      else
        upstream_error!
        message = rate.parsed_response&.dig('error').presence || "Unexpected error"
        Rails.logger.error("PricingService API error: #{message} [period=#{@period}, hotel=#{@hotel}, room=#{@room}]")
        errors << message
        nil
      end
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      upstream_error!
      Rails.logger.error("PricingService timeout: #{e.class} [period=#{@period}, hotel=#{@hotel}, room=#{@room}]")
      errors << "Request timed out"
      nil
    end
  end
end
