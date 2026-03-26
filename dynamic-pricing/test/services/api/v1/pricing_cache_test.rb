require "test_helper"

class Api::V1::PricingCacheTest < ActiveSupport::TestCase
  def cache
    Api::V1::PricingCache
  end

  def setup
    Rails.cache.clear
  
    @data = [
      { "period" => "Summer", "hotel" => "A", "room" => "X", "rate" => "10000" },
      { "period" => "Winter", "hotel" => "B", "room" => "Y", "rate" => "20000" }
    ]
  end

  test "fetch_all should store data on cache miss" do
    result = cache.fetch_all { @data }

    assert_equal @data, result
    assert_equal @data, Rails.cache.read(cache::KEY)
  end

  test "fetch_all should return cached data without calling block" do
    Rails.cache.write(cache::KEY, @data)

    result = cache.fetch_all do
      raise "should not be called"
    end

    assert_equal @data, result
  end

  test "fetch_all should treat empty array as valid cached value" do
    Rails.cache.write(Api::V1::PricingCache::KEY, [])

    result = Api::V1::PricingCache.fetch_all do
      raise "should not be called"
    end

    assert_equal [], result
  end

  test "cached entry should expire after TTL" do
    cache.fetch_all { @data }

    travel Api::V1::PricingCache::TTL + 1.second do
      call_count = 0
      result = cache.fetch_all do
        call_count += 1
        @data
      end

      assert_equal 1, call_count, "block should be called after TTL expires"
      assert_equal @data, result
    end
  end

  test "find should return correct entry" do
    result = cache.find(
      period: "Summer",
      hotel: "A",
      room: "X"
    ) { @data }

    assert_equal "10000", result["rate"]
  end

  test "find should return nil when no match" do
    result = cache.find(
      period: "Spring",
      hotel: "Z",
      room: "Q"
    ) { @data }

    assert_nil result
  end

  test "find should return nil when fetch_all returns nil" do
    result = Api::V1::PricingCache.find(
      period: "Summer",
      hotel: "A",
      room: "X"
    ) { nil }

    assert_nil result
  end

  test "find should not re-invoke block on second call when data is cached" do
    cache.find(period: "Summer", hotel: "A", room: "X") { @data }

    call_count = 0
    result = cache.find(period: "Winter", hotel: "B", room: "Y") do
      call_count += 1
      @data
    end

    assert_equal 0, call_count
    assert_equal "20000", result["rate"]
  end

  test "invalidate should remove cached data" do
    Rails.cache.write(cache::KEY, @data)

    cache.invalidate

    assert_nil Rails.cache.read(cache::KEY)
  end

  test "fetch_all falls through to block when cache raises" do
    Rails.cache.stub(:fetch, ->(*) { raise RuntimeError, "cache unavailable" }) do
      call_count = 0
      result = cache.fetch_all do
        call_count += 1
        @data
      end
      assert_equal 1, call_count
      assert_equal @data, result
    end
  end

  test "invalidate does not raise when cache raises" do
    Rails.cache.stub(:delete, ->(*) { raise RuntimeError, "cache unavailable" }) do
      assert_nothing_raised { cache.invalidate }
    end
  end
end
