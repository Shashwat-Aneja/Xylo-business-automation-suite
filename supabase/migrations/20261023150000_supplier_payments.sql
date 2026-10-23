-- Supplier payment lifecycle: posted payments reduce accounts payable and cash/bank.
-- Allocations are a subledger assignment and never recognize expense/revenue again.
-- Source-only migration: apply to a disposable local/dev database after prior accounting migrations.

create table if not exists public.supplier_payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  supplier_id uuid not null,
  payment_number text not null,
  payment_date date not null,
  currency_code text not null default 'INR' check (currency_code ~ '^[A-Z]{3}$'),
  amount numeric(18,2) not null check (amount > 0),
  accounts_payable_account_id uuid not null references public.accounts(id) on delete restrict,
  cash_bank_account_id uuid not null references public.accounts(id) on delete restrict,
  status text not null default 'draft' check (status in ('draft','posted','void')),
  journal_entry_id uuid references public.journal_entries(id) on delete restrict,
  idempotency_key text,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, payment_number),
  unique (business_id, id),
  unique (business_id, idempotency_key),
  foreign key (business_id, supplier_id) references public.suppliers(business_id, id) on delete restrict,
  check ((status = 'draft' and journal_entry_id is null) or (status <> 'draft' and journal_entry_id is not null))
);
create index if not exists supplier_payments_business_date_idx
  on public.supplier_payments (business_id, payment_date desc);
create index if not exists supplier_payments_supplier_idx
  on public.supplier_payments (business_id, supplier_id, status);

create table if not exists public.supplier_payment_allocations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  payment_id uuid not null,
  supplier_bill_id uuid not null,
  amount numeric(18,2) not null check (amount > 0),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique (payment_id, supplier_bill_id),
  foreign key (business_id, payment_id) references public.supplier_payments(business_id, id) on delete restrict,
  foreign key (business_id, supplier_bill_id) references public.supplier_bills(business_id, id) on delete restrict
);
create index if not exists supplier_payment_allocations_bill_idx
  on public.supplier_payment_allocations (business_id, supplier_bill_id);

alter table public.supplier_payments enable row level security;
alter table public.supplier_payment_allocations enable row level security;
create policy "Owners manage supplier payments" on public.supplier_payments for all to authenticated
using (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())))
with check (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())));
create policy "Owners read supplier payment allocations" on public.supplier_payment_allocations for select to authenticated
using (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())));
create policy "Owners allocate supplier payments" on public.supplier_payment_allocations for insert to authenticated
with check (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = (select auth.uid())));
grant select, insert, update, delete on public.supplier_payments to authenticated;
grant select, insert on public.supplier_payment_allocations to authenticated;

create or replace function private.guard_supplier_payment()
returns trigger language plpgsql set search_path = ''
as $$
declare v_journal_status text; v_source_type text; v_source_id uuid;
begin
  if tg_op = 'DELETE' then
    if old.status <> 'draft' then raise exception using errcode = '55000', message = 'POSTED_SUPPLIER_PAYMENT_CANNOT_BE_DELETED'; end if;
    return old;
  end if;
  if old.status <> 'draft' then
    raise exception using errcode = '55000', message = 'POSTED_SUPPLIER_PAYMENT_IMMUTABLE; use a correction workflow';
  end if;
  if new.status = 'posted' then
    select status, source_document_type, source_document_id into v_journal_status, v_source_type, v_source_id
    from public.journal_entries where id = new.journal_entry_id and business_id = new.business_id;
    if v_journal_status is distinct from 'posted' or v_source_type is distinct from 'supplier_payment'
       or v_source_id is distinct from new.id
       or current_setting('xylo.posting_source_type', true) is distinct from 'supplier_payment'
       or current_setting('xylo.posting_source_id', true) is distinct from new.id::text then
      raise exception using errcode = '23514', message = 'SUPPLIER_PAYMENT_REQUIRES_CONTROLLED_POSTED_JOURNAL';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.guard_supplier_payment() from public, anon, authenticated;
drop trigger if exists supplier_payment_state_guard on public.supplier_payments;
create trigger supplier_payment_state_guard before update or delete on public.supplier_payments
for each row execute function private.guard_supplier_payment();

create or replace function private.guard_supplier_payment_allocation()
returns trigger language plpgsql set search_path = ''
as $$
declare
  v_payment public.supplier_payments%rowtype;
  v_bill public.supplier_bills%rowtype;
  v_payment_allocated numeric(18,2);
  v_bill_allocated numeric(18,2);
begin
  if tg_op <> 'INSERT' then
    raise exception using errcode = '55000', message = 'SUPPLIER_PAYMENT_ALLOCATIONS_IMMUTABLE';
  end if;
  select * into v_payment from public.supplier_payments
    where id = new.payment_id and business_id = new.business_id for update;
  select * into v_bill from public.supplier_bills
    where id = new.supplier_bill_id and business_id = new.business_id for update;
  if v_payment.status is distinct from 'posted' then
    raise exception using errcode = '55000', message = 'PAYMENT_MUST_BE_POSTED_BEFORE_ALLOCATION';
  end if;
  if v_bill.status is distinct from 'posted' or v_payment.supplier_id <> v_bill.supplier_id
     or v_payment.currency_code <> v_bill.currency_code then
    raise exception using errcode = '23514', message = 'PAYMENT_AND_BILL_SUPPLIER_CURRENCY_OR_STATUS_MISMATCH';
  end if;
  select coalesce(sum(amount),0) into v_payment_allocated
    from public.supplier_payment_allocations where payment_id = new.payment_id;
  select coalesce(sum(amount),0) into v_bill_allocated
    from public.supplier_payment_allocations where supplier_bill_id = new.supplier_bill_id;
  if v_payment_allocated + new.amount > v_payment.amount then
    raise exception using errcode = '23514', message = 'PAYMENT_ALLOCATION_EXCEEDS_PAYMENT_AMOUNT';
  end if;
  if v_bill_allocated + new.amount > v_bill.gross_amount then
    raise exception using errcode = '23514', message = 'PAYMENT_ALLOCATION_EXCEEDS_BILL_AMOUNT';
  end if;
  return new;
end;
$$;
revoke all on function private.guard_supplier_payment_allocation() from public, anon, authenticated;
drop trigger if exists supplier_payment_allocation_guard on public.supplier_payment_allocations;
create trigger supplier_payment_allocation_guard before insert or update or delete on public.supplier_payment_allocations
for each row execute function private.guard_supplier_payment_allocation();

create or replace function public.post_supplier_payment(p_payment_id uuid, p_idempotency_key text)
returns table (supplier_payment_id uuid, journal_entry_id uuid, document_status text)
language plpgsql security invoker set search_path = ''
as $$
declare
  v_payment public.supplier_payments%rowtype;
  v_period_status text;
  v_ap_type text;
  v_cash_type text;
  v_journal_id uuid;
begin
  if auth.uid() is null then raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED'; end if;
  if nullif(trim(p_idempotency_key), '') is null then raise exception using errcode = '22023', message = 'IDEMPOTENCY_KEY_REQUIRED'; end if;
  select * into v_payment from public.supplier_payments where id = p_payment_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'SUPPLIER_PAYMENT_NOT_FOUND'; end if;
  if not exists (select 1 from public.businesses b where b.id = v_payment.business_id and b.owner_id = auth.uid()) then
    raise exception using errcode = '42501', message = 'BUSINESS_ACCESS_DENIED';
  end if;
  if v_payment.status = 'posted' then return query select v_payment.id, v_payment.journal_entry_id, v_payment.status; return; end if;
  if v_payment.status <> 'draft' then raise exception using errcode = '55000', message = 'SUPPLIER_PAYMENT_NOT_POSTABLE'; end if;
  select status into v_period_status from public.accounting_periods
    where business_id = v_payment.business_id and v_payment.payment_date between starts_on and ends_on
    order by starts_on desc limit 1 for update;
  if v_period_status is distinct from 'open' then raise exception using errcode = '55000', message = 'ACCOUNTING_PERIOD_MISSING_OR_CLOSED'; end if;
  select account_type into v_ap_type from public.accounts
    where id = v_payment.accounts_payable_account_id and business_id = v_payment.business_id and is_active;
  select account_type into v_cash_type from public.accounts
    where id = v_payment.cash_bank_account_id and business_id = v_payment.business_id and is_active;
  if v_ap_type is distinct from 'liability' then raise exception using errcode = '23514', message = 'PAYABLE_ACCOUNT_MUST_BE_ACTIVE_LIABILITY'; end if;
  if v_cash_type is distinct from 'asset' then raise exception using errcode = '23514', message = 'CASH_BANK_ACCOUNT_MUST_BE_ACTIVE_ASSET'; end if;
  if exists (select 1 from public.journal_entries where business_id = v_payment.business_id and idempotency_key = p_idempotency_key) then
    raise exception using errcode = '23505', message = 'IDEMPOTENCY_KEY_ALREADY_USED';
  end if;
  insert into public.journal_entries
    (business_id, entry_date, reference, description, status, created_by, source_document_type,
     source_document_id, entry_kind, idempotency_key, policy_version)
  values (v_payment.business_id, v_payment.payment_date, v_payment.payment_number,
    'Supplier payment ' || v_payment.payment_number, 'draft', auth.uid(), 'supplier_payment',
    v_payment.id, 'original', p_idempotency_key, 'accounting-core-v1')
  returning id into v_journal_id;
  insert into public.journal_lines (journal_entry_id, account_id, description, debit, credit)
  values (v_journal_id, v_payment.accounts_payable_account_id, 'Supplier payable cleared — ' || v_payment.payment_number, v_payment.amount, 0),
         (v_journal_id, v_payment.cash_bank_account_id, 'Cash/bank paid — ' || v_payment.payment_number, 0, v_payment.amount);
  perform set_config('xylo.posting_source_type', 'supplier_payment', true);
  perform set_config('xylo.posting_source_id', v_payment.id::text, true);
  update public.journal_entries set status = 'posted', posted_at = now() where id = v_journal_id;
  update public.supplier_payments set status = 'posted', journal_entry_id = v_journal_id, idempotency_key = p_idempotency_key, updated_at = now()
    where id = v_payment.id;
  insert into public.accounting_audit_events (business_id, actor_id, event_type, entity_type, entity_id, metadata)
  values (v_payment.business_id, auth.uid(), 'supplier_payment.posted', 'supplier_payment', v_payment.id,
    jsonb_build_object('journal_entry_id', v_journal_id, 'idempotency_key', p_idempotency_key));
  return query select v_payment.id, v_journal_id, 'posted'::text;
end;
$$;
revoke all on function public.post_supplier_payment(uuid, text) from public, anon;
grant execute on function public.post_supplier_payment(uuid, text) to authenticated;

create or replace view public.supplier_payment_register
with (security_invoker = true)
as
select p.business_id, p.id as supplier_payment_id, p.payment_number, p.payment_date,
  p.currency_code, p.amount, p.status as payment_status, s.id as supplier_id,
  s.display_name as supplier_name, p.journal_entry_id,
  coalesce(a.allocated_amount, 0::numeric) as allocated_amount,
  p.amount - coalesce(a.allocated_amount, 0::numeric) as unallocated_amount
from public.supplier_payments p
join public.suppliers s on s.id = p.supplier_id and s.business_id = p.business_id
left join (
  select business_id, payment_id, sum(amount) as allocated_amount
  from public.supplier_payment_allocations group by business_id, payment_id
) a on a.business_id = p.business_id and a.payment_id = p.id;
grant select on public.supplier_payment_register to authenticated;
comment on table public.supplier_payments is 'Supplier cash/bank disbursements; posted payments reduce payable and cash/bank through a linked journal.';
comment on table public.supplier_payment_allocations is 'Immutable allocation of posted supplier payments to posted supplier bills.';
