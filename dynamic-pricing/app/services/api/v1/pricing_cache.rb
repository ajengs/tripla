class Api::V1::PricingCache
  KEY = "pricing:all"
  TTL = 5.minutes

  def self.fetch_all
    Rails.cache.fetch(KEY, expires_in: TTL, skip_nil: true) { yield }
  rescue => e
    Rails.logger.error("event=cache_unavailable error=#{e.class} message=\"#{e.message}\" request_id=#{Current.request_id}")
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
    Rails.logger.error("event=cache_invalidate_failed error=#{e.class} message=\"#{e.message}\" request_id=#{Current.request_id}")
  end
end
