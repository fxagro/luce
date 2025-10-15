# 0001: Use Pessimistic Locking for Wallet Transfer Concurrency Control

## Status

Accepted

## Context

The lucepay_tx application requires robust concurrency control for financial transactions to prevent race conditions, ensure data consistency, and maintain audit integrity. Multiple transfers may occur simultaneously on the same wallets, and the system must guarantee that:

- Wallet balances never go negative due to concurrent transfers
- All transfers are atomic (all-or-nothing)
- Ledger entries and audit logs remain consistent
- No duplicate transactions are created
- Financial regulations and audit requirements are met

## Decision

We have chosen to implement **pessimistic locking** using ActiveRecord's `lock!` method (which translates to `SELECT ... FOR UPDATE` in PostgreSQL) for wallet transfers.

### Implementation Details

```ruby
# In Wallet#transfer_to!
ApplicationRecord.transaction do
  # Lock both wallets to prevent concurrent modifications
  lock!
  target_wallet.lock!

  # Re-check balance after acquiring lock
  raise ArgumentError, 'Insufficient funds' if balance_cents < amount_cents

  # Create transaction, ledger entries, and audit logs
  # Update wallet balances
end
```

## Consequences

### Positive Consequences

- **Guaranteed Consistency**: Eliminates race conditions by preventing concurrent access to locked wallets
- **Simplicity**: Straightforward implementation with clear semantics
- **Immediate Failure Detection**: Failed lock attempts are immediately apparent
- **Audit Compliance**: Meets financial industry requirements for transaction integrity
- **Debugging**: Easier to trace and debug concurrency issues
- **Rollback Safety**: Failed transactions automatically rollback due to database transactions

### Negative Consequences

- **Performance Impact**: Locking creates database contention under high concurrency
- **Deadlock Potential**: Risk of deadlocks if locking order is inconsistent
- **Scalability Limits**: May limit throughput compared to optimistic approaches
- **Resource Holding**: Locks are held for the duration of the transaction
- **Complex Testing**: Requires careful testing of concurrent scenarios

## Alternatives Considered

### Optimistic Locking

**Description**: Use version-based locking with `lock_version` column and retry logic

**Pros**:
- Better performance under low contention
- No database locks held during business logic
- More scalable for read-heavy workloads
- No deadlock concerns

**Cons**:
- Complex retry logic required
- Potential for starvation under high contention
- Business logic duplication in retry scenarios
- Harder to test and debug
- May fail user operations unnecessarily

**Why Not Chosen**:
- Financial transactions require guaranteed consistency
- Retry logic adds complexity for MVP
- Optimistic locking failures can frustrate users
- Debugging optimistic locking issues is more complex

### Application-Level Locking

**Description**: Use Redis or other distributed locks

**Pros**:
- Can work across multiple database instances
- More sophisticated retry and timeout logic
- Better observability

**Cons**:
- Additional infrastructure complexity
- Network latency and failure points
- More complex error handling
- Higher operational overhead

**Why Not Chosen**:
- Over-engineering for MVP scope
- Database-level pessimistic locking is sufficient
- Adds unnecessary complexity

## Mitigation Strategies

### Deadlock Prevention

1. **Consistent Lock Ordering**: Always lock wallets in a consistent order (e.g., by ID)
2. **Timeout Handling**: Implement appropriate lock timeouts
3. **Transaction Scoping**: Keep transactions short to minimize lock duration
4. **Error Monitoring**: Monitor for deadlock exceptions and alert operations

### Performance Optimization

1. **Lock Scope Minimization**: Only lock necessary records
2. **Read-Only Operations**: Avoid locking for read-only operations
3. **Connection Pooling**: Ensure adequate database connections
4. **Monitoring**: Track lock wait times and contention

## Future Considerations

### Migration to Optimistic Locking

If performance becomes a bottleneck, we can migrate to optimistic locking by:

1. Adding `lock_version` column to wallets table
2. Implementing retry logic in `Wallet#transfer_to!`
3. Updating tests to handle `ActiveRecord::StaleObjectError`
4. Monitoring retry rates and performance metrics

### Enhanced Monitoring

Future enhancements may include:
- Lock wait time metrics
- Deadlock detection and alerting
- Performance profiling under load
- Automatic failover strategies

## Compliance and Security

The chosen pessimistic locking approach ensures:
- **ACID Compliance**: Full transactional consistency
- **Audit Trail Integrity**: Complete and accurate financial records
- **Regulatory Compliance**: Meets financial industry standards
- **Fraud Prevention**: Eliminates race condition vulnerabilities

## Testing Strategy

Concurrency testing includes:
- **Unit Tests**: Individual transfer operations
- **Integration Tests**: Multiple concurrent transfers
- **Stress Tests**: High-volume concurrent operations
- **Race Condition Tests**: Simulated timing-based conflicts
- **Performance Tests**: Throughput and latency measurements

## Related Decisions

- **ADR-0002**: Database Transaction Management (pending)
- **ADR-0003**: Audit Logging Strategy (pending)
- **ADR-0004**: Idempotency Implementation (pending)

## References

- [ActiveRecord Pessimistic Locking](https://api.rubyonrails.org/classes/ActiveRecord/Locking/Pessimistic.html)
- [PostgreSQL SELECT FOR UPDATE](https://www.postgresql.org/docs/current/sql-select.html)
- [Financial Transaction Concurrency Patterns](https://microservices.io/patterns/data/transactional-outbox.html)