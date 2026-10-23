-- Xylo interconnected accounting foundation.
-- This migration is intentionally additive. It does not deploy or enable GST compliance.
-- Posted accounting records are corrected through linked entries, never silently deleted.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists public.business_accounting_profiles (
  business_id uuid primary key references public.businesses(id) on delete restrict,
  legal_form text not null check (legal_form in ('sole_proprietorship','private_limited_company','public_limited_company','other_company','other')),
  framework_code text,
  framework_version text,
  reporting_basis_default text not null default 'accrual' check (reporting_basis_default in ('cash','accrual')),
  supported_reporting_bases text[] not null default array['accrual']::text[],
  gst_registration_status text not null default 'unknown' check (gst_registration_status in ('registered','not_registered','composition','unknown','not_applicable')),
  gstin text,
  profile_effective_from date not null default current_date,
  profile_effective_to date,
  applicability_review_status text not null default 'unreviewed' check (applicability_review_status in ('unreviewed','needs_review','approved','rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (profile_effective_to is null or profile_effective_to >= profile_effective_from),
  check (reporting_basis_default = any(supported_reporting_bases))
);

create table if not exists public.accounting_periods (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  period_name text not null,
  starts_on date not null,
  ends_on date not null,
  status text not null default 'open' check (status in ('open','closing','closed')),
  closed_at timestamptz,
  closed_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique (business_id, period_name),
  check (ends_on >= starts_on),
  check ((status = 'closed' and closed_at is not null) or status <> 'closed')
);
create index if not exists accounting_periods_business_dates_idx
  on public.accounting_periods (business_id, starts_on, ends_on);

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  display_name text not null,
  legal_name text,
  email text,
  phone text,
  tax_identifier text,
  billing_address jsonb not null default '{}'::jsonb,
  payment_terms_days integer not null default 0 check (payment_terms_days >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, id),
  check (char_length(trim(display_name)) between 1 and 200)
);

create table if not exists public.sales_invoices (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  customer_id uuid not null,
  invoice_number text not null,
  document_date date not null,
  supply_date date,
  due_date date,
  accounting_date date not null,
  currency_code text not null default 'INR' check (currency_code ~ '^[A-Z]{3}$'),
  accounts_receivable_account_id uuid not null references public.accounts(id) on delete restrict,
  net_amount numeric(18,2) not null default 0 check (net_amount >= 0),
  tax_amount numeric(18,2) not null default 0 check (tax_amount >= 0),
  gross_amount numeric(18,2) not null default 0 check (gross_amount >= 0),
  status text not null default 'draft' check (status in ('draft','posted','cancelled')),
  compliance_status text not null default 'not_assessed' check (compliance_status in ('not_assessed','pending_review','approved','rejected','not_applicable')),
  posting_journal_id uuid references public.journal_entries(id) on delete restrict,
  cancellation_journal_id uuid references public.journal_entries(id) on delete restrict,
  cancellation_reason text,
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users(id),
  idempotency_key text,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, invoice_number),
  unique (business_id, id),
  unique (business_id, idempotency_key),
  foreign key (business_id, customer_id) references public.customers(business_id, id) on delete restrict,
  check (gross_amount = net_amount + tax_amount),
  check (due_date is null or due_date >= document_date),
  check ((status = 'draft' and posting_journal_id is null and cancellation_journal_id is null)
      or (status = 'posted' and posting_journal_id is not null and cancellation_journal_id is null)
      or (status = 'cancelled' and posting_journal_id is not null and cancellation_journal_id is not null
          and cancellation_reason is not null and cancelled_at is not null))
);
create index if not exists sales_invoices_business_date_idx
  on public.sales_invoices (business_id, document_date desc);
create index if not exists sales_invoices_customer_status_idx
  on public.sales_invoices (business_id, customer_id, status);

create table if not exists public.sales_invoice_lines (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  invoice_id uuid not null,
  line_number integer not null check (line_number > 0),
  description text not null,
  quantity numeric(18,4) not null default 1 check (quantity > 0),
  unit_price numeric(18,4) not null check (unit_price >= 0),
  discount_amount numeric(18,2) not null default 0 check (discount_amount >= 0),
  net_amount numeric(18,2) not null check (net_amount >= 0),
  tax_amount numeric(18,2) not null default 0 check (tax_amount >= 0),
  revenue_account_id uuid not null references public.accounts(id) on delete restrict,
  tax_account_id uuid references public.accounts(id) on delete restrict,
  tax_code text,
  tax_rule_version text,
  created_at timestamptz not null default now(),
  unique (invoice_id, line_number),
  foreign key (business_id, invoice_id) references public.sales_invoices(business_id, id) on delete cascade,
  check (discount_amount <= round(quantity * unit_price, 2)),
  check (net_amount = round(quantity * unit_price, 2) - discount_amount),
  check ((tax_amount = 0) or (tax_account_id is not null and tax_code is not null))
);
create index if not exists sales_invoice_lines_invoice_idx
  on public.sales_invoice_lines (business_id, invoice_id);

create table if not exists public.cash_receipts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  customer_id uuid not null,
  receipt_number text not null,
  receipt_date date not null,
  currency_code text not null default 'INR' check (currency_code ~ '^[A-Z]{3}$'),
  amount numeric(18,2) not null check (amount > 0),
  cash_bank_account_id uuid not null references public.accounts(id) on delete restrict,
  status text not null default 'draft' check (status in ('draft','posted','void')),
  journal_entry_id uuid references public.journal_entries(id) on delete restrict,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique (business_id, receipt_number),
  unique (business_id, id),
  foreign key (business_id, customer_id) references public.customers(business_id, id) on delete restrict,
  check ((status = 'draft' and journal_entry_id is null) or (status <> 'draft' and journal_entry_id is not null))
);

create table if not exists public.invoice_receipt_allocations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  invoice_id uuid not null,
  receipt_id uuid not null,
  amount numeric(18,2) not null check (amount > 0),
  created_at timestamptz not null default now(),
  unique (invoice_id, receipt_id),
  foreign key (business_id, invoice_id) references public.sales_invoices(business_id, id) on delete restrict,
  foreign key (business_id, receipt_id) references public.cash_receipts(business_id, id) on delete restrict
);
create index if not exists invoice_receipt_allocations_invoice_idx
  on public.invoice_receipt_allocations (business_id, invoice_id);

create table if not exists public.accounting_rule_registry (
  id uuid primary key default gen_random_uuid(),
  rule_id text not null,
  rule_version text not null,
  rule_type text not null check (rule_type in ('accounting','tax','invoice','applicability','reporting','period_control')),
  jurisdiction text not null,
  source_authority text,
  source_reference text,
  source_url text,
  effective_from date not null,
  effective_to date,
  applicability jsonb not null default '{}'::jsonb,
  implementation_key text not null,
  review_status text not null default 'unreviewed' check (review_status in ('draft','unreviewed','needs_review','approved','rejected','retired')),
  release_status text not null default 'disabled' check (release_status in ('disabled','pilot','enabled')),
  reviewer text,
  reviewed_at timestamptz,
  test_evidence jsonb not null default '{}'::jsonb,
  supersedes_rule_version text,
  created_at timestamptz not null default now(),
  unique (rule_id, rule_version),
  check (effective_to is null or effective_to >= effective_from),
  check (release_status <> 'enabled' or (review_status = 'approved' and reviewer is not null and reviewed_at is not null))
);

create table if not exists public.accounting_audit_events (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  actor_id uuid references auth.users(id),
  event_type text not null,
  entity_type text not null,
  entity_id uuid not null,
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);
create index if not exists accounting_audit_business_time_idx
  on public.accounting_audit_events (business_id, occurred_at desc);

-- Link existing journals to their source document and correction history.
alter table public.journal_entries
  add column if not exists source_document_type text,
  add column if not exists source_document_id uuid,
  add column if not exists entry_kind text not null default 'standard'
    check (entry_kind in ('standard','original','reversal','adjustment')),
  add column if not exists reversal_of uuid references public.journal_entries(id) on delete restrict,
  add column if not exists policy_version text,
  add column if not exists idempotency_key text;
create unique index if not exists journal_entries_business_idempotency_idx
  on public.journal_entries (business_id, idempotency_key) where idempotency_key is not null;
create unique index if not exists journal_entries_one_original_per_source_idx
  on public.journal_entries (business_id, source_document_type, source_document_id)
  where status = 'posted' and entry_kind = 'original';
create index if not exists journal_entries_source_idx
  on public.journal_entries (business_id, source_document_type, source_document_id);

-- Reject posting a journal unless the entire journal balances.
create or replace function private.assert_journal_balanced()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_debits numeric(18,2);
  v_credits numeric(18,2);
  v_count integer;
begin
  if new.status = 'posted' and (tg_op = 'INSERT' or old.status is distinct from 'posted') then
    select count(*), coalesce(sum(debit), 0), coalesce(sum(credit), 0)
      into v_count, v_debits, v_credits
      from public.journal_lines
      where journal_entry_id = new.id;
    if v_count < 2 or v_debits <> v_credits then
      raise exception using errcode = '23514',
        message = 'JOURNAL_NOT_BALANCED',
        detail = format('Posted journals require at least two lines and equal debits/credits; lines=%s debits=%s credits=%s', v_count, v_debits, v_credits);
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.assert_journal_balanced() from public, anon, authenticated;
drop trigger if exists journal_entries_balance_before_post on public.journal_entries;
create trigger journal_entries_balance_before_post
before insert or update of status on public.journal_entries
for each row execute function private.assert_journal_balanced();

-- Posted journals and their lines are append-only. Corrections are new linked journals.
create or replace function private.protect_posted_journal()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_status text;
begin
  if tg_table_name = 'journal_entries' then
    if tg_op = 'DELETE' and old.status = 'posted' then
      raise exception using errcode = '55000', message = 'POSTED_JOURNAL_IMMUTABLE';
    end if;
    if tg_op = 'UPDATE' and old.status = 'posted' then
      raise exception using errcode = '55000', message = 'POSTED_JOURNAL_IMMUTABLE';
    end if;
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  select status into v_status from public.journal_entries where id = coalesce(old.journal_entry_id, new.journal_entry_id);
  if v_status = 'posted' then
    raise exception using errcode = '55000', message = 'POSTED_JOURNAL_LINES_IMMUTABLE';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;
revoke all on function private.protect_posted_journal() from public, anon, authenticated;
drop trigger if exists journal_entries_immutable_after_post on public.journal_entries;
create trigger journal_entries_immutable_after_post
before update or delete on public.journal_entries
for each row execute function private.protect_posted_journal();
drop trigger if exists journal_lines_immutable_after_post on public.journal_lines;
create trigger journal_lines_immutable_after_post
before insert or update or delete on public.journal_lines
for each row execute function private.protect_posted_journal();

-- Guard invoice state transitions. Drafts may be edited/deleted; posted documents are immutable.
create or replace function private.guard_sales_invoice()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_journal_status text;
begin
  if tg_op = 'DELETE' then
    if old.status <> 'draft' then
      raise exception using errcode = '55000', message = 'POSTED_INVOICE_CANNOT_BE_DELETED; use a permitted correction workflow';
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' and old.status <> 'draft' then
    if old.status = 'posted' and new.status = 'cancelled'
       and new.id = old.id and new.business_id = old.business_id
       and new.customer_id = old.customer_id
       and new.invoice_number = old.invoice_number
       and new.document_date = old.document_date
       and new.accounting_date = old.accounting_date
       and (to_jsonb(new) - array['status','cancellation_journal_id','cancellation_reason','cancelled_at','cancelled_by','updated_at'])
           = (to_jsonb(old) - array['status','cancellation_journal_id','cancellation_reason','cancelled_at','cancelled_by','updated_at'])
       and new.cancellation_journal_id is not null
       and nullif(trim(new.cancellation_reason), '') is not null then
      select status into v_journal_status from public.journal_entries
       where id = new.cancellation_journal_id and business_id = old.business_id
         and source_document_type = 'sales_invoice_cancellation'
         and source_document_id = old.id and entry_kind = 'reversal';
      if v_journal_status = 'posted' then return new; end if;
    end if;
    raise exception using errcode = '55000', message = 'POSTED_INVOICE_IMMUTABLE; use a permitted correction workflow';
  end if;

  if tg_op = 'UPDATE' and old.status = 'draft' and new.status = 'posted' then
    select status into v_journal_status from public.journal_entries
      where id = new.posting_journal_id and business_id = new.business_id
        and source_document_type = 'sales_invoice' and source_document_id = new.id
        and entry_kind = 'original';
    if v_journal_status <> 'posted' then
      raise exception using errcode = '23514', message = 'INVOICE_REQUIRES_POSTED_JOURNAL';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.guard_sales_invoice() from public, anon, authenticated;
drop trigger if exists sales_invoice_state_guard on public.sales_invoices;
create trigger sales_invoice_state_guard
before update or delete on public.sales_invoices
for each row execute function private.guard_sales_invoice();

-- Only allow invoice line edits while the parent invoice is a draft.
create or replace function private.guard_sales_invoice_line()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_invoice_status text;
begin
  select status into v_invoice_status
    from public.sales_invoices
    where id = coalesce(old.invoice_id, new.invoice_id)
      and business_id = coalesce(old.business_id, new.business_id);
  if v_invoice_status is distinct from 'draft' then
    raise exception using errcode = '55000', message = 'POSTED_INVOICE_LINES_IMMUTABLE';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;
revoke all on function private.guard_sales_invoice_line() from public, anon, authenticated;
drop trigger if exists sales_invoice_lines_state_guard on public.sales_invoice_lines;
create trigger sales_invoice_lines_state_guard
before insert or update or delete on public.sales_invoice_lines
for each row execute function private.guard_sales_invoice_line();

-- All accounting-facing tables use owner-scoped RLS. Membership expansion can be added later.
alter table public.business_accounting_profiles enable row level security;
alter table public.accounting_periods enable row level security;
alter table public.customers enable row level security;
alter table public.sales_invoices enable row level security;
alter table public.sales_invoice_lines enable row level security;
alter table public.cash_receipts enable row level security;
alter table public.invoice_receipt_allocations enable row level security;
alter table public.accounting_rule_registry enable row level security;
alter table public.accounting_audit_events enable row level security;

create policy "Owners manage accounting profiles" on public.business_accounting_profiles for all to authenticated
using (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())))
with check (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())));
create policy "Owners manage accounting periods" on public.accounting_periods for all to authenticated
using (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())))
with check (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())));
create policy "Owners manage customers" on public.customers for all to authenticated
using (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())))
with check (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())));
create policy "Owners read invoices" on public.sales_invoices for select to authenticated
using (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())));
create policy "Owners create draft invoices" on public.sales_invoices for insert to authenticated
with check (status = 'draft' and exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())));
create policy "Owners update own invoices" on public.sales_invoices for update to authenticated
using (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())))
with check (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())));
create policy "Owners delete draft invoices" on public.sales_invoices for delete to authenticated
using (status = 'draft' and exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())));
create policy "Owners manage invoice lines" on public.sales_invoice_lines for all to authenticated
using (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())))
with check (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())));
create policy "Owners manage cash receipts" on public.cash_receipts for all to authenticated
using (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())))
with check (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())));
create policy "Owners manage invoice receipt allocations" on public.invoice_receipt_allocations for all to authenticated
using (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())))
with check (
  exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid()))
  and exists (select 1 from public.sales_invoices i where i.id = invoice_id and i.business_id = business_id)
  and exists (select 1 from public.cash_receipts r where r.id = receipt_id and r.business_id = business_id)
);
create policy "Authenticated read accounting rules" on public.accounting_rule_registry for select to authenticated using (true);
create policy "Owners read audit events" on public.accounting_audit_events for select to authenticated
using (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())));

grant select, insert, update, delete on public.business_accounting_profiles, public.accounting_periods, public.customers to authenticated;
grant select, insert, update, delete on public.sales_invoices, public.sales_invoice_lines to authenticated;
grant select, insert, update, delete on public.cash_receipts, public.invoice_receipt_allocations to authenticated;
grant select on public.accounting_rule_registry, public.accounting_audit_events to authenticated;

-- Posting RPC: journal, lines, invoice status and audit record are one PostgreSQL transaction.
create or replace function public.post_sales_invoice(p_invoice_id uuid, p_idempotency_key text)
returns table (invoice_id uuid, journal_entry_id uuid, document_status text)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_invoice public.sales_invoices%rowtype;
  v_line record;
  v_journal_id uuid;
  v_count integer;
  v_net numeric(18,2);
  v_tax numeric(18,2);
  v_gross numeric(18,2);
  v_period_status text;
  v_ar_type text;
  v_existing uuid;
begin
  if auth.uid() is null then raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED'; end if;
  if nullif(trim(p_idempotency_key), '') is null then raise exception using errcode = '22023', message = 'IDEMPOTENCY_KEY_REQUIRED'; end if;

  select * into v_invoice from public.sales_invoices where id = p_invoice_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'INVOICE_NOT_FOUND'; end if;
  if not exists (select 1 from public.businesses b where b.id = v_invoice.business_id and b.owner_id = auth.uid()) then
    raise exception using errcode = '42501', message = 'BUSINESS_ACCESS_DENIED';
  end if;
  if v_invoice.status = 'posted' then
    return query select v_invoice.id, v_invoice.posting_journal_id, v_invoice.status; return;
  end if;
  if v_invoice.status <> 'draft' then raise exception using errcode = '55000', message = 'INVOICE_NOT_POSTABLE'; end if;

  select status into v_period_status from public.accounting_periods
    where business_id = v_invoice.business_id
      and v_invoice.accounting_date between starts_on and ends_on
    order by starts_on desc limit 1 for update;
  if v_period_status is distinct from 'open' then
    raise exception using errcode = '55000', message = 'ACCOUNTING_PERIOD_MISSING_OR_CLOSED';
  end if;

  select account_type into v_ar_type from public.accounts
    where id = v_invoice.accounts_receivable_account_id and business_id = v_invoice.business_id and is_active;
  if v_ar_type is distinct from 'asset' then raise exception using errcode = '23514', message = 'RECEIVABLE_ACCOUNT_MUST_BE_ACTIVE_ASSET'; end if;

  select count(*), coalesce(sum(net_amount),0), coalesce(sum(tax_amount),0)
    into v_count, v_net, v_tax
    from public.sales_invoice_lines where invoice_id = v_invoice.id and business_id = v_invoice.business_id;
  if v_count = 0 then raise exception using errcode = '23514', message = 'INVOICE_REQUIRES_LINES'; end if;
  v_gross := v_net + v_tax;
  if v_net <> v_invoice.net_amount or v_tax <> v_invoice.tax_amount or v_gross <> v_invoice.gross_amount then
    raise exception using errcode = '23514', message = 'INVOICE_TOTALS_DO_NOT_MATCH_LINES';
  end if;

  if not exists (
    select 1 from public.business_accounting_profiles p
     where p.business_id = v_invoice.business_id
       and p.applicability_review_status = 'approved'
       and v_invoice.document_date >= p.profile_effective_from
       and (p.profile_effective_to is null or v_invoice.document_date <= p.profile_effective_to)
  ) then
    raise exception using errcode = '55000', message = 'BUSINESS_APPLICABILITY_PROFILE_NOT_APPROVED';
  end if;

  if not exists (
    select 1 from public.accounting_rule_registry r
     where r.rule_id = 'IN.SALES_INVOICE.POST'
       and r.review_status = 'approved' and r.release_status = 'enabled'
       and v_invoice.document_date >= r.effective_from
       and (r.effective_to is null or v_invoice.document_date <= r.effective_to)
  ) then
    raise exception using errcode = '55000', message = 'SALES_INVOICE_POSTING_RULE_NOT_INDEPENDENTLY_APPROVED';
  end if;

  if v_tax > 0 and not exists (
    select 1 from public.accounting_rule_registry r
     where r.rule_id = 'IN.GST.SALES_INVOICE.POST'
       and r.review_status = 'approved' and r.release_status = 'enabled'
       and v_invoice.document_date >= r.effective_from
       and (r.effective_to is null or v_invoice.document_date <= r.effective_to)
  ) then
    raise exception using errcode = '55000', message = 'GST_POSTING_RULE_NOT_INDEPENDENTLY_APPROVED';
  end if;

  for v_line in
    select l.*, ra.account_type as revenue_type, ra.is_active as revenue_active,
           ta.account_type as tax_type, ta.is_active as tax_active
      from public.sales_invoice_lines l
      join public.accounts ra on ra.id = l.revenue_account_id and ra.business_id = l.business_id
      left join public.accounts ta on ta.id = l.tax_account_id and ta.business_id = l.business_id
     where l.invoice_id = v_invoice.id and l.business_id = v_invoice.business_id
  loop
    if v_line.revenue_type <> 'income' or not v_line.revenue_active then
      raise exception using errcode = '23514', message = 'REVENUE_ACCOUNT_MUST_BE_ACTIVE_INCOME';
    end if;
    if v_line.tax_amount > 0 and (v_line.tax_type <> 'liability' or not v_line.tax_active) then
      raise exception using errcode = '23514', message = 'TAX_ACCOUNT_MUST_BE_ACTIVE_LIABILITY';
    end if;
  end loop;

  select je.id into v_existing from public.journal_entries je
    where je.business_id = v_invoice.business_id and je.idempotency_key = p_idempotency_key;
  if v_existing is not null then raise exception using errcode = '23505', message = 'IDEMPOTENCY_KEY_ALREADY_USED'; end if;

  insert into public.journal_entries
    (business_id, entry_date, reference, description, status, created_by, source_document_type,
     source_document_id, entry_kind, idempotency_key, policy_version)
  values
    (v_invoice.business_id, v_invoice.accounting_date, v_invoice.invoice_number,
     'Sales invoice ' || v_invoice.invoice_number, 'draft', auth.uid(), 'sales_invoice',
     v_invoice.id, 'original', p_idempotency_key, 'accounting-core-v1')
  returning id into v_journal_id;

  insert into public.journal_lines (journal_entry_id, account_id, description, debit, credit)
  values (v_journal_id, v_invoice.accounts_receivable_account_id,
          'Receivable — ' || v_invoice.invoice_number, v_gross, 0);

  for v_line in
    select * from public.sales_invoice_lines where invoice_id = v_invoice.id and business_id = v_invoice.business_id order by line_number
  loop
    if v_line.net_amount > 0 then
      insert into public.journal_lines (journal_entry_id, account_id, description, debit, credit)
      values (v_journal_id, v_line.revenue_account_id, v_line.description, 0, v_line.net_amount);
    end if;
    if v_line.tax_amount > 0 then
      insert into public.journal_lines (journal_entry_id, account_id, description, debit, credit)
      values (v_journal_id, v_line.tax_account_id, 'Tax — ' || v_invoice.invoice_number, 0, v_line.tax_amount);
    end if;
  end loop;

  update public.journal_entries set status = 'posted', posted_at = now() where id = v_journal_id;
  update public.sales_invoices set status = 'posted', posting_journal_id = v_journal_id,
    updated_at = now() where id = v_invoice.id;

  insert into public.accounting_audit_events (business_id, actor_id, event_type, entity_type, entity_id, metadata)
  values (v_invoice.business_id, auth.uid(), 'invoice.posted', 'sales_invoice', v_invoice.id,
          jsonb_build_object('journal_entry_id', v_journal_id, 'idempotency_key', p_idempotency_key));

  return query select v_invoice.id, v_journal_id, 'posted'::text;
end;
$$;
revoke all on function public.post_sales_invoice(uuid, text) from public, anon;
grant execute on function public.post_sales_invoice(uuid, text) to authenticated;

-- Deleting a draft is safe; posted documents are rejected by the table guard.
create or replace function public.delete_draft_sales_invoice(p_invoice_id uuid)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_invoice public.sales_invoices%rowtype;
begin
  if auth.uid() is null then raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED'; end if;
  select * into v_invoice from public.sales_invoices where id = p_invoice_id for update;
  if not found then return false; end if;
  if not exists (select 1 from public.businesses b where b.id = v_invoice.business_id and b.owner_id = auth.uid()) then
    raise exception using errcode = '42501', message = 'BUSINESS_ACCESS_DENIED';
  end if;
  if v_invoice.status <> 'draft' then
    raise exception using errcode = '55000', message = 'POSTED_INVOICE_REQUIRES_CORRECTION_WORKFLOW';
  end if;
  delete from public.sales_invoices where id = v_invoice.id;
  insert into public.accounting_audit_events (business_id, actor_id, event_type, entity_type, entity_id, reason, metadata)
  values (v_invoice.business_id, auth.uid(), 'invoice.draft_deleted', 'sales_invoice', v_invoice.id,
          'Unposted draft deleted', jsonb_build_object('invoice_number', v_invoice.invoice_number));
  return true;
end;
$$;
revoke all on function public.delete_draft_sales_invoice(uuid) from public, anon;
grant execute on function public.delete_draft_sales_invoice(uuid) to authenticated;

-- Posted invoice cancellation is deliberately gated. Tax-bearing or settled invoices need a
-- reviewed credit-note/allocation workflow; this function refuses to silently erase either.
create or replace function public.cancel_unpaid_untaxed_sales_invoice(
  p_invoice_id uuid, p_correction_date date, p_reason text, p_idempotency_key text
)
returns table (invoice_id uuid, reversal_journal_id uuid, document_status text)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_invoice public.sales_invoices%rowtype;
  v_original public.journal_entries%rowtype;
  v_reversal uuid;
  v_period_status text;
  v_line record;
begin
  if auth.uid() is null then raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED'; end if;
  if nullif(trim(p_reason), '') is null then raise exception using errcode = '22023', message = 'CORRECTION_REASON_REQUIRED'; end if;
  if nullif(trim(p_idempotency_key), '') is null then raise exception using errcode = '22023', message = 'IDEMPOTENCY_KEY_REQUIRED'; end if;

  select * into v_invoice from public.sales_invoices where id = p_invoice_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'INVOICE_NOT_FOUND'; end if;
  if not exists (select 1 from public.businesses b where b.id = v_invoice.business_id and b.owner_id = auth.uid()) then
    raise exception using errcode = '42501', message = 'BUSINESS_ACCESS_DENIED';
  end if;
  if v_invoice.status = 'cancelled' then
    return query select v_invoice.id, v_invoice.cancellation_journal_id, v_invoice.status; return;
  end if;
  if v_invoice.status <> 'posted' then raise exception using errcode = '55000', message = 'ONLY_POSTED_INVOICES_USE_CANCELLATION'; end if;
  if v_invoice.tax_amount <> 0 then raise exception using errcode = '55000', message = 'TAX_BEARING_INVOICE_REQUIRES_REVIEWED_CREDIT_NOTE_WORKFLOW'; end if;
  if exists (select 1 from public.invoice_receipt_allocations a where a.invoice_id = v_invoice.id) then
    raise exception using errcode = '55000', message = 'ALLOCATED_INVOICE_REQUIRES_REVIEWED_ALLOCATION_CORRECTION';
  end if;
  if not exists (
    select 1 from public.accounting_rule_registry r
    where r.rule_id = 'ACCOUNTING.SALES_INVOICE.CANCEL_UNPAID_UNTAXED'
      and r.review_status = 'approved' and r.release_status = 'enabled'
      and p_correction_date >= r.effective_from
      and (r.effective_to is null or p_correction_date <= r.effective_to)
  ) then raise exception using errcode = '55000', message = 'CANCELLATION_RULE_NOT_INDEPENDENTLY_APPROVED'; end if;

  select status into v_period_status from public.accounting_periods
    where business_id = v_invoice.business_id and p_correction_date between starts_on and ends_on
    order by starts_on desc limit 1 for update;
  if v_period_status is distinct from 'open' then raise exception using errcode = '55000', message = 'CORRECTION_PERIOD_MISSING_OR_CLOSED'; end if;

  select * into v_original from public.journal_entries
    where id = v_invoice.posting_journal_id and business_id = v_invoice.business_id and status = 'posted';
  if not found then raise exception using errcode = '23514', message = 'ORIGINAL_POSTED_JOURNAL_MISSING'; end if;

  insert into public.journal_entries
    (business_id, entry_date, reference, description, status, created_by, source_document_type,
     source_document_id, entry_kind, reversal_of, idempotency_key, policy_version)
  values
    (v_invoice.business_id, p_correction_date, v_invoice.invoice_number,
     'Reversal of sales invoice ' || v_invoice.invoice_number, 'draft', auth.uid(),
     'sales_invoice_cancellation', v_invoice.id, 'reversal', v_original.id, p_idempotency_key, 'accounting-core-v1')
  returning id into v_reversal;

  for v_line in select * from public.journal_lines where journal_entry_id = v_original.id order by id
  loop
    insert into public.journal_lines (journal_entry_id, account_id, description, debit, credit)
    values (v_reversal, v_line.account_id, 'Reversal: ' || coalesce(v_line.description, v_invoice.invoice_number),
            v_line.credit, v_line.debit);
  end loop;

  update public.journal_entries set status = 'posted', posted_at = now() where id = v_reversal;
  update public.sales_invoices set status = 'cancelled', cancellation_journal_id = v_reversal,
    cancellation_reason = trim(p_reason), cancelled_at = now(), cancelled_by = auth.uid(), updated_at = now()
    where id = v_invoice.id;

  insert into public.accounting_audit_events (business_id, actor_id, event_type, entity_type, entity_id, reason, metadata)
  values (v_invoice.business_id, auth.uid(), 'invoice.cancelled_by_reversal', 'sales_invoice', v_invoice.id,
          trim(p_reason), jsonb_build_object('original_journal_id', v_original.id, 'reversal_journal_id', v_reversal));

  return query select v_invoice.id, v_reversal, 'cancelled'::text;
end;
$$;
revoke all on function public.cancel_unpaid_untaxed_sales_invoice(uuid, date, text, text) from public, anon;
grant execute on function public.cancel_unpaid_untaxed_sales_invoice(uuid, date, text, text) to authenticated;

comment on table public.sales_invoices is 'Sales register source documents. Draft deletion is allowed; posted records are corrected through linked accounting entries.';
comment on table public.journal_entries is 'Authoritative accounting journal. Posted entries are immutable; corrections use linked reversal or adjustment entries.';
comment on table public.accounting_rule_registry is 'Effective-dated rule registry. Compliance rules remain disabled until independently reviewed and approved.';
