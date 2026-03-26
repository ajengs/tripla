Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::KeyValue.new
  config.lograge.custom_options = lambda do |event|
    {
      request_id: Current.request_id,
      params: event.payload[:params].except("controller", "action").to_s
    }
  end
end
