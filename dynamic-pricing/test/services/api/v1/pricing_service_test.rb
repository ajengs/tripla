require "test_helper"

class Api::V1::PricingServiceTest < ActiveSupport::TestCase
  def setup
    @period = "Summer"
    @hotel = "FloatingPointResort"
    @room = "SingletonRoom"
  end

  def service
    Api::V1::PricingService.new(period: @period, hotel: @hotel, room: @room)
  end

  def stub_response(success:, body:)
    resp = Object.new
    resp.define_singleton_method(:success?) { success }
    resp.define_singleton_method(:body) { body.is_a?(String) ? body : body.to_json }
    resp
  end

  def rates_response(rate: "15000")
    stub_response(
      success: true,
      body: {
        "rates" => [
          { "period" => @period, "hotel" => @hotel, "room" => @room, "rate" => rate }
        ]
      }
    )
  end

  test "should return rate from API on success" do
    RateApiClient.stub(:get_rate, rates_response) do
      sut = service
      sut.run
      assert sut.valid?
      assert_equal "15000", sut.result
    end
  end

  test "should return nil result when rate is absent from response" do
    response = stub_response(success: true, body: { "rates" => [] })
    RateApiClient.stub(:get_rate, response) do
      sut = service
      sut.run
      assert sut.valid?
      assert_nil sut.result
    end
  end

  test "should be invalid on API failure" do
    response = stub_response(success: false, body: { "error" => "rate limit exceeded" })
    RateApiClient.stub(:get_rate, response) do
      sut = service
      sut.run
      refute sut.valid?
      assert_not_nil sut.errors
      assert_equal "rate limit exceeded", sut.errors[0]
    end
  end

  test "should be invalid when API times out" do
    RateApiClient.stub(:get_rate, ->(*) { raise Net::OpenTimeout }) do
      sut = service
      assert_raises(Net::OpenTimeout) { sut.run }
    end
  end
end
