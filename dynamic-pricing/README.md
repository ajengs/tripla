# Dynamic Pricing Proxy

A Ruby on Rails service that acts as a caching proxy for an expensive dynamic pricing model. Rates are cached for 5 minutes and fetched in a single batch call to stay within API token limits.

## Design

### The problem
The pricing model API is computationally expensive and rate-limited to a single token. The naive implementation calls it on every request, which exhausts the token budget and adds latency.

### Caching strategy
Rather than caching per `(period, hotel, room)` combination, the service fetches **all 36 combinations** (4 periods × 3 hotels × 3 rooms) in a single API call and caches the full result under one key for 5 minutes.

**Why batch over per-key?**
- Per-key caching could require up to 36 API calls per cache refresh cycle
- At 10,000 req/day with 5-min TTL: worst case 36 × 288 = ~10,368 API calls/day
- Batch approach: maximum 1 call per 5 minutes = 288 calls/day regardless of traffic

The rate API's `attributes` array accepts multiple combinations in one request, making this approach possible without any API changes.

### Error handling
- API failures return `502 Bad Gateway` — the client's request was valid, the upstream failed
- Validation failures return `400 Bad Request`
- Errors are not cached — the next request will retry the API
- Timeouts and connection errors are caught and surfaced with a human-readable message

## Quick Start

```bash
docker compose up -d --build
```

The app will be available at `http://localhost:3000`.

## API

### `GET /api/v1/pricing`

Returns the dynamic rate for a given room configuration.

**Parameters**

| Name     | Required | Values |
|----------|----------|--------|
| `period` | yes      | `Summer`, `Autumn`, `Winter`, `Spring` |
| `hotel`  | yes      | `FloatingPointResort`, `GitawayHotel`, `RecursionRetreat` |
| `room`   | yes      | `SingletonRoom`, `BooleanTwin`, `RestfulKing` |

**Success (200)**
```json
{ "rate": "15000" }
```

**Validation error (400)**
```json
{ "error": "Invalid period. Must be one of: Summer, Autumn, Winter, Spring" }
```

**Upstream error (502)**
```json
{ "error": "Pricing API is unavailable" }
```

**Example**
```bash
curl 'http://localhost:3000/api/v1/pricing?period=Summer&hotel=FloatingPointResort&room=SingletonRoom'
```

## Running Tests

```bash
# Full test suite
docker compose exec interview-dev ./bin/rails test

# Single file
docker compose exec interview-dev ./bin/rails test test/services/api/v1/pricing_service_test.rb

# Single test
docker compose exec interview-dev ./bin/rails test test/services/api/v1/pricing_service_test.rb -n test_should_return_rate_from_API_on_success
```

## Load Testing

A load test script is included to verify caching behaviour and throughput.

```bash
# Default: 10 concurrent, 200 total requests
ruby bin/load_test

# Custom: 50 concurrent, 1000 total requests
ruby bin/load_test 50 1000

# Or inside the container (removes Docker port-forwarding overhead)
docker compose exec interview-dev ruby bin/load_test
```

Run it twice back-to-back — the second run should show significantly lower latency
since the cache is already warm.

## Implementation Notes

- `RateApiClient` — HTTParty client with a 5-second timeout. Fetches all rate combinations at once.
- `PricingCache` — Thin wrapper around `Rails.cache` with a 5-minute TTL. Uses `skip_nil: true` so API errors are never cached.
- `PricingService` — Orchestrates cache lookup and API call. Distinguishes upstream errors from validation errors via `upstream_error?` flag on `BaseService`.
- Cache store defaults to `memory_store` in development/test. For production, swap to Redis via `config.cache_store = :redis_cache_store`.
