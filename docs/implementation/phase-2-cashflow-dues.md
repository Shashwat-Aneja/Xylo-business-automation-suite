# Phase 2 — Cashflow & Dues: implementation contract

## Status and safety boundary

- Branch: `feature/xylo-cashflow-phase-2`
- This phase begins with contract, query boundary, and verification requirements.
- Source migrations and local-only demo fixtures are committed to this branch; they have not been executed against any Supabase project.
- The only active Supabase project found is `xylo-production`; there are no development branches. Production remains unchanged.
- The existing HTML dashboards are prototypes; this document does not claim they are connected to the accounting database.
- Xylo remains a deterministic bookkeeping and business-operations product. Do not add AI-generated estimates or opaque scoring.

## Phase 2 outcomes

1. Establish an authenticated, business-scoped read service for recorded cash, receivables, payables, due dates, and a transparent short-term cash forecast.
2. Add the supplier-payment and supplier-bill-allocation schema and controlled posting RPC before treating bills as paid or using them as confirmed forecast outflows. The first pass now exists in `20261023150000_supplier_payments.sql`; database-level integration tests remain a gate.
3. Add query-level and database integration tests for business isolation, date boundaries, partial allocations, over-allocation, reversals, closed periods, and currency separation.
4. Connect the read service to the Cashflow & Dues UI only after staging schema and authorization checks pass.

## Local test data

See `docs/implementation/local-demo-data.md` and `supabase/seed/demo_accounting.sql`. The fixture creates a sample business, chart of accounts, period, customer, supplier, one draft invoice (₹18,000), and one draft supplier bill (₹4,200). It intentionally creates no posted journals and enables no tax/compliance rules. Run it only against a disposable local/dev database after applying the accounting migrations. Do not run it against `xylo-production`.

## Current environment constraint

The connected Supabase account has one active project, `xylo-production`, and no development branches. Older projects are inactive. No data was inserted because the requested test fixture requires the new accounting schema and should not be written to production. A separate disposable local/dev database is needed for an actual seeded runtime test.

## Domain contracts

### Recorded cash

Return balances per business, currency, and as-of date. Derive them only from posted journal lines attached to active accounts explicitly classified as cash or bank. Use the chart-of-accounts type and normal-balance conventions defined by the accounting core; do not infer cash from sales totals or the account label alone. Exclude drafts and future-dated entries. Return the as-of date and source coverage.

### Receivables

Use posted sales invoices and their valid posted allocation/correction journals. Outstanding = posted gross amount minus posted allocations and supported corrections. Cancelled documents must not appear as collectible balances. Return invoice ID, customer, invoice/due dates, currency, gross, allocated, outstanding, days overdue, and source journal IDs.

### Payables

Use posted supplier bills less posted supplier payments and valid allocations/corrections. Until a controlled supplier-payment workflow exists and has been tested, the API must mark paid/outstanding status as unavailable rather than present gross bill totals as a fully reconciled payable balance. Return bill ID, supplier, invoice/due dates, currency, gross, paid, outstanding, days overdue, and source journal IDs.

### Forecast

Return daily buckets per currency and a configurable horizon. Starting cash must come from recorded cash. Expected inflows must reference a posted receivable and its remaining outstanding amount. Expected outflows must reference a posted payable and its remaining outstanding amount. Preserve original due dates and disclose any manual date overrides. Do not net amounts across currencies. Distinguish recorded balances from expected movements in both payload and UI.

Suggested bucket fields:
- `date`: ISO calendar date in the business time zone.
- `currency`: ISO 4217 currency code.
- `opening_cash`, `expected_inflows`, `expected_outflows`, `closing_forecast`: exact decimal strings.
- `inflow_sources`, `outflow_sources`: document IDs and amounts contributing to the bucket.
- `warnings`: missing-payment-workflow, overdue-document, unclassified-account, or incomplete-source warnings.

## Required supplier-payment workflow

Implement as a separate additive migration after the accounting base has been staged and verified.

- Supplier payment draft: business, supplier, payment date, currency, cash/bank account, amount, external reference, idempotency key, creator, status.
- Payment allocations: payment-to-supplier-bill link, business, amount, journal link, idempotency key.
- Posting routine: authenticate caller; authorize business owner/member; lock payment and target bills; require open accounting period; verify same business, supplier, and currency; verify active cash/bank asset and payable liability accounts; prevent allocation above payment unallocated balance or bill outstanding; create balanced linked journal and audit event atomically.
- Posted payment and allocation records are immutable. Corrections use separately linked reversing/adjustment entries; never edit posted rows in place.
- Database constraints/triggers and transaction locks must prevent concurrent over-allocation.
- Views must use `security_invoker = true` and must not bypass source-table RLS.
- Do not enable GST/tax behavior without separately approved rules and evidence.

## Authorization and RLS gates

Before enabling any endpoint:
- Confirm every new table has RLS enabled and appropriate policies for SELECT, INSERT, UPDATE, DELETE.
- Ensure direct client writes cannot bypass controlled posting routines for posted records.
- Ensure account, customer, supplier, invoice, bill, payment, allocation, and journal references all belong to the same business.
- Test authenticated owner, authorized non-owner (if membership is supported), unrelated user, anonymous caller, and service-role operations separately.
- Keep privileged service credentials server-only. Prefer Supabase user-scoped JWT/RLS for ordinary user reads.
- Do not claim multi-user authorization until the repository's business membership model has been inspected and tested.

## Acceptance tests

### Accounting integrity
- Draft documents have no report or forecast effect.
- Only posted journal lines affect recorded cash and statements.
- Every posted journal balances exactly to the currency minor unit.
- Retrying a posting request does not create a duplicate journal.
- Posted documents, journal entries, journal lines, and allocations cannot be silently mutated or deleted.
- A correction creates a linked entry and preserves the original.

### Dues and allocations
- Partial and full receipt allocations yield the expected outstanding amount.
- Over-allocation fails for both invoice and receipt/payment balance, including concurrent requests.
- Supplier payment allocation cannot cross businesses, suppliers, or currencies.
- Cancelled invoices and bills are excluded from collectible/payable totals according to the approved correction workflow.
- Overdue days are calculated against the business-local current date and due date, not UTC date by accident.

### Forecast
- No draft or unposted transaction affects the starting balance.
- Forecast totals reconcile to opening cash plus listed inflows minus listed outflows.
- Different currencies produce separate buckets.
- Missing payment lifecycle, unclassified accounts, and stale/overdue source records generate visible warnings.
- Empty source data is returned as an explicit empty/zero state, not fabricated sample figures.

## Execution sequence

1. Complete static schema/RLS review and resolve migration ordering or constraint issues.
2. Apply all migrations to an isolated disposable staging project only.
3. Run database integration tests and Supabase database advisors; resolve critical/high findings.
4. Implement and test supplier payments and allocations.
5. Implement authenticated, read-only cashflow query functions/API endpoints.
6. Connect the UI and test against staging data.
7. Request review before merge; production deployment requires separate explicit authorization.
