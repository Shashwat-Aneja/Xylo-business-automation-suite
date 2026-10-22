# Xylo product and implementation architecture

## Product definition

Xylo is a bookkeeping and business-operations workspace for sole proprietors and small businesses. It should feel deliberate, calm, and trustworthy—not like a generic SaaS admin template. The product does not include AI features.

## Product principles

- Accounting correctness and traceability take precedence over convenience shortcuts.
- Each financial record belongs to a business workspace and is protected by server-side authorization.
- Store money as integer minor units or an exact decimal type; never use binary floating point for persisted accounting values.
- Store transaction timestamps consistently and distinguish date-only accounting dates from instants.
- Keep a clear audit trail for financially material changes.
- Internationalize display and input: locale, time zone, country, currency, and fiscal-year configuration are explicit business settings.
- Empty, loading, error, and success states are designed—not left to browser defaults.
- Use progressive disclosure and dense, readable registers instead of a page full of generic cards.
- Never treat client-side filtering or hidden controls as authorization.

## Locked visual system

- Warm paper: #F3EFE6
- Soft ivory: #FAF8F2
- Ink: #24231F
- Terracotta: #873F32; darker interaction state: #6E3027
- Muted olive: #74745D
- Divider: #D7D1C5
- Editorial serif headings; restrained sans-serif for data and controls.
- Generous whitespace, thin rules, underlined fields, asymmetrical layouts, quiet transitions.
- Respect reduced-motion preferences and keyboard access.
- Avoid neon gradients, glow effects, heavy glassmorphism, excessive rounded cards, and templated AI-looking layouts.

## Current technical direction

- Frontend: React, TypeScript, Vite, Tailwind CSS.
- API: Node.js and Express; validate all inputs at the API boundary.
- Data and identity: Supabase PostgreSQL, Supabase Auth, row-level security.
- Source control: GitHub feature branches and reviewed changes.
- Hosting: Vercel previews; do not promote unfinished work to production by default.

The currently deployed auth and workspace screens are static HTML prototypes using the Supabase browser client. The transaction register is also a static UI prototype and uses in-memory sample records. These are not yet the production React application. Never describe prototype data as persisted or synchronized.

## Current database foundation

- `profiles`: user profile metadata keyed to the Supabase Auth user.
- `businesses`: workspace identity and accounting defaults, owned by a user.
- RLS is enabled for both tables with owner-scoped policies.
- A database trigger creates a profile row for a newly created Auth user.
- No password is stored in application profile tables.

## Proposed domain model, to implement incrementally

1. **Workspace and access**: profiles, businesses, business_memberships, invitations, roles.
2. **Accounting setup**: chart_of_accounts, tax_rates, fiscal_periods, numbering_sequences.
3. **Financial records**: contacts, invoices, invoice_lines, bills, bill_lines, transactions, transaction_splits, attachments.
4. **Double-entry accounting**: journal_entries, journal_lines, posting rules, account balances derived from posted journal lines.
5. **Cash and settlement**: payment allocations, bank accounts, statement imports, reconciliation sessions and reconciliation items.
6. **Operations**: recurring templates, reminders, activity/audit events, notification preferences.
7. **Reporting**: reporting queries/views for profit and loss, balance sheet, cash flow, receivables/payables aging, tax summaries.

Do not create every table at once. Before each migration, specify ownership, constraints, indexes, RLS policies, deletion semantics, and how financial records remain auditable.

## API conventions

- Version external endpoints under `/api/v1`.
- Derive the authenticated user from a verified Supabase JWT; never trust a client-supplied owner ID.
- Validate request bodies, query parameters, currency codes, date ranges, and pagination.
- Use stable error shapes with machine-readable codes and safe user-facing messages.
- Apply idempotency keys to operations that may be retried (payments, imports, posting).
- Never log passwords, access tokens, API keys, or full sensitive financial payloads.
- Keep service-role credentials server-only; browser code uses only the publishable key and relies on RLS.

## Accounting invariants

- Posted journal entries must balance: total debits equal total credits.
- Drafts may be incomplete; posted entries should be immutable or changed through explicit reversal/correction workflows.
- Amounts and currency are explicit; do not silently add amounts in different currencies.
- Define rounding policy and currency precision at the domain boundary.
- Reports must state their period, accounting basis, and currency.
- Reconciliation differences must be visible; do not silently force balances to match.

## Implementation sequence

### Phase 1 — Foundation and access
Finish auth redirect and email delivery configuration; verify sign-up, confirmation, sign-in, sign-out, session refresh, and RLS isolation. Establish the React/Vite app, environment variable validation, lint/typecheck/test commands, and preview deployment conventions.

### Phase 2 — Business setup
Complete workspace creation, locale/currency/time-zone defaults, fiscal-year settings, onboarding recovery, and multiple-workspace navigation. Validate all fields on the server.

### Phase 3 — Accounting core
Build chart of accounts, contacts, transaction register, create/edit flows, journal posting, audit trail, and tests for debit/credit balance and currency precision.

### Phase 4 — Documents and cash
Invoices, bills, payment tracking, document attachments, import/export, bank statement matching, and reconciliation.

### Phase 5 — Reporting and operations
Financial reports, period comparisons, overdue lists, reminders, recurring records, and data export.

### Phase 6 — Production readiness
Authorization review, migration rollback strategy, backups/restore test, accessibility checks, automated tests, observability, rate limits, security review, and user-facing support/error states.

## Immediate next steps

1. Test the current auth callback on a stable canonical URL and fix redirects before relying on confirmation emails.
2. Configure a verified Resend sender and connect it to Supabase Auth SMTP without exposing secrets in client code or chat.
3. Add repeatable frontend tooling and move static prototypes into React components without changing the approved visual language.
4. Connect the transaction register to a server-validated API and real database tables before using it for real financial data.
5. Add automated tests for RLS ownership isolation and financial invariants before expanding features.
