# Database Layer — Technical Specification  
### XYLO Business Automation Suite

This document defines XYLO's database design, schema, storage strategy, and operational considerations.  
It is intended to provide a clear, production-ready blueprint for storing users, transactions, ledgers, reports, chatbot logs, and automation metadata.

---

## 1. Goals & Requirements

- **Reliability:** ACID-safe for financial transactions.  
- **Simplicity for dev:** SQLite for development; PostgreSQL for production.  
- **Auditability:** Full transaction history, timestamps, and user attribution.  
- **Performance:** Indexed read paths for reports and ledger queries.  
- **Backup & Restore:** Simple exports (JSON/CSV) + periodic DB dumps.  
- **Extensibility:** Easy to add new tables (inventory, payroll, etc.).

---

## 2. Technology Recommendations

- **Development:** SQLite (file-based, easy to run locally).  
- **Production:** PostgreSQL (reliability, concurrency, indexing, JSONB).  
- **ORM:** SQLAlchemy (Python) or Tortoise ORM / Pydantic models for FastAPI.  
- **Migrations:** Alembic for SQLAlchemy / builtin migration tooling.

---

## 3. High-Level Tables (Core Schema)

### 3.1 users
Stores application users and roles.
users

id (PK, UUID)

email (unique)

password_hash

name

role (enum: admin, staff, viewer)

created_at (timestamp)

last_login (timestamp)


### 3.2 transactions
Raw transaction records (ingested from uploads / manual).
transactions

id (PK, UUID)

user_id (FK → users.id)

source (enum: manual, invoice_upload, bank_import)

reference (string) # invoice number or external id

date (date)

amount (decimal)

currency (string)

description (text)

metadata (JSONB) # parsed fields (vendor, tax, etc.)

created_at (timestamp)

processed (boolean) # whether already converted into journal entries


### 3.3 journal_entries
Double-entry journal entries produced by the accounting engine.

journal_entries

id (PK, UUID)

transaction_id (FK → transactions.id) # optional link back to source

entry_date (date)

description (text)

created_at (timestamp)


### 3.4 journal_lines
Line items (debit/credit) for each journal entry.

journal_lines

id (PK, UUID)

journal_entry_id (FK → journal_entries.id)

account_code (string) # e.g., "1001-Cash" or numeric code

debit (decimal, default 0)

credit (decimal, default 0)

cost_center (optional)


### 3.5 accounts
Chart of accounts.
accounts

id (PK)

code (string, unique) # "1001", "2001"

name (string)

type (enum: asset, liability, equity, income, expense)

parent_id (nullable FK → accounts.id)

normal_balance (enum: debit, credit)


### 3.6 reports
Generated report metadata and cached result locations.
reports

id (PK, UUID)

user_id (FK → users.id)

type (enum: daily_summary, pnl, balance_sheet)

params (JSONB)

generated_at (timestamp)

location (string) # path to JSON/CSV/PDF in samples/ or blob storage


### 3.7 chatbot_logs
Conversation history for analytics and auditing.

chatbot_logs

id (PK, UUID)

user_id (nullable FK → users.id)

session_id (string)

user_query (text)

detected_intent (string)

entities (JSONB)

bot_response (text)

created_at (timestamp)


### 3.8 automation_tasks
Scheduled / triggered tasks history.

automation_tasks

id (PK, UUID)

task_name (string)

params (JSONB)

status (enum: pending, running, success, failed)

run_at (timestamp)

finished_at (timestamp, nullable)

result_location (string, optional)


---

## 4. Indexing & Performance

Recommended indexes (Postgres):

- `users(email)` unique index  
- `transactions(user_id, date)` for report queries  
- `journal_lines(journal_entry_id)` FK index  
- `journal_lines(account_code)` for account balance queries  
- `reports(user_id, generated_at)` for recent reports  
- `chatbot_logs(session_id, created_at)` for analytics  
- Partial index: `transactions(processed) WHERE processed = false` to speed ingestion workflows

Use `EXPLAIN` to tune slow reporting queries. For heavy report workloads, create materialized views (e.g., monthly aggregated totals) and refresh nightly.

---

## 5. Sample Queries (Postgres style)

**Trial balance (simplified):**
```sql
SELECT jl.account_code,
       SUM(jl.debit) AS total_debit,
       SUM(jl.credit) AS total_credit
FROM journal_lines jl
JOIN journal_entries je ON je.id = jl.journal_entry_id
WHERE je.entry_date BETWEEN :from AND :to
GROUP BY jl.account_code;

Profit & Loss (income - expenses):
SELECT a.type, SUM(jl.debit - jl.credit) AS amount
FROM journal_lines jl
JOIN accounts a ON a.code = jl.account_code
JOIN journal_entries je ON je.id = jl.journal_entry_id
WHERE je.entry_date BETWEEN :from AND :to
  AND a.type IN ('income','expense')
GROUP BY a.type;

