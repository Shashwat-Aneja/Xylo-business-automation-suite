Observability requirements

## Minimum signals
Track request errors, latency, job execution failures, reminder delivery failures, and invoice-processing failures.

## Logging rules
Logs should contain correlation identifiers and actionable context without credentials or sensitive user data.

## Operational goal
A failed background job should be diagnosable from its recorded status and error metadata without reproducing the failure locally.