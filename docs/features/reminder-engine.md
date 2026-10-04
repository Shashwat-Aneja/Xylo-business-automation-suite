Reminder engine design

## Goal
Keep scheduled reminders deterministic and easy to audit.

## Rules
- Store the source task identifier with every reminder.
- Normalize all timestamps to UTC at the persistence boundary.
- Evaluate overdue reminders before future reminders.
- Make delivery idempotent so a retry cannot send the same reminder twice.
- Record the delivery result and failure reason.

## Retry policy
Transient delivery failures should be retried with bounded exponential backoff. Permanent validation failures should be recorded without retrying.