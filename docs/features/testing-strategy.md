Testing strategy

## Layers
1. Unit tests for pure accounting, parsing, and validation functions.
2. Integration tests for API and persistence boundaries.
3. UI tests for critical user workflows.

## Priority workflows
Invoice ingestion, journal validation, reminder scheduling, report generation, authentication, and destructive-action confirmation.

Tests should assert observable behavior and failure handling rather than implementation details.