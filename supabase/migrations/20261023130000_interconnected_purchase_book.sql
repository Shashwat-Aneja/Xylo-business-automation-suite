-- Supplier bills and purchase-book projection.
-- This is an additive, staged accounting slice; no GST rule is enabled by this migration.

create table if not exists public.suppliers (
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

create table if not exists public.supplier_bills (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  supplier_id uuid not null,
  bill_number text not null,
  supplier_reference text,
  document_date date not null,
  due_date date,
  accounting_date date not null,
  currency_code text not null default 'INR' check (currency_code ~ '^[A-Z]{3}$'),
  accounts_payable_account_id uuid not null references public.accounts(id) on delete restrict,
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
  unique (business_id, bill_number),
  unique (business_id, id),
  unique (business_id, idempotency_key),
  foreign key (business_id, supplier_id) references public.suppliers(business_id, id) on delete restrict,
  check (gross_amount = net_amount + tax_amount),
  check (due_date is null or due_date >= document_date),
  check ((status = 'draft' and posting_journal_id is null and cancellation_journal_id is null)
      or (status = 'posted' and posting_journal_id is not null and cancellation_journal_id is null)
      or (status = 'cancelled' and posting_journal_id is not null and cancellation_journal_id is not null
          and cancellation_reason is not null and cancelled_at is not null))
);
create index if not exists supplier_bills_business_date_idx
  on public.supplier_bills (business_id, document_date desc);
create index if not exists supplier_bills_supplier_status_idx
  on public.supplier_bills (business_id, supplier_id, status);

create table if not exists public.supplier_bill_lines (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  supplier_bill_id uuid not null,
  line_number integer not null check (line_number > 0),
  description text not null,
  quantity numeric(18,4) not null default 1 check (quantity > 0),
  unit_price numeric(18,4) not null check (unit_price >= 0),
  discount_amount numeric(18,2) not null default 0 check (discount_amount >= 0),
  net_amount numeric(18,2) not null check (net_amount >= 0),
  tax_amount numeric(18,2) not null default 0 check (tax_amount >= 0),
  recoverable_tax_amount numeric(18,2) not null default 0 check (recoverable_tax_amount >= 0),
  purchase_account_id uuid not null references public.accounts(id) on delete restrict,
  tax_account_id uuid references public.accounts(id) on delete restrict,
  tax_code text,
  tax_rule_version text,
  created_at timestamptz not null default now(),
  unique (supplier_bill_id, line_number),
  foreign key (business_id, supplier_bill_id) references public.supplier_bills(business_id, id) on delete cascade,
  check (discount_amount <= round(quantity * unit_price, 2)),
  check (net_amount = round(quantity * unit_price, 2) - discount_amount),
  check (recoverable_tax_amount <= tax_amount),
  check ((recoverable_tax_amount = 0) or tax_account_id is not null),
  check ((tax_amount = 0) or tax_code is not null)
);
create index if not exists supplier_bill_lines_bill_idx
  on public.supplier_bill_lines (business_id, supplier_bill_id);

alter table public.suppliers enable row level security;
alter table public.supplier_bills enable row level security;
alter table public.supplier_bill_lines enable row level security;

create policy "Owners manage suppliers" on public.suppliers for all to authenticated
using (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())))
with check (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())));
create policy "Owners read supplier bills" on public.supplier_bills for select to authenticated
using (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())));
create policy "Owners create draft supplier bills" on public.supplier_bills for insert to authenticated
with check (status = 'draft' and exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())));
create policy "Owners update own supplier bills" on public.supplier_bills for update to authenticated
using (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())))
with check (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())));
create policy "Owners delete draft supplier bills" on public.supplier_bills for delete to authenticated
using (status = 'draft' and exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())));
create policy "Owners manage supplier bill lines" on public.supplier_bill_lines for all to authenticated
using (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())))
with check (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())));
grant select, insert, update, delete on public.suppliers to authenticated;
grant select, insert, update, delete on public.supplier_bills, public.supplier_bill_lines to authenticated;

create or replace function private.guard_supplier_bill()
returns trigger language plpgsql set search_path = ''
as $$
declare v_journal_status text;
begin
  if tg_op = 'DELETE' then
    if old.status <> 'draft' then
      raise exception using errcode = '55000', message = 'POSTED_SUPPLIER_BILL_CANNOT_BE_DELETED';
    end if;
    insert into public.accounting_audit_events (business_id, actor_id, event_type, entity_type, entity_id, reason, metadata)
    values (old.business_id, auth.uid(), 'supplier_bill.draft_deleted', 'supplier_bill', old.id,
      'Unposted draft deleted', jsonb_build_object('bill_number', old.bill_number));
    return old;
  end if;
  if old.status <> 'draft' then
    if old.status = 'posted' and new.status = 'cancelled'
       and (to_jsonb(new) - array['status','cancellation_journal_id','cancellation_reason','cancelled_at','cancelled_by','updated_at'])
         = (to_jsonb(old) - array['status','cancellation_journal_id','cancellation_reason','cancelled_at','cancelled_by','updated_at'])
       and new.cancellation_journal_id is not null and nullif(trim(new.cancellation_reason),'') is not null then
      select status into v_journal_status from public.journal_entries
       where id = new.cancellation_journal_id and business_id = old.business_id
         and source_document_type = 'supplier_bill_cancellation' and source_document_id = old.id and entry_kind = 'reversal';
      if v_journal_status = 'posted'
         and current_setting('xylo.posting_source_type', true) is not distinct from 'supplier_bill_cancellation'
         and current_setting('xylo.posting_source_id', true) is not distinct from new.id::text then return new; end if;
    end if;
    raise exception using errcode = '55000', message = 'POSTED_SUPPLIER_BILL_IMMUTABLE';
  end if;
  if new.status = 'posted' then
    select status into v_journal_status from public.journal_entries
     where id = new.posting_journal_id and business_id = new.business_id
       and source_document_type = 'supplier_bill' and source_document_id = new.id and entry_kind = 'original';
    if v_journal_status <> 'posted'
       or current_setting('xylo.posting_source_type', true) is distinct from 'supplier_bill'
       or current_setting('xylo.posting_source_id', true) is distinct from new.id::text then
      raise exception using errcode = '23514', message = 'SUPPLIER_BILL_REQUIRES_CONTROLLED_POSTED_JOURNAL';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.guard_supplier_bill() from public, anon, authenticated;
drop trigger if exists supplier_bill_state_guard on public.supplier_bills;
create trigger supplier_bill_state_guard before update or delete on public.supplier_bills
for each row execute function private.guard_supplier_bill();

create or replace function private.guard_supplier_bill_line()
returns trigger language plpgsql set search_path = ''
as $$
declare v_status text;
begin
  if tg_op = 'INSERT' then
    select status into v_status from public.supplier_bills where id = new.supplier_bill_id and business_id = new.business_id;
  elsif tg_op = 'DELETE' then
    select status into v_status from public.supplier_bills where id = old.supplier_bill_id and business_id = old.business_id;
  else
    select status into v_status from public.supplier_bills where id = old.supplier_bill_id and business_id = old.business_id;
    if v_status is distinct from 'draft' then
      raise exception using errcode = '55000', message = 'POSTED_SUPPLIER_BILL_LINES_IMMUTABLE';
    end if;
    select status into v_status from public.supplier_bills where id = new.supplier_bill_id and business_id = new.business_id;
  end if;
  if v_status is distinct from 'draft' then
    raise exception using errcode = '55000', message = 'POSTED_SUPPLIER_BILL_LINES_IMMUTABLE';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function private.guard_supplier_bill_line() from public, anon, authenticated;
drop trigger if exists supplier_bill_lines_state_guard on public.supplier_bill_lines;
create trigger supplier_bill_lines_state_guard before insert or update or delete on public.supplier_bill_lines
for each row execute function private.guard_supplier_bill_line();

create or replace function public.post_supplier_bill(p_bill_id uuid, p_idempotency_key text)
returns table (supplier_bill_id uuid, journal_entry_id uuid, document_status text)
language plpgsql security invoker set search_path = ''
as $$
declare
  v_bill public.supplier_bills%rowtype;
  v_line record;
  v_journal_id uuid;
  v_count integer;
  v_net numeric(18,2);
  v_tax numeric(18,2);
  v_gross numeric(18,2);
  v_period_status text;
  v_ap_type text;
  v_purchase_type text;
  v_tax_type text;
begin
  if auth.uid() is null then raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED'; end if;
  if nullif(trim(p_idempotency_key),'') is null then raise exception using errcode = '22023', message = 'IDEMPOTENCY_KEY_REQUIRED'; end if;
  select * into v_bill from public.supplier_bills where id = p_bill_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'SUPPLIER_BILL_NOT_FOUND'; end if;
  if not exists (select 1 from public.businesses b where b.id = v_bill.business_id and b.owner_id = auth.uid()) then
    raise exception using errcode = '42501', message = 'BUSINESS_ACCESS_DENIED';
  end if;
  if v_bill.status = 'posted' then return query select v_bill.id, v_bill.posting_journal_id, v_bill.status; return; end if;
  if v_bill.status <> 'draft' then raise exception using errcode = '55000', message = 'SUPPLIER_BILL_NOT_POSTABLE'; end if;

  select status into v_period_status from public.accounting_periods
   where business_id = v_bill.business_id and v_bill.accounting_date between starts_on and ends_on
   order by starts_on desc limit 1 for update;
  if v_period_status is distinct from 'open' then raise exception using errcode = '55000', message = 'ACCOUNTING_PERIOD_MISSING_OR_CLOSED'; end if;
  if not exists (select 1 from public.business_accounting_profiles p where p.business_id = v_bill.business_id
    and p.applicability_review_status = 'approved' and v_bill.document_date >= p.profile_effective_from
    and (p.profile_effective_to is null or v_bill.document_date <= p.profile_effective_to)) then
    raise exception using errcode = '55000', message = 'BUSINESS_APPLICABILITY_PROFILE_NOT_APPROVED';
  end if;
  if not exists (select 1 from public.accounting_rule_registry r where r.rule_id = 'IN.PURCHASE_BILL.POST'
    and r.review_status = 'approved' and r.release_status = 'enabled' and v_bill.document_date >= r.effective_from
    and (r.effective_to is null or v_bill.document_date <= r.effective_to)) then
    raise exception using errcode = '55000', message = 'PURCHASE_BILL_POSTING_RULE_NOT_INDEPENDENTLY_APPROVED';
  end if;

  select account_type into v_ap_type from public.accounts where id = v_bill.accounts_payable_account_id
    and business_id = v_bill.business_id and is_active;
  if v_ap_type is distinct from 'liability' then raise exception using errcode = '23514', message = 'PAYABLE_ACCOUNT_MUST_BE_ACTIVE_LIABILITY'; end if;

  select count(*), coalesce(sum(net_amount),0), coalesce(sum(tax_amount),0)
   into v_count, v_net, v_tax from public.supplier_bill_lines where supplier_bill_id = v_bill.id and business_id = v_bill.business_id;
  if v_count = 0 then raise exception using errcode = '23514', message = 'SUPPLIER_BILL_REQUIRES_LINES'; end if;
  v_gross := v_net + v_tax;
  if v_gross <= 0 then raise exception using errcode = '23514', message = 'ZERO_TOTAL_SUPPLIER_BILL_CANNOT_BE_POSTED'; end if;
  if v_net <> v_bill.net_amount or v_tax <> v_bill.tax_amount or v_gross <> v_bill.gross_amount then
    raise exception using errcode = '23514', message = 'SUPPLIER_BILL_TOTALS_DO_NOT_MATCH_LINES';
  end if;
  if v_tax > 0 and not exists (select 1 from public.accounting_rule_registry r where r.rule_id = 'IN.GST.PURCHASE_BILL.POST'
    and r.review_status = 'approved' and r.release_status = 'enabled' and v_bill.document_date >= r.effective_from
    and (r.effective_to is null or v_bill.document_date <= r.effective_to)) then
    raise exception using errcode = '55000', message = 'GST_PURCHASE_POSTING_RULE_NOT_INDEPENDENTLY_APPROVED';
  end if;

  for v_line in
    select l.*, a.account_type as purchase_type, a.is_active as purchase_active,
           t.account_type as tax_type, t.is_active as tax_active
      from public.supplier_bill_lines l
      join public.accounts a on a.id = l.purchase_account_id and a.business_id = l.business_id
      left join public.accounts t on t.id = l.tax_account_id and t.business_id = l.business_id
     where l.supplier_bill_id = v_bill.id and l.business_id = v_bill.business_id
  loop
    if v_line.purchase_type not in ('expense','asset') or not v_line.purchase_active then
      raise exception using errcode = '23514', message = 'PURCHASE_ACCOUNT_MUST_BE_ACTIVE_EXPENSE_OR_ASSET';
    end if;
    if v_line.recoverable_tax_amount > 0 and (v_line.tax_type is distinct from 'asset' or not v_line.tax_active) then
      raise exception using errcode = '23514', message = 'RECOVERABLE_TAX_ACCOUNT_MUST_BE_ACTIVE_ASSET';
    end if;
  end loop;

  if exists (select 1 from public.journal_entries where business_id = v_bill.business_id and idempotency_key = p_idempotency_key) then
    raise exception using errcode = '23505', message = 'IDEMPOTENCY_KEY_ALREADY_USED';
  end if;
  insert into public.journal_entries
    (business_id, entry_date, reference, description, status, created_by, source_document_type,
     source_document_id, entry_kind, idempotency_key, policy_version)
  values (v_bill.business_id, v_bill.accounting_date, v_bill.bill_number,
    'Supplier bill ' || v_bill.bill_number, 'draft', auth.uid(), 'supplier_bill', v_bill.id,
    'original', p_idempotency_key, 'accounting-core-v1')
  returning id into v_journal_id;

  for v_line in select * from public.supplier_bill_lines where supplier_bill_id = v_bill.id and business_id = v_bill.business_id order by line_number
  loop
    if v_line.net_amount + (v_line.tax_amount - v_line.recoverable_tax_amount) > 0 then
      insert into public.journal_lines (journal_entry_id, account_id, description, debit, credit)
      values (v_journal_id, v_line.purchase_account_id, v_line.description,
        v_line.net_amount + (v_line.tax_amount - v_line.recoverable_tax_amount), 0);
    end if;
    if v_line.recoverable_tax_amount > 0 then
      insert into public.journal_lines (journal_entry_id, account_id, description, debit, credit)
      values (v_journal_id, v_line.tax_account_id, 'Recoverable tax — ' || v_bill.bill_number,
        v_line.recoverable_tax_amount, 0);
    end if;
  end loop;
  insert into public.journal_lines (journal_entry_id, account_id, description, debit, credit)
    values (v_journal_id, v_bill.accounts_payable_account_id, 'Payable — ' || v_bill.bill_number, 0, v_gross);

  perform set_config('xylo.posting_source_type', 'supplier_bill', true);
  perform set_config('xylo.posting_source_id', v_bill.id::text, true);
  update public.journal_entries set status = 'posted', posted_at = now() where id = v_journal_id;
  update public.supplier_bills set status = 'posted', posting_journal_id = v_journal_id, updated_at = now() where id = v_bill.id;
  insert into public.accounting_audit_events (business_id, actor_id, event_type, entity_type, entity_id, metadata)
   values (v_bill.business_id, auth.uid(), 'supplier_bill.posted', 'supplier_bill', v_bill.id,
     jsonb_build_object('journal_entry_id', v_journal_id, 'idempotency_key', p_idempotency_key));
  return query select v_bill.id, v_journal_id, 'posted'::text;
end;
$$;
revoke all on function public.post_supplier_bill(uuid, text) from public, anon;
grant execute on function public.post_supplier_bill(uuid, text) to authenticated;

create or replace view public.purchase_book
with (security_invoker = true)
as
select b.business_id, b.id as supplier_bill_id, b.bill_number, b.supplier_reference,
  b.document_date, b.due_date, b.currency_code, b.status as document_status,
  b.compliance_status, s.id as supplier_id, s.display_name as supplier_name,
  b.net_amount, b.tax_amount, b.gross_amount, b.posting_journal_id, b.cancellation_journal_id, b.created_at
from public.supplier_bills b
join public.suppliers s on s.id = b.supplier_id and s.business_id = b.business_id;
grant select on public.purchase_book to authenticated;
comment on view public.purchase_book is 'Purchase register projection; every posted bill links to its authoritative journal entry.';
