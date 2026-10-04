API error contract

## Standard response
API failures should expose a stable machine-readable error code, a human-readable message, and optional field-level details.

Example shape:
```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Request validation failed",
    "fields": {}
  }
}
```

## Rules
Clients should branch on `code`, not on message text. Internal stack traces must remain server-side.