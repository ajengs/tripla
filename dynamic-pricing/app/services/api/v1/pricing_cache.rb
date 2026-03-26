class Api::V1::PricingCache
  KEY = "pricing:all"
  TTL = 5.minutes

  def self.fetch_all
    Rails.cache.fetch(KEY, expires_in: TTL, skip_nil: true, race_condition_ttl: 10.seconds) { yield }
  rescue => e
    ActiveSupport::Notifications.instrument("cache_error.pricing", error: e, operation: :fetch)
    yield
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

  def self.invalidate
    Rails.cache.delete(KEY)
  rescue => e
    ActiveSupport::Notifications.instrument("cache_error.pricing", error: e, operation: :invalidate)
  end
end
