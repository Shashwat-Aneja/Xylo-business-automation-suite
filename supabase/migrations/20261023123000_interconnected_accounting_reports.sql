-- Xylo reporting projections: all views are derived from the authoritative posted journal.
-- security_invoker prevents views from bypassing underlying RLS policies (PostgreSQL 15+).

create or replace view public.sales_book
with (security_invoker = true)
as
select
  i.business_id,
  i.id as invoice_id,
  i.invoice_number,
  i.document_date,
  i.supply_date,
  i.due_date,
  i.currency_code,
  i.status as document_status,
  i.compliance_status,
  c.id as customer_id,
  c.display_name as customer_name,
  i.net_amount,
  i.tax_amount,
  i.gross_amount,
  i.posting_journal_id,
  i.cancellation_journal_id,
  i.created_at
from public.sales_invoices i
join public.customers c on c.id = i.customer_id and c.business_id = i.business_id;

create or replace view public.general_ledger
with (security_invoker = true)
as
select
  je.business_id,
  je.id as journal_entry_id,
  jl.id as journal_line_id,
  je.entry_number,
  je.entry_date,
  je.reference,
  je.description as journal_description,
  je.status as journal_status,
  je.source_document_type,
  je.source_document_id,
  je.entry_kind,
  je.reversal_of,
  a.id as account_id,
  a.code as account_code,
  a.name as account_name,
  a.account_type,
  jl.description as line_description,
  jl.debit,
  jl.credit,
  sum(jl.debit - jl.credit) over (
    partition by je.business_id, a.id
    order by je.entry_date, je.entry_number, jl.id
    rows between unbounded preceding and current row
  ) as running_debit_minus_credit_balance
from public.journal_entries je
join public.journal_lines jl on jl.journal_entry_id = je.id
join public.accounts a on a.id = jl.account_id and a.business_id = je.business_id
where je.status = 'posted';

create or replace view public.trial_balance
with (security_invoker = true)
as
select
  je.business_id,
  a.id as account_id,
  a.code as account_code,
  a.name as account_name,
  a.account_type,
  sum(jl.debit) as total_debits,
  sum(jl.credit) as total_credits,
  sum(jl.debit) - sum(jl.credit) as debit_minus_credit_balance,
  'accrual'::text as reporting_basis
from public.journal_entries je
join public.journal_lines jl on jl.journal_entry_id = je.id
join public.accounts a on a.id = jl.account_id and a.business_id = je.business_id
where je.status = 'posted'
group by je.business_id, a.id, a.code, a.name, a.account_type;

create or replace view public.profit_and_loss
with (security_invoker = true)
as
select
  je.business_id,
  a.id as account_id,
  a.code as account_code,
  a.name as account_name,
  a.account_type,
  sum(case when a.account_type = 'income' then jl.credit - jl.debit
           when a.account_type = 'expense' then jl.debit - jl.credit
           else 0 end) as statement_amount,
  'accrual'::text as reporting_basis
from public.journal_entries je
join public.journal_lines jl on jl.journal_entry_id = je.id
join public.accounts a on a.id = jl.account_id and a.business_id = je.business_id
where je.status = 'posted' and a.account_type in ('income','expense')
group by je.business_id, a.id, a.code, a.name, a.account_type;

create or replace view public.balance_sheet
with (security_invoker = true)
as
select
  je.business_id,
  a.id as account_id,
  a.code as account_code,
  a.name as account_name,
  a.account_type,
  sum(case when a.account_type = 'asset' then jl.debit - jl.credit
           when a.account_type in ('liability','equity') then jl.credit - jl.debit
           else 0 end) as statement_amount,
  'accrual'::text as reporting_basis
from public.journal_entries je
join public.journal_lines jl on jl.journal_entry_id = je.id
join public.accounts a on a.id = jl.account_id and a.business_id = je.business_id
where je.status = 'posted' and a.account_type in ('asset','liability','equity')
group by je.business_id, a.id, a.code, a.name, a.account_type;

grant select on public.sales_book, public.general_ledger, public.trial_balance,
  public.profit_and_loss, public.balance_sheet to authenticated;

comment on view public.sales_book is 'Document register projection; includes status and links to posted journal/correction records.';
comment on view public.general_ledger is 'General ledger projection from all posted journal lines, with no arbitrary row limit.';
comment on view public.trial_balance is 'Accrual-basis trial balance projection from the complete posted journal population.';
comment on view public.profit_and_loss is 'Accrual-basis P&L projection. Cash-basis reports must use a separately reviewed transformation.';
comment on view public.balance_sheet is 'Accrual-basis balance sheet projection from posted journals.';
