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
        errors << rate.parsed_response['error']
        nil
      end
    rescue Net::OpenTimeout, Net::ReadTimeout
      errors << "Request timed out"
      nil
    end
  end
end
