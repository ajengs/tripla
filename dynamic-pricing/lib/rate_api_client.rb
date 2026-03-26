class RateApiClient
  include HTTParty
  base_uri ENV.fetch('RATE_API_URL', 'http://localhost:8080')
  headers "Content-Type" => "application/json"
  headers 'token' => ENV.fetch('RATE_API_TOKEN', '04aa6f42aa03f220c2ae9a276cd68c62')
  default_timeout 5

  VALID_PERIODS = %w[Summer Autumn Winter Spring].freeze
  VALID_HOTELS = %w[FloatingPointResort GitawayHotel RecursionRetreat].freeze
  VALID_ROOMS = %w[SingletonRoom BooleanTwin RestfulKing].freeze
  ALL_COMBINATIONS = VALID_PERIODS.product(VALID_HOTELS, VALID_ROOMS).map do |p, h, r|
    { period: p, hotel: h, room: r }
  end

  def self.get_all_rates
    self.post("/pricing", body: { attributes: ALL_COMBINATIONS }.to_json)
  end
end
