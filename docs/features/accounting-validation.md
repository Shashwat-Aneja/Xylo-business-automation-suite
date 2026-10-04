Accounting validation rules

## Core checks
- Debit and credit entries must contain valid accounts.
- Journal entries must balance before posting.
- Monetary values must use a consistent decimal representation.
- Dates must be valid before posting.
- Posted records should be immutable through normal edit flows.

## Failure handling
Validation failures should identify the field or accounting rule that failed and should not partially persist a journal entry.