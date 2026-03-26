# Dynamic Pricing Proxy

A Ruby on Rails service that acts as a caching proxy for an expensive dynamic pricing model. Rates are cached for 5 minutes and fetched in a single batch call to stay within API token limits.

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

Run it twice back-to-back, the second run should show significantly lower latency since the cache is already warm.

## Implementation Notes
[Implementation notes](./SOLUTION.md)
