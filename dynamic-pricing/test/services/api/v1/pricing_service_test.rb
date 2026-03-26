require "test_helper"

class Api::V1::PricingServiceTest < ActiveSupport::TestCase
  def setup
    Rails.cache.clear
    @period = "Summer"
    @hotel = "FloatingPointResort"
    @room = "SingletonRoom"
  end

  def service
    Api::V1::PricingService.new(period: @period, hotel: @hotel, room: @room)
  end

  def stub_response(success:, body:, code: nil)
    resp = Object.new
    resp.define_singleton_method(:success?) { success }
    resp.define_singleton_method(:parsed_response) { body }
    resp.define_singleton_method(:code) { code || (success ? 200 : 500) }
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
    RateApiClient.stub(:get_all_rates, rates_response) do
      sut = service
      sut.run
      assert sut.valid?
      assert_equal "15000", sut.result
    end
  end

  test "should return nil result when rate is absent from response" do
    response = stub_response(success: true, body: { "rates" => [] })
    RateApiClient.stub(:get_all_rates, response) do
      sut = service
      sut.run
      assert sut.valid?
      assert_nil sut.result
    end
  end

  test "should be invalid on API failure" do
    response = stub_response(success: false, body: { "error" => "rate limit exceeded" })
    RateApiClient.stub(:get_all_rates, response) do
      sut = service
      sut.run
      refute sut.valid?
      assert_equal "rate limit exceeded", sut.errors[0]
    end
  end

  test "should be invalid when API returns nil parsed_response on success" do
    response = stub_response(success: true, body: nil)
    RateApiClient.stub(:get_all_rates, response) do
      sut = service
      sut.run
      refute sut.valid?
      assert_includes sut.errors, "Empty response from pricing API"
    end
  end

  test "should not call API when data is cached" do
    RateApiClient.stub(:get_all_rates, rates_response) do
      service.run
    end

    RateApiClient.stub(:get_all_rates, ->(*) { raise "API should not be called on cache hit" }) do
      sut = service
      sut.run
      assert sut.valid?
      assert_equal "15000", sut.result
    end
  end

  test "should not cache API errors so next call retries" do
    error_response = stub_response(success: false, body: { "error" => "service unavailable" })
    RateApiClient.stub(:get_all_rates, error_response) do
      service.run
    end

    RateApiClient.stub(:get_all_rates, rates_response) do
      sut = service
      sut.run
      assert sut.valid?
      assert_equal "15000", sut.result
    end
  end

  test "should be invalid when failed API contains no error" do
    response = stub_response(success: false, body: nil)
    RateApiClient.stub(:get_all_rates, response) do
      sut = service
      sut.run
      refute sut.valid?
      assert_includes sut.errors, "Unexpected error from Pricing API"
    end
  end

  test "should be invalid and invalidate cache when matched rate entry has no rate attribute" do
    response = stub_response(
      success: true,
      body: {
        "rates" => [
          { "period" => @period, "hotel" => @hotel, "room" => @room }
        ]
      }
    )

    RateApiClient.stub(:get_all_rates, response) do
      sut = service
      sut.run
      refute sut.valid?
      assert_includes sut.errors, "Rate value missing from pricing API response"
      assert_nil Rails.cache.read(Api::V1::PricingCache::KEY), "cache should be invalidated"
    end
  end

  test "should retry API on next request after cache invalidation" do
    incomplete_response = stub_response(
      success: true,
      body: { "rates" => [{ "period" => @period, "hotel" => @hotel, "room" => @room }] }
    )
    RateApiClient.stub(:get_all_rates, incomplete_response) do
      service.run  # populates cache with incomplete data, then invalidates it
    end

    RateApiClient.stub(:get_all_rates, rates_response) do
      sut = service
      sut.run
      assert sut.valid?
      assert_equal "15000", sut.result
    end
  end

  [Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED].each do |exception_class|
    test "should be invalid when API raises #{exception_class}" do
      RateApiClient.stub(:get_all_rates, ->(*) { raise exception_class }) do
        sut = service
        sut.run
        refute sut.valid?
        assert_includes sut.errors, "Pricing API is unavailable"
      end
    end
  end
end
