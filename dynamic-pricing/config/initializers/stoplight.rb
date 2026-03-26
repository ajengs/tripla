require "stoplight"

Stoplight.configure do |config|
  config.data_store = Stoplight::DataStore::Redis.new(
    Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
  )
end
