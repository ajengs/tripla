class Api::V1::PricingCache
  KEY = "pricing:all"
  TTL = 5.minutes

  def self.fetch_all
    Rails.cache.fetch(KEY, expires_in: TTL, skip_nil: true) { yield }
  end

  def self.find(period:, hotel:, room:)
    data = fetch_all { yield }
    return nil if data.nil?

    data.find do |r|
      r["period"] == period &&
      r["hotel"] == hotel &&
      r["room"] == room
    end
  end
end
