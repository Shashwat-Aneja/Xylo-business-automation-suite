# Local demo data for Xylo accounting

This fixture is for a disposable local/development database only. It is not run by migrations and must never be executed against `xylo-production`.

## Fixture contents
- Demo business: Xylo Demo Studio (INR, Asia/Kolkata, accrual basis)
- Chart-of-accounts fixture: cash/bank, receivables, payables, service revenue, office supplies expense
- Open demo accounting period for FY 2026–27
- One customer and one supplier
- One ₹18,000 draft sales invoice with a matching line
- One ₹4,200 draft supplier bill with a matching line
- No GST/tax assumptions and no posted journals. Posting remains gated by independent applicability/rule approval.

## Preconditions
1. Start a disposable local Supabase instance and apply the base Xylo foundation migration followed by the interconnected accounting, purchase-book, receipt/allocation, and supplier-payment migrations.
2. Create a test auth user locally.
3. In a local SQL session, set `xylo.demo_owner_id` to that test user's UUID for the session, then run `supabase/seed/demo_accounting.sql`.
4. Inspect the inserted rows and test RLS through the application using the test user's session.

The seed is transaction-scoped and uses stable demo business/document names. It deliberately does not invent a real customer, supplier, tax registration, or posted accounting balance.
