# Xylo Dashboard

The first interactive frontend foundation for Xylo, an accounting and business-automation workspace for sole proprietors and small businesses.

## Stack
- React + TypeScript + Vite
- Tailwind CSS tooling, with product styling expressed through CSS design tokens
- Lucide icons

## Run locally
```bash
npm install
npm run dev
```

## Build
```bash
npm run build
```

## Current preview scope
- Responsive app shell and navigation
- Dashboard KPI cards, cash-flow visualization, business pulse, tasks, and recent transactions
- Search across visible transaction data
- Add transaction modal and CSV export
- Four atmosphere themes: Paper, Void, Terminal, and Dusk
- Xylo AI assistant preview panel and module placeholders

## Important data boundary
This is a frontend preview with illustrative sample data. Transactions added through the interface remain in memory and reset on refresh. No authentication, database, or external AI provider is connected yet. Do not use the demo data for real accounting decisions.

## Next phases
1. Review the frontend and refine product requirements.
2. Connect the existing accounting backend through a typed API client.
3. Design the Supabase/PostgreSQL schema and authentication flow.
4. Add validated accounting operations, auditability, and tests.
5. Connect AI and automation through server-side services only.
