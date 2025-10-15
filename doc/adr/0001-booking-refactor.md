# 0001. Booking Subsystem Refactor

**Date:** 2025-01-15

**Status:** Accepted

## Context

The original booking system suffered from several critical performance and maintainability issues:

- **High Latency**: The booking API had 1-2 seconds response time due to synchronous external API calls for provider matching and pricing
- **Monolithic Controller**: All booking logic was contained in a single controller, making it difficult to test and maintain
- **Unstable External Dependencies**: Direct API calls to external services caused failures when those services were unavailable
- **Poor Observability**: Lack of structured logging and metrics made debugging and monitoring challenging
- **No Idempotency**: Duplicate requests could create multiple bookings for the same client request

## Decision

We decided to refactor the booking subsystem using the following architectural improvements:

### Service Object Pattern
- Extract booking creation logic into `Booking::CreateBooking` service object
- Centralize business logic and validation in a reusable, testable component
- Enable better error handling and logging at the service layer

### Asynchronous Processing
- Implement `Booking::MatchProviderJob` Sidekiq background job for provider matching
- Move external API calls to background processing to reduce response latency
- Return HTTP 202 (Accepted) immediately after booking creation

### Idempotency Implementation
- Use `client_token` field to ensure duplicate requests return the same booking
- Add unique database constraint on `client_token` to prevent race conditions
- Implement proper error handling for constraint violations

### Observability Enhancements
- Add structured JSON logging for all booking events (`booking_received`, `booking_created`, `job_started`, etc.)
- Implement Prometheus-style metrics counter (`$BOOKING_METRICS[:matching_completed]`)
- Enable comprehensive monitoring and debugging capabilities

## Alternatives Considered

### Alternative 1: Controller Optimization
Keep all logic in the controller but optimize external API calls with caching and circuit breakers.
- **Pros**: Simpler architecture, no additional infrastructure dependencies
- **Cons**: Still synchronous, limited testability, harder to maintain complex logic

### Alternative 2: Delayed Job Instead of Sidekiq
Use Rails' built-in background job system instead of Sidekiq.
- **Pros**: No Redis dependency, simpler setup
- **Cons**: Less robust for high-volume scenarios, fewer monitoring features

## Consequences

### Positive
- **Improved Performance**: API response time reduced from 1-2 seconds to milliseconds
- **Better Maintainability**: Separated concerns make code easier to test and modify
- **Enhanced Reliability**: Background job retries handle transient external API failures
- **Better Observability**: Structured logging and metrics enable proactive monitoring
- **Idempotency**: Prevents duplicate bookings and improves user experience

### Negative
- **Increased Complexity**: Additional service objects and background jobs add architectural complexity
- **Infrastructure Dependency**: Requires Redis for Sidekiq job processing
- **Operational Overhead**: Need to monitor both web application and background job performance
- **Debugging Complexity**: Asynchronous processing makes debugging more challenging

### Mitigation Strategies
- Comprehensive test coverage to ensure reliability
- Detailed logging to aid in debugging asynchronous operations
- Monitoring and alerting for background job performance
- Clear documentation for developers working with the system