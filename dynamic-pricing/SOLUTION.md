# Analysis and Design
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
- Validation failures return 400 Bad Request: the client sent an invalid request
- Upstream failures return 502 Bad Gateway: the client's request was valid, the pricing API failed
- Errors are never cached: the next request will retry the API immediately
- Timeouts and connection errors (`Net::OpenTimeout`, `Net::ReadTimeout`, `SocketError`, `Errno::`ECONNREFUSED) are all caught and surfaced as 502 with a human-readable message
- If Redis is unavailable, the cache layer logs event=cache_error and falls through to call the API directly. The service degrades gracefully without returning an error

### Rate completeness assumption
The controller validates all three parameters against the known set of valid combinations before the service runs. Since the API fetches all 36 combinations at once, every valid request is guaranteed to have a matching entry in the response.

If a matched entry is missing the rate attribute (malformed API response), the service treats it as a 502, immediately invalidates the cache, and lets the next request retry. This prevents corrupted data from being served for up to 5 minutes.

### Concurrency
`race_condition_ttl: 10.seconds` is set on the cache fetch. When the cache expires, the first requester triggers a refresh while concurrent requesters continue receiving the previous value for up to 10 additional seconds rather than all calling the API simultaneously. This is a built-in Rails mechanism with no additional infrastructure.

A distributed lock (e.g. Redis SETNX) would eliminate duplicate API calls entirely but adds complexity (lock expiry, retry logic, blocking request threads) that is not justified at the current traffic level.

## Implementation Notes

**RateApiClient** HTTParty client. Timeout is configurable via `RATE_API_TIMEOUT` (default 5 seconds). Defines `ALL_COMBINATIONS` and fetches all rates in one POST.

**PricingCache** thin wrapper around `Rails.cache` with a 5-minute TTL. Uses `skip_nil: true` so API errors are never cached. `race_condition_ttl: 10.seconds` mitigates thundering herd at cache expiry. Exposes invalidate for cases where cached data is detected as malformed.

**PricingService** orchestrates the cache lookup and API call. Distinguishes upstream errors from validation errors via `upstream_error?` on `BaseService`, allowing the controller to respond with the correct HTTP status without inspecting error messages.

**Instrumentation** all observability events flow through `ActiveSupport::Notifications` subscribers in `config/initializers/instrumentation.rb`. Currently each event has a single subscriber that logs in logfmt format. The indirection is intentional: if a second consumer is needed (e.g. StatsD metrics, Sentry alerts, OpenTelemetry spans), it can be added as a new subscriber with no changes to the service code. 
  
**Cache store** `memory_store` in test, Redis in development and production. The Redis `error_handler` is configured to raise on connection errors so `PricingCache` can detect and log them explicitly rather than silently treating them as cache misses.

**Tracing** the current setup provides per-request correlation via `request_id`. For full distributed tracing, we could use OpenTelemetry instrumentation to produce spans with parent-child relationships. This was not implemented as it requires an external collector (Jaeger, Honeycomb, Datadog) to be useful, which is out of scope for this environment.

## Strengths and Weaknesses

### Strengths

**Token-efficient caching** fetching all 36 rate combinations in a single API call and caching them together ensures at most one upstream call per 5-minute window, regardless of traffic volume. This is the most important property for meeting the token constraint.

**Errors are never cached** `skip_nil: true` ensures a failed or timed-out request never poisons the cache. The next request retries the API immediately.

**Graceful Redis degradation** if Redis goes down, the service continues to function by calling the API directly on every request. Throughput suffers but correctness is maintained.

**Observable** every API call emits a structured `rate_api.pricing` notification with duration, HTTP status, and request context. Cache hits, misses, and errors are also instrumented. All log lines are in logfmt format and include `request_id` for per-request correlation.

**Resilient against transient failures** `retriable` retries once on network-level exceptions (`Net::OpenTimeout`, `Net::ReadTimeout`, `SocketError`, `Errno::ECONNREFUSED`) before giving up. A single blip in connectivity does not immediately surface as an error to the client.

**Circuit breaker prevents cascade failures** `stoplight` tracks failures across requests using Redis as a shared data store. After 3 consecutive failures, the circuit opens and subsequent requests fail immediately without calling the API, reducing load on a struggling upstream and improving response time during an outage. The circuit resets automatically after a 60-second cool-off period.

### Weaknesses

**Thundering herd is mitigated but not eliminated** `race_condition_ttl` prevents most concurrent duplicate API calls but does not guarantee exactly one call per expiry cycle. Under extreme concurrency, a small number of duplicate calls may still occur. A distributed lock would eliminate this entirely but adds complexity not justified at this traffic level.

**Cache is global, not per-caller** if the pricing model ever returns different rates based on caller identity or region, the single-key design would serve incorrect rates. The current design assumes rates are uniform across all callers.

**Retry adds latency on failure** with `base_interval: 0.25s` and `tries: 2`, a failing request waits at least 250ms before the retry. Combined with a 5-second timeout per attempt, the worst-case response time for a failing request is ~10.25 seconds. Tuning `RATE_API_TIMEOUT` and retry intervals together is important if tighter SLAs are required.

**Circuit breaker depends on Redis availability** Stoplight uses Redis to share failure counts across processes. If Redis is down, Stoplight fails open and the circuit never trips. In practice, both Redis and the pricing API going down simultaneously is unlikely, and per-request retry logic still provides protection regardless.
