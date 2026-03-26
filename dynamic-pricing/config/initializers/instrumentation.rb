# Structured logging for rate API calls and cache events.
# Log format: logfmt (key=value pairs) — parseable by Datadog, Loki, etc.

ActiveSupport::Notifications.subscribe("rate_api.pricing") do |_name, start, finish, _id, payload|
  duration_ms = ((finish - start) * 1000).round(2)
  level = payload[:success] ? :info : :error
  Rails.logger.public_send(
    level,
    "event=rate_api_call request_id=#{Current.request_id} success=#{payload[:success]} " \
    "http_status=#{payload[:http_status]} duration_ms=#{duration_ms} " \
    "period=#{payload[:period]} hotel=#{payload[:hotel]} room=#{payload[:room]}"
  )
end

ActiveSupport::Notifications.subscribe("cache_generate.active_support") do |*, payload|
  next unless payload[:key] == Api::V1::PricingCache::KEY
  Rails.logger.info("event=pricing_cache_miss request_id=#{Current.request_id} key=#{payload[:key]}")
end

ActiveSupport::Notifications.subscribe("cache_fetch_hit.active_support") do |*, payload|
  next unless payload[:key] == Api::V1::PricingCache::KEY
  Rails.logger.info("event=pricing_cache_hit request_id=#{Current.request_id} key=#{payload[:key]}")
end
