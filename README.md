# Xylo — Bookkeeping and business operations

Xylo is a bookkeeping and business-operations workspace for sole proprietors and small businesses. The product direction is a clear, carefully designed, international-ready accounting experience with **no AI features**.

## Product priorities

- Secure business workspaces with Supabase Auth and row-level security.
- A dependable transaction register, invoices, bills, payment tracking, reconciliation, and financial reports.
- Double-entry accounting with auditable posting and correction workflows.
- Explicit currency, locale, time zone, and fiscal-year settings.
- Human-designed editorial interface: warm paper and ivory surfaces, ink typography, terracotta accents, fine dividers, and generous whitespace.

## Planned stack

- **Frontend:** React + TypeScript + Vite + Tailwind CSS
- **API:** Node.js + Express
- **Database and identity:** Supabase PostgreSQL + Supabase Auth + RLS
- **Hosting and delivery:** Vercel previews, GitHub feature branches

## Current implementation status

This repository is transitioning from an earlier backend prototype into the current Xylo product. The auth, workspace, and transaction-register screens currently include static HTML prototypes. The transaction register uses in-memory sample data and is **not yet connected to the production database**. Do not use it to record real financial data.

Database foundation currently includes `profiles` and `businesses`, with owner-scoped RLS policies and profile creation on signup. Email confirmation redirects and the Resend/Supabase SMTP setup still require end-to-end verification.

## Preview screens

- Auth: `/auth-experience/`
- Workspace onboarding: `/dashboard/`
- Transaction register prototype: `/transactions/`
- Invoice register prototype: `/invoices/`
- Financial reports prototype: `/reports/`

## Architecture and delivery plan

See [Xylo product architecture](docs/xylo-product-architecture.md) for the product principles, locked design system, proposed domain model, accounting invariants, API conventions, and phased implementation plan.

## Development principles

1. Keep unfinished work on feature branches and preview deployments; do not silently promote it to production.
2. Never expose Supabase service-role credentials or Resend API keys in browser code, repository files, or chat.
3. Enforce workspace ownership in database RLS and server authorization—not only in the UI.
4. Treat money with exact decimal or integer minor-unit representations; avoid binary floating-point persistence.
5. Test authorization isolation, balanced journal entries, currency handling, and error states before production use.
