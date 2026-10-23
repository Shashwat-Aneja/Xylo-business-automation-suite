# Interconnected accounting — implementation phase 1

## Status

- Branch: `feature/xylo-interconnected-accounting`
- Scope: additive PostgreSQL foundation for business applicability profiles, periods, customers and suppliers, sales invoices and supplier bills, cash receipts and invoice allocations, versioned rule registry, audit events, journal source links, journal integrity guards, controlled posting routines, and journal-derived books/report projections.
- Deployment: **not applied to any Supabase database**.
- Production: unchanged.
- Compliance: GST and invoice-posting rules default to disabled and require independently approved registry entries before invoice posting is enabled.

## Interconnection model

A sales invoice is a source document, not a separately maintained balance. Posting creates the linked journal and its lines in the same database transaction. The sales book is a view over invoice documents; the general ledger, trial balance, profit-and-loss view and balance-sheet view are derived from posted journal lines. Reports do not have a recent-record limit.

Draft deletion removes only an unposted draft and records an audit event. Database triggers reject deletion or mutation of posted invoices, supplier bills, receipts, journal entries and journal lines. A cancellation routine exists only for an unpaid, untaxed invoice and is additionally gated by an independently approved cancellation rule. Tax-bearing invoices and invoices with receipt allocations fail closed and require a separately reviewed credit-note/allocation-correction workflow. Receipt posting debits cash/bank and credits customer advances; allocating a posted receipt creates a linked journal that reclassifies the advance against receivables, and allocation constraints prevent over-allocation.

## Important boundaries in this phase

1. The migrations are source-control artifacts only; they have not been executed against a database.
2. The current HTML invoice, transaction and report pages remain prototypes with in-memory data. They are not yet connected to these tables or views.
3. Receipt posting and allocation journals are implemented as database routines, but require staging verification and frontend/API wiring.
4. Supplier bill posting and the purchase-book projection are implemented as database routines, but require staging verification and frontend/API wiring.
5. The initial report views are accrual-basis projections only and do not replace period-parameterized production report endpoints. Cash-basis reporting must be implemented as a separate reviewed transformation and must not mutate the accrual ledger.
6. The GST registry contains no pre-approved rules. No GST compliance is asserted or enabled by these migrations.
7. The migration requires a PostgreSQL/Supabase staging execution, SQL test run, RLS review, and database advisors before it can be accepted.

## Verification checklist before merge

- [ ] Apply migrations to an isolated staging database, not production.
- [ ] Verify migrations run cleanly from the repository's current foundation.
- [ ] Verify owner RLS for every new table and security-invoker reporting view.
- [ ] Create an open period, reviewed profile, customer, accounts and a draft invoice.
- [ ] Confirm draft has no journal/report impact.
- [ ] Confirm posting fails if profile/rule approval is missing.
- [ ] Enable test-only approved rules in staging and confirm a balanced posting appears in sales book, general ledger, trial balance, P&L and balance sheet.
- [ ] Confirm duplicate/retried posting does not create a second journal.
- [ ] Confirm draft deletion removes only the draft and preserves an audit event.
- [ ] Confirm posted invoice and posted journal rows cannot be directly deleted or edited.
- [ ] Confirm tax-bearing or allocated invoice cancellation fails closed.
- [ ] Confirm eligible unpaid/untaxed cancellation creates an equal-and-opposite linked journal and retains the original.
- [ ] Confirm supplier bill posting updates purchase book, journal, GL and trial balance once.
- [ ] Confirm receipt posting debits cash/bank and credits customer advances.
- [ ] Confirm receipt allocation creates a linked debit to customer advances and credit to receivables.
- [ ] Confirm allocation cannot exceed either posted invoice outstanding or unallocated receipt balance, including concurrent requests.
- [ ] Confirm a posted receipt or supplier bill cannot be deleted or silently edited.
- [ ] Confirm cross-business references are rejected.
- [ ] Run Supabase database advisors and resolve all critical/high findings.
- [ ] Do not merge or deploy until SQL has been executed and verified in staging.

## Next implementation slice

Implement the API/frontend adapters for the database routines and period-parameterized reporting endpoints. Add automated tests that prove the full source-document → journal → subledger → reporting flow for sales, purchases and receipts before expanding into bank reconciliation, inventory and fixed assets.
