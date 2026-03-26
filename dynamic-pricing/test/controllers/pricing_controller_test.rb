require "test_helper"

class Api::V1::PricingControllerTest < ActionDispatch::IntegrationTest
  def setup
    Rails.cache.clear
  end

  test "should get pricing with all parameters" do
    mock_body = {
      'rates' => [
        { 'period' => 'Summer', 'hotel' => 'FloatingPointResort', 'room' => 'SingletonRoom', 'rate' => '15000' }
      ]
    }

    mock_response = OpenStruct.new(success?: true, parsed_response: mock_body)

    RateApiClient.stub(:get_all_rates, mock_response) do
      get api_v1_pricing_url, params: {
        period: "Summer",
        hotel: "FloatingPointResort",
        room: "SingletonRoom"
      }

      assert_response :success
      assert_equal "application/json", @response.media_type

      json_response = JSON.parse(@response.body)
      assert_equal "15000", json_response["rate"]
    end
  end

  test "should return error when rate API fails" do
    mock_response = OpenStruct.new(success?: false, parsed_response: { 'error' => 'Rate not found' })

    RateApiClient.stub(:get_all_rates, mock_response) do
      get api_v1_pricing_url, params: {
        period: "Summer",
        hotel: "FloatingPointResort",
        room: "SingletonRoom"
      }

      assert_response :bad_gateway
      assert_equal "application/json", @response.media_type

      json_response = JSON.parse(@response.body)
      assert_includes json_response["error"], "Rate not found"
      assert_equal "upstream_error", json_response['code']
      assert_equal 502, response.status
    end
  end

  test "should return error without any parameters" do
    get api_v1_pricing_url

    assert_response :bad_request
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Missing required parameters"
    assert_equal "invalid_params", json_response['code']
    assert_equal 400, response.status
  end

  test "should handle empty parameters" do
    get api_v1_pricing_url, params: {
      period: "",
      hotel: "",
      room: ""
    }

    assert_response :bad_request
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Missing required parameters"
    assert_equal "invalid_params", json_response['code']
    assert_equal 400, response.status
  end

  test "should reject invalid period" do
    get api_v1_pricing_url, params: {
      period: "summer-2024",
      hotel: "FloatingPointResort",
      room: "SingletonRoom"
    }

    assert_response :bad_request
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Invalid period"
    assert_equal "invalid_params", json_response['code']
    assert_equal 400, response.status
  end

  test "should reject invalid hotel" do
    get api_v1_pricing_url, params: {
      period: "Summer",
      hotel: "InvalidHotel",
      room: "SingletonRoom"
    }

    assert_response :bad_request
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Invalid hotel"
    assert_equal "invalid_params", json_response['code']
    assert_equal 400, response.status
  end

  test "should reject invalid room" do
    get api_v1_pricing_url, params: {
      period: "Summer",
      hotel: "FloatingPointResort",
      room: "InvalidRoom"
    }

    assert_response :bad_request
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Invalid room"
    assert_equal "invalid_params", json_response['code']
    assert_equal 400, response.status
  end

  test "should return 502 when API times out" do
    RateApiClient.stub(:get_all_rates, ->(*) { raise Net::OpenTimeout }) do
      get api_v1_pricing_url, params: {
        period: "Summer",
        hotel: "FloatingPointResort",
        room: "SingletonRoom"
      }

      assert_response :bad_gateway
      json_response = JSON.parse(@response.body)
      assert_includes json_response['error'], "unavailable"
      assert_equal "upstream_error", json_response['code']
      assert_equal 502, response.status
    end
  end

  test "should return 502 when API returns empty response" do
    mock_response = OpenStruct.new(success?: false, parsed_response: nil, code: 500)
    RateApiClient.stub(:get_all_rates, mock_response) do
      get api_v1_pricing_url, params: {
        period: "Summer",
        hotel: "FloatingPointResort",
        room: "SingletonRoom"
      }

      assert_response :bad_gateway
      json_response = JSON.parse(@response.body)
      assert_includes json_response['error'], "Unexpected error"
      assert_equal "upstream_error", json_response['code']
      assert_equal 502, response.status
    end
  end


  test "should not call API on cache hit" do
    mock_response = OpenStruct.new(
      success?: true,
      parsed_response: {
        'rates' => [
          { 'period' => 'Summer', 'hotel' => 'FloatingPointResort', 'room' => 'SingletonRoom', 'rate' => '15000' }
        ]
      }
    )

    RateApiClient.stub(:get_all_rates, mock_response) do
      get api_v1_pricing_url, params: { period: "Summer", hotel: "FloatingPointResort", room: "SingletonRoom" }
    end

    RateApiClient.stub(:get_all_rates, ->(*) { raise "API should not be called on cache hit" }) do
      get api_v1_pricing_url, params: { period: "Summer", hotel: "FloatingPointResort", room: "SingletonRoom" }

      assert_response :success
      json_response = JSON.parse(@response.body)
      assert_equal "15000", json_response["rate"]
    end
  end
end
