-- Receipt posting and allocation. Receipts first record the cash movement against customer advances;
-- an allocation then reclassifies the advance against the selected receivable without recognising revenue twice.

alter table public.cash_receipts
  add column if not exists customer_advance_account_id uuid references public.accounts(id) on delete restrict;

alter table public.invoice_receipt_allocations
  add column if not exists journal_entry_id uuid references public.journal_entries(id) on delete restrict,
  add column if not exists created_by uuid not null default auth.uid() references auth.users(id),
  add column if not exists idempotency_key text;

alter table public.invoice_receipt_allocations
  drop constraint if exists invoice_receipt_allocations_invoice_id_receipt_id_key;
create unique index if not exists invoice_receipt_allocations_business_idempotency_idx
  on public.invoice_receipt_allocations (business_id, idempotency_key) where idempotency_key is not null;
create index if not exists invoice_receipt_allocations_receipt_idx
  on public.invoice_receipt_allocations (business_id, receipt_id);

create or replace function private.guard_cash_receipt()
returns trigger language plpgsql set search_path = ''
as $$
declare v_status text; v_source_type text; v_source_id uuid;
begin
  if tg_op = 'DELETE' then
    if old.status <> 'draft' then raise exception using errcode = '55000', message = 'POSTED_RECEIPT_CANNOT_BE_DELETED'; end if;
    return old;
  end if;
  if old.status <> 'draft' then
    raise exception using errcode = '55000', message = 'POSTED_RECEIPT_IMMUTABLE; use a permitted correction workflow';
  end if;
  if new.status = 'posted' then
    select status, source_document_type, source_document_id into v_status, v_source_type, v_source_id
      from public.journal_entries where id = new.journal_entry_id and business_id = new.business_id;
    if v_status is distinct from 'posted' or v_source_type is distinct from 'cash_receipt'
       or v_source_id is distinct from new.id then
      raise exception using errcode = '23514', message = 'RECEIPT_REQUIRES_LINKED_POSTED_JOURNAL';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.guard_cash_receipt() from public, anon, authenticated;
drop trigger if exists cash_receipt_state_guard on public.cash_receipts;
create trigger cash_receipt_state_guard before update or delete on public.cash_receipts
for each row execute function private.guard_cash_receipt();

create or replace function private.guard_receipt_allocation()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if tg_op <> 'INSERT' then
    raise exception using errcode = '55000', message = 'POSTED_RECEIPT_ALLOCATIONS_ARE_IMMUTABLE; create a correcting allocation entry';
  end if;
  if new.journal_entry_id is null or new.idempotency_key is null then
    raise exception using errcode = '23514', message = 'ALLOCATION_REQUIRES_JOURNAL_AND_IDEMPOTENCY_KEY';
  end if;
  if not exists (
    select 1 from public.journal_entries je
     where je.id = new.journal_entry_id and je.business_id = new.business_id
       and je.source_document_type = 'receipt_allocation'
       and je.source_document_id = new.id and je.entry_kind = 'adjustment'
  ) then
    raise exception using errcode = '23514', message = 'ALLOCATION_REQUIRES_LINKED_JOURNAL';
  end if;
  return new;
end;
$$;
revoke all on function private.guard_receipt_allocation() from public, anon, authenticated;
drop trigger if exists receipt_allocation_state_guard on public.invoice_receipt_allocations;
create trigger receipt_allocation_state_guard
before insert or update or delete on public.invoice_receipt_allocations
for each row execute function private.guard_receipt_allocation();

create or replace function private.validate_receipt_allocation_at_commit()
returns trigger language plpgsql set search_path = ''
as $$
declare
  v_invoice public.sales_invoices%rowtype;
  v_receipt public.cash_receipts%rowtype;
  v_journal public.journal_entries%rowtype;
  v_allocated_invoice numeric(18,2);
  v_allocated_receipt numeric(18,2);
  v_debit numeric(18,2);
  v_credit numeric(18,2);
  v_debit_account uuid;
  v_credit_account uuid;
begin
  select * into v_invoice from public.sales_invoices where id = new.invoice_id and business_id = new.business_id for update;
  select * into v_receipt from public.cash_receipts where id = new.receipt_id and business_id = new.business_id for update;
  select * into v_journal from public.journal_entries where id = new.journal_entry_id and business_id = new.business_id;
  if v_invoice.id is null or v_receipt.id is null or v_journal.id is null then
    raise exception using errcode = '23503', message = 'ALLOCATION_REFERENCE_MISSING';
  end if;
  if v_invoice.status <> 'posted' or v_receipt.status <> 'posted' or v_invoice.customer_id <> v_receipt.customer_id then
    raise exception using errcode = '23514', message = 'ALLOCATION_REQUIRES_POSTED_DOCUMENTS_FOR_SAME_CUSTOMER';
  end if;
  if v_journal.status <> 'posted' or v_journal.source_document_type <> 'receipt_allocation'
     or v_journal.source_document_id <> new.id or v_journal.entry_kind <> 'adjustment' then
    raise exception using errcode = '23514', message = 'ALLOCATION_JOURNAL_NOT_POSTED_OR_NOT_LINKED';
  end if;
  if v_invoice.currency_code <> v_receipt.currency_code then
    raise exception using errcode = '23514', message = 'CROSS_CURRENCY_ALLOCATION_REQUIRES_FX_WORKFLOW';
  end if;

  select coalesce(sum(amount),0) into v_allocated_invoice
    from public.invoice_receipt_allocations a
    join public.journal_entries je on je.id = a.journal_entry_id and je.status = 'posted'
    where a.invoice_id = new.invoice_id and a.business_id = new.business_id;
  select coalesce(sum(amount),0) into v_allocated_receipt
    from public.invoice_receipt_allocations a
    join public.journal_entries je on je.id = a.journal_entry_id and je.status = 'posted'
    where a.receipt_id = new.receipt_id and a.business_id = new.business_id;
  if v_allocated_invoice > v_invoice.gross_amount or v_allocated_receipt > v_receipt.amount then
    raise exception using errcode = '23514', message = 'ALLOCATION_EXCEEDS_INVOICE_OR_RECEIPT_BALANCE';
  end if;

  select coalesce(sum(debit),0), coalesce(sum(credit),0),
         max(account_id) filter (where debit > 0), max(account_id) filter (where credit > 0)
    into v_debit, v_credit, v_debit_account, v_credit_account
    from public.journal_lines where journal_entry_id = new.journal_entry_id;
  if v_debit <> new.amount or v_credit <> new.amount
     or v_debit_account is distinct from v_receipt.customer_advance_account_id
     or v_credit_account is distinct from v_invoice.accounts_receivable_account_id then
    raise exception using errcode = '23514', message = 'ALLOCATION_JOURNAL_MUST_RECLASSIFY_ADVANCE_TO_RECEIVABLE';
  end if;
  return new;
end;
$$;
revoke all on function private.validate_receipt_allocation_at_commit() from public, anon, authenticated;
drop trigger if exists receipt_allocation_commit_check on public.invoice_receipt_allocations;
create constraint trigger receipt_allocation_commit_check
after insert on public.invoice_receipt_allocations
deferrable initially deferred
for each row execute function private.validate_receipt_allocation_at_commit();

create or replace function public.post_cash_receipt(p_receipt_id uuid, p_idempotency_key text)
returns table (receipt_id uuid, journal_entry_id uuid, document_status text)
language plpgsql security invoker set search_path = ''
as $$
declare
  v_receipt public.cash_receipts%rowtype;
  v_period_status text;
  v_bank_type text;
  v_advance_type text;
  v_journal_id uuid;
begin
  if auth.uid() is null then raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED'; end if;
  if nullif(trim(p_idempotency_key),'') is null then raise exception using errcode = '22023', message = 'IDEMPOTENCY_KEY_REQUIRED'; end if;
  select * into v_receipt from public.cash_receipts where id = p_receipt_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'RECEIPT_NOT_FOUND'; end if;
  if not exists (select 1 from public.businesses b where b.id = v_receipt.business_id and b.owner_id = auth.uid()) then
    raise exception using errcode = '42501', message = 'BUSINESS_ACCESS_DENIED';
  end if;
  if v_receipt.status = 'posted' then return query select v_receipt.id, v_receipt.journal_entry_id, v_receipt.status; return; end if;
  if v_receipt.status <> 'draft' then raise exception using errcode = '55000', message = 'RECEIPT_NOT_POSTABLE'; end if;
  if v_receipt.customer_advance_account_id is null then
    raise exception using errcode = '23514', message = 'CUSTOMER_ADVANCE_ACCOUNT_REQUIRED';
  end if;
  select status into v_period_status from public.accounting_periods
    where business_id = v_receipt.business_id and v_receipt.receipt_date between starts_on and ends_on
    order by starts_on desc limit 1 for update;
  if v_period_status is distinct from 'open' then raise exception using errcode = '55000', message = 'ACCOUNTING_PERIOD_MISSING_OR_CLOSED'; end if;
  select account_type into v_bank_type from public.accounts where id = v_receipt.cash_bank_account_id
    and business_id = v_receipt.business_id and is_active;
  select account_type into v_advance_type from public.accounts where id = v_receipt.customer_advance_account_id
    and business_id = v_receipt.business_id and is_active;
  if v_bank_type is distinct from 'asset' then raise exception using errcode = '23514', message = 'CASH_BANK_ACCOUNT_MUST_BE_ACTIVE_ASSET'; end if;
  if v_advance_type is distinct from 'liability' then raise exception using errcode = '23514', message = 'CUSTOMER_ADVANCE_ACCOUNT_MUST_BE_ACTIVE_LIABILITY'; end if;
  if exists (select 1 from public.journal_entries where business_id = v_receipt.business_id and idempotency_key = p_idempotency_key) then
    raise exception using errcode = '23505', message = 'IDEMPOTENCY_KEY_ALREADY_USED';
  end if;
  insert into public.journal_entries
    (business_id, entry_date, reference, description, status, created_by, source_document_type,
     source_document_id, entry_kind, idempotency_key, policy_version)
  values (v_receipt.business_id, v_receipt.receipt_date, v_receipt.receipt_number,
    'Customer receipt ' || v_receipt.receipt_number, 'draft', auth.uid(), 'cash_receipt',
    v_receipt.id, 'original', p_idempotency_key, 'accounting-core-v1')
  returning id into v_journal_id;
  insert into public.journal_lines (journal_entry_id, account_id, description, debit, credit)
    values (v_journal_id, v_receipt.cash_bank_account_id, 'Receipt received — ' || v_receipt.receipt_number, v_receipt.amount, 0);
  insert into public.journal_lines (journal_entry_id, account_id, description, debit, credit)
    values (v_journal_id, v_receipt.customer_advance_account_id, 'Customer advance — ' || v_receipt.receipt_number, 0, v_receipt.amount);
  update public.journal_entries set status = 'posted', posted_at = now() where id = v_journal_id;
  update public.cash_receipts set status = 'posted', journal_entry_id = v_journal_id where id = v_receipt.id;
  insert into public.accounting_audit_events (business_id, actor_id, event_type, entity_type, entity_id, metadata)
    values (v_receipt.business_id, auth.uid(), 'cash_receipt.posted', 'cash_receipt', v_receipt.id,
      jsonb_build_object('journal_entry_id', v_journal_id, 'idempotency_key', p_idempotency_key));
  return query select v_receipt.id, v_journal_id, 'posted'::text;
end;
$$;
revoke all on function public.post_cash_receipt(uuid, text) from public, anon;
grant execute on function public.post_cash_receipt(uuid, text) to authenticated;

create or replace function public.allocate_receipt_to_invoice(
  p_receipt_id uuid, p_invoice_id uuid, p_amount numeric, p_accounting_date date, p_idempotency_key text
)
returns table (allocation_id uuid, journal_entry_id uuid, allocated_amount numeric, invoice_outstanding numeric)
language plpgsql security invoker set search_path = ''
as $$
declare
  v_receipt public.cash_receipts%rowtype;
  v_invoice public.sales_invoices%rowtype;
  v_period_status text;
  v_allocated_invoice numeric(18,2);
  v_allocated_receipt numeric(18,2);
  v_allocation_id uuid := gen_random_uuid();
  v_journal_id uuid;
begin
  if auth.uid() is null then raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED'; end if;
  if p_amount is null or p_amount <= 0 or round(p_amount,2) <> p_amount then
    raise exception using errcode = '22023', message = 'ALLOCATION_AMOUNT_MUST_BE_POSITIVE_CURRENCY_AMOUNT';
  end if;
  if nullif(trim(p_idempotency_key),'') is null then raise exception using errcode = '22023', message = 'IDEMPOTENCY_KEY_REQUIRED'; end if;

  select * into v_invoice from public.sales_invoices where id = p_invoice_id for update;
  select * into v_receipt from public.cash_receipts where id = p_receipt_id for update;
  if v_invoice.id is null or v_receipt.id is null then raise exception using errcode = 'P0002', message = 'INVOICE_OR_RECEIPT_NOT_FOUND'; end if;
  if v_invoice.business_id <> v_receipt.business_id then raise exception using errcode = '23514', message = 'CROSS_BUSINESS_ALLOCATION_FORBIDDEN'; end if;
  if not exists (select 1 from public.businesses b where b.id = v_invoice.business_id and b.owner_id = auth.uid()) then
    raise exception using errcode = '42501', message = 'BUSINESS_ACCESS_DENIED';
  end if;
  if v_invoice.status <> 'posted' or v_receipt.status <> 'posted' then raise exception using errcode = '55000', message = 'ALLOCATION_REQUIRES_POSTED_INVOICE_AND_RECEIPT'; end if;
  if v_invoice.customer_id <> v_receipt.customer_id then raise exception using errcode = '23514', message = 'CUSTOMER_MISMATCH'; end if;
  if v_invoice.currency_code <> v_receipt.currency_code then raise exception using errcode = '23514', message = 'CROSS_CURRENCY_ALLOCATION_REQUIRES_FX_WORKFLOW'; end if;
  if exists (select 1 from public.invoice_receipt_allocations where business_id = v_invoice.business_id and idempotency_key = p_idempotency_key) then
    raise exception using errcode = '23505', message = 'IDEMPOTENCY_KEY_ALREADY_USED';
  end if;

  select status into v_period_status from public.accounting_periods
    where business_id = v_invoice.business_id and p_accounting_date between starts_on and ends_on
    order by starts_on desc limit 1 for update;
  if v_period_status is distinct from 'open' then raise exception using errcode = '55000', message = 'ACCOUNTING_PERIOD_MISSING_OR_CLOSED'; end if;

  select coalesce(sum(a.amount),0) into v_allocated_invoice
    from public.invoice_receipt_allocations a join public.journal_entries je on je.id = a.journal_entry_id and je.status = 'posted'
    where a.invoice_id = v_invoice.id;
  select coalesce(sum(a.amount),0) into v_allocated_receipt
    from public.invoice_receipt_allocations a join public.journal_entries je on je.id = a.journal_entry_id and je.status = 'posted'
    where a.receipt_id = v_receipt.id;
  if v_allocated_invoice + p_amount > v_invoice.gross_amount then raise exception using errcode = '23514', message = 'ALLOCATION_EXCEEDS_INVOICE_OUTSTANDING'; end if;
  if v_allocated_receipt + p_amount > v_receipt.amount then raise exception using errcode = '23514', message = 'ALLOCATION_EXCEEDS_RECEIPT_UNALLOCATED_BALANCE'; end if;

  insert into public.journal_entries
    (business_id, entry_date, reference, description, status, created_by, source_document_type,
     source_document_id, entry_kind, idempotency_key, policy_version)
  values (v_invoice.business_id, p_accounting_date, v_receipt.receipt_number,
    'Allocate receipt ' || v_receipt.receipt_number || ' to invoice ' || v_invoice.invoice_number,
    'draft', auth.uid(), 'receipt_allocation', v_allocation_id, 'adjustment',
    p_idempotency_key, 'accounting-core-v1')
  returning id into v_journal_id;

  insert into public.invoice_receipt_allocations
    (id, business_id, invoice_id, receipt_id, amount, journal_entry_id, created_by, idempotency_key)
  values (v_allocation_id, v_invoice.business_id, v_invoice.id, v_receipt.id, p_amount, v_journal_id, auth.uid(), p_idempotency_key);

  insert into public.journal_lines (journal_entry_id, account_id, description, debit, credit)
    values (v_journal_id, v_receipt.customer_advance_account_id, 'Apply customer advance — ' || v_receipt.receipt_number, p_amount, 0);
  insert into public.journal_lines (journal_entry_id, account_id, description, debit, credit)
    values (v_journal_id, v_invoice.accounts_receivable_account_id, 'Settle invoice — ' || v_invoice.invoice_number, 0, p_amount);
  update public.journal_entries set status = 'posted', posted_at = now() where id = v_journal_id;

  insert into public.accounting_audit_events (business_id, actor_id, event_type, entity_type, entity_id, reason, metadata)
    values (v_invoice.business_id, auth.uid(), 'receipt.allocated', 'invoice_receipt_allocation', v_allocation_id,
      'Receipt allocated to posted invoice', jsonb_build_object('receipt_id', v_receipt.id, 'invoice_id', v_invoice.id,
      'amount', p_amount, 'journal_entry_id', v_journal_id, 'idempotency_key', p_idempotency_key));

  return query select v_allocation_id, v_journal_id, p_amount, v_invoice.gross_amount - v_allocated_invoice - p_amount;
end;
$$;
revoke all on function public.allocate_receipt_to_invoice(uuid, uuid, numeric, date, text) from public, anon;
grant execute on function public.allocate_receipt_to_invoice(uuid, uuid, numeric, date, text) to authenticated;

create or replace view public.receipt_book
with (security_invoker = true)
as
select r.business_id, r.id as receipt_id, r.receipt_number, r.receipt_date, r.currency_code,
  c.id as customer_id, c.display_name as customer_name, r.amount, r.status as document_status,
  r.journal_entry_id,
  coalesce(sum(a.amount) filter (where aje.status = 'posted'),0) as allocated_amount,
  r.amount - coalesce(sum(a.amount) filter (where aje.status = 'posted'),0) as unallocated_amount
from public.cash_receipts r
join public.customers c on c.id = r.customer_id and c.business_id = r.business_id
left join public.invoice_receipt_allocations a on a.receipt_id = r.id and a.business_id = r.business_id
left join public.journal_entries aje on aje.id = a.journal_entry_id
group by r.business_id, r.id, r.receipt_number, r.receipt_date, r.currency_code, c.id, c.display_name, r.amount, r.status, r.journal_entry_id;
grant select on public.receipt_book to authenticated;
comment on view public.receipt_book is 'Receipt register with posted allocations derived from allocation journals.';

create or replace view public.sales_book
with (security_invoker = true)
as
select i.business_id, i.id as invoice_id, i.invoice_number, i.document_date, i.supply_date,
  i.due_date, i.currency_code, i.status as document_status, i.compliance_status,
  c.id as customer_id, c.display_name as customer_name, i.net_amount, i.tax_amount, i.gross_amount,
  i.posting_journal_id, i.cancellation_journal_id, i.created_at,
  coalesce(sum(a.amount) filter (where aje.status = 'posted'),0) as allocated_amount,
  greatest(i.gross_amount - coalesce(sum(a.amount) filter (where aje.status = 'posted'),0),0) as outstanding_amount
from public.sales_invoices i
join public.customers c on c.id = i.customer_id and c.business_id = i.business_id
left join public.invoice_receipt_allocations a on a.invoice_id = i.id and a.business_id = i.business_id
left join public.journal_entries aje on aje.id = a.journal_entry_id
group by i.business_id, i.id, i.invoice_number, i.document_date, i.supply_date, i.due_date, i.currency_code,
  i.status, i.compliance_status, c.id, c.display_name, i.net_amount, i.tax_amount, i.gross_amount,
  i.posting_journal_id, i.cancellation_journal_id, i.created_at;
