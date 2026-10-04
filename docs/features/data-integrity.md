Data integrity rules

## Principles
Business records should have stable identifiers, explicit ownership, and predictable lifecycle states.

## Write safety
Validate input before persistence, use transactions for multi-record accounting operations, and reject invalid state transitions.

## Auditability
Important state changes should retain timestamps and enough metadata to determine what operation occurred and which workflow initiated it.