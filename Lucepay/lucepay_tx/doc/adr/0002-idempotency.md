# 0002: Client Token-Based Idempotency for Financial Transactions

## Status

Accepted

## Context

Financial transaction systems must handle duplicate requests gracefully to prevent accidental double-charging, ensure data consistency, and provide a reliable API for clients. The lucepay_tx system processes wallet transfers that involve:

- **Financial Integrity**: Money transfers must not be duplicated
- **API Reliability**: Clients need safe retry mechanisms
- **Audit Compliance**: Each logical operation should have exactly one audit trail
- **Race Conditions**: Concurrent identical requests must be handled safely
- **Performance**: Idempotency checks should not significantly impact response times

Key requirements include:
- Safe retry of failed requests
- Prevention of duplicate financial operations
- Clear error handling for invalid duplicate attempts
- Minimal performance overhead
- Comprehensive audit logging

## Decision

We have implemented **client token-based idempotency** using a unique database index combined with application-level checks within database transactions.

### Implementation Strategy

```ruby
# In TransferService#call
def call(from_wallet_id:, to_wallet_id:, amount_cents:, client_token:)
  # 1. Pre-flight idempotency check
  existing_transaction = find_existing_transaction(client_token)
  return Result.success(transaction_id: existing_transaction.id) if existing_transaction

  # 2. Load wallets and perform transfer within transaction
  ApplicationRecord.transaction do
    # Double-check for race conditions
    existing = find_existing_transaction(client_token)
    return Result.success(transaction_id: existing.id) if existing

    # Perform transfer
    transaction = from_wallet.transfer_to!(to_wallet, amount_cents, client_token)
    Result.success(transaction_id: transaction.id)
  end
end
```

## Consequences

### Positive Consequences

- **API Safety**: Clients can safely retry requests without side effects
- **Financial Integrity**: Prevents accidental duplicate transfers
- **Audit Clarity**: Single audit trail per logical operation
- **Race Condition Safety**: Handles concurrent identical requests correctly
- **Performance**: Minimal overhead for idempotency checks
- **Debugging**: Clear tracing of duplicate request handling

### Negative Consequences

- **Database Overhead**: Unique index adds slight write performance cost
- **Token Management**: Clients must generate unique tokens for each logical operation
- **Storage Growth**: Client tokens accumulate in database over time
- **Error Handling**: Complex error scenarios when tokens conflict
- **Testing Complexity**: Requires testing of concurrent duplicate scenarios

## Technical Implementation

### Database-Level Idempotency

**Unique Index on client_token:**
```sql
-- Implemented in migration 20240101000003_create_transactions.rb
add_index :transactions, :client_token, unique: true
```

**Benefits:**
- Database-enforced uniqueness prevents race conditions
- Automatic rollback of duplicate attempts
- No application-level token collision detection needed

### Application-Level Handling

**Pre-flight Check:**
```ruby
def find_existing_transaction(client_token)
  Transaction.find_by(client_token: client_token)
end
```

**Race Condition Recovery:**
```ruby
rescue ActiveRecord::RecordInvalid => e
  if e.message.include?('client_token')
    # Race condition: another process created the transaction first
    existing_transaction = find_existing_transaction(client_token)
    if existing_transaction
      return Result.success(transaction_id: existing_transaction.id)
    end
  end
  Result.failure(error: "Transfer failed: #{e.message}")
```

## Trade-offs Analysis

### Performance vs. Reliability

**Chosen Approach (Database + Application):**
- ✅ **High Reliability**: Guaranteed uniqueness with database constraints
- ✅ **Race Condition Safety**: Handles concurrent requests correctly
- ✅ **Audit Compliance**: Complete audit trail for all operations
- ⚠️ **Performance Cost**: Unique index adds write overhead (~5-10%)

**Trade-off Rationale:**
- Financial systems prioritize correctness over raw performance
- The performance cost is acceptable for the reliability gained
- Database-level constraints provide stronger guarantees than application-level checks

### Token-Based vs. Hash-Based Idempotency

**Token-Based (Chosen):**
- ✅ **Human Readable**: Tokens can be meaningful (e.g., "payment-order-123")
- ✅ **Debugging**: Easy to trace and identify specific operations
- ✅ **Client Control**: Clients generate tokens based on business logic
- ⚠️ **Collision Risk**: Requires client-side uniqueness management

**Hash-Based (Not Chosen):**
- ✅ **Automatic Uniqueness**: Hash of request parameters prevents collisions
- ✅ **No Client Management**: System generates idempotency automatically
- ⚠️ **Debugging Difficulty**: Hash values are not human-readable
- ⚠️ **Flexibility Loss**: Cannot handle intentional duplicate requests

## Alternatives Considered

### Redis-Based Idempotency Keys

**Description**: Store idempotency keys in Redis with TTL

**Pros:**
- Better performance for high-frequency operations
- Configurable TTL for automatic cleanup
- Distributed system compatibility

**Cons:**
- Additional infrastructure dependency
- Consistency risks if Redis fails
- Complex failure scenarios
- Higher operational complexity

**Why Not Chosen:**
- Adds unnecessary complexity for MVP
- Database-level solution is sufficient and simpler
- Redis failure could cause inconsistent state

### Application-Level Caching

**Description**: Cache transaction results in memory/application cache

**Pros:**
- Fastest response times for cache hits
- No database overhead for cached operations

**Cons:**
- Cache invalidation complexity
- Memory usage grows with operation volume
- Inconsistent state during application restarts
- Race conditions in cache updates

**Why Not Chosen:**
- Financial data requires database durability
- Cache failures could cause financial inconsistencies
- More complex to implement correctly

### HTTP ETag/If-Match Headers

**Description**: Use HTTP headers for resource-based idempotency

**Pros:**
- Standard HTTP patterns
- Good for RESTful resource updates
- Client-driven approach

**Cons:**
- Not suitable for financial transactions
- Complex for non-resource operations
- Limited to HTTP-based APIs

**Why Not Chosen:**
- Financial transfers are not resource updates
- Overly complex for the use case
- Not a natural fit for transaction processing

## Migration and Evolution

### Current State (MVP)
- Database unique index on `client_token`
- Application-level pre-flight checks
- Transaction-based race condition handling

### Future Enhancements

**Phase 1: Token Cleanup**
- Implement background job to clean old client tokens
- Add retention policies based on transaction age
- Monitor token table growth

**Phase 2: Performance Optimization**
- Consider Redis caching for high-frequency tokens
- Implement token hashing for very long tokens
- Add database query optimization

**Phase 3: Advanced Features**
- Token expiration and renewal mechanisms
- Client token validation and formatting
- Integration with external idempotency services

## Compliance and Security

### Financial Compliance
- **Double-Entry Bookkeeping**: Each transfer creates exactly two ledger entries
- **Audit Trail**: Complete audit log for every operation (including duplicates)
- **Non-Repudiation**: Client tokens provide verifiable operation identity
- **Regulatory Reporting**: Clear transaction history for compliance audits

### Security Considerations
- **Token Predictability**: Clients should generate cryptographically secure tokens
- **Information Disclosure**: Token format should not reveal sensitive information
- **Brute Force Protection**: Consider rate limiting for token-based operations
- **Logging Security**: Ensure tokens are logged safely for debugging

## Testing Strategy

### Idempotency Testing
- **Duplicate Requests**: Verify same token returns same result
- **Concurrent Requests**: Test simultaneous identical requests
- **Race Conditions**: Simulate timing-based conflicts
- **Error Recovery**: Test behavior when uniqueness constraints fail

### Performance Testing
- **Overhead Measurement**: Compare performance with/without idempotency
- **Concurrent Load**: Test under high concurrency scenarios
- **Memory Usage**: Monitor token storage growth
- **Response Times**: Ensure idempotency doesn't significantly impact latency

## Related Decisions

- **ADR-0001**: Pessimistic Locking Strategy (provides concurrency safety foundation)
- **ADR-0003**: Audit Logging Strategy (pending)
- **ADR-0004**: API Design Patterns (pending)

## References

- [Idempotency Patterns in Distributed Systems](https://microservices.io/patterns/communication-style/idempotent-consumer.html)
- [PostgreSQL Unique Constraints](https://www.postgresql.org/docs/current/indexes-unique.html)
- [Financial Transaction Idempotency](https://stripe.com/docs/idempotency)
- [RESTful API Idempotency](https://tools.ietf.org/html/rfc7231#section-4.3.5)