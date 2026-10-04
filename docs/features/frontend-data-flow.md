Frontend data flow

## Principle
Keep server state, local UI state, and derived presentation state separate.

## Flow
API response -> query/cache layer -> feature state -> presentation components.

## Guidelines
- Avoid duplicating server records in unrelated components.
- Keep loading, empty, and error states explicit.
- Derive totals from canonical data rather than maintaining duplicate counters.
- Keep API transformation logic outside presentational components.