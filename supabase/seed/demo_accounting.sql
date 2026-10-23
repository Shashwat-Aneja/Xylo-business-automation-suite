-- Demo seed for LOCAL / DISPOSABLE DEVELOPMENT DATABASES ONLY.
-- Never run against xylo-production. Requires accounting migrations to be applied first.
-- Replace the UUID below with the owner_id of a test user already present in auth.users.
-- This is deliberately transaction-scoped and idempotent for the named demo business.
begin;

do $$
declare
  v_owner uuid := nullif(current_setting('xylo.demo_owner_id', true), '')::uuid;
  v_business uuid;
  v_cash uuid;
  v_ar uuid;
  v_ap uuid;
  v_revenue uuid;
  v_expense uuid;
  v_customer uuid;
  v_supplier uuid;
begin
  if v_owner is null or not exists (select 1 from auth.users where id = v_owner) then
    raise exception 'Set xylo.demo_owner_id to an existing TEST auth.users.id before running this seed';
  end if;

  insert into public.businesses (owner_id, display_name, legal_name, country_code, base_currency, timezone, accounting_basis, industry)
  values (v_owner, 'Xylo Demo Studio', 'Xylo Demo Studio', 'IN', 'INR', 'Asia/Kolkata', 'accrual', 'Professional services')
  on conflict do nothing;

  select id into v_business from public.businesses where owner_id = v_owner and display_name = 'Xylo Demo Studio' order by created_at limit 1;
  if v_business is null then raise exception 'Unable to resolve demo business'; end if;

  insert into public.accounts (business_id, code, name, account_type, normal_balance, is_system)
  values
    (v_business, 'DEMO-CASH', 'Demo Bank', 'asset', 'debit', true),
    (v_business, 'DEMO-AR', 'Accounts Receivable', 'asset', 'debit', true),
    (v_business, 'DEMO-AP', 'Accounts Payable', 'liability', 'credit', true),
    (v_business, 'DEMO-REV', 'Service Revenue', 'income', 'credit', true),
    (v_business, 'DEMO-EXP', 'Office Supplies Expense', 'expense', 'debit', true)
  on conflict (business_id, code) do nothing;

  select id into v_cash from public.accounts where business_id=v_business and code='DEMO-CASH';
  select id into v_ar from public.accounts where business_id=v_business and code='DEMO-AR';
  select id into v_ap from public.accounts where business_id=v_business and code='DEMO-AP';
  select id into v_revenue from public.accounts where business_id=v_business and code='DEMO-REV';
  select id into v_expense from public.accounts where business_id=v_business and code='DEMO-EXP';

  insert into public.accounting_periods (business_id, period_name, starts_on, ends_on, status)
  values (v_business, 'Demo FY 2026-27', date '2026-04-01', date '2027-03-31', 'open')
  on conflict (business_id, period_name) do nothing;

  insert into public.customers (business_id, display_name, email, payment_terms_days)
  values (v_business, 'Northstar Design Co.', 'demo-customer@example.test', 15)
  on conflict do nothing;
  select id into v_customer from public.customers where business_id=v_business and display_name='Northstar Design Co.' order by created_at limit 1;

  insert into public.suppliers (business_id, display_name, email, payment_terms_days)
  values (v_business, 'Paper & Pixel Supplies', 'demo-supplier@example.test', 30)
  on conflict do nothing;
  select id into v_supplier from public.suppliers where business_id=v_business and display_name='Paper & Pixel Supplies' order by created_at limit 1;

  insert into public.business_accounting_profiles
    (business_id, legal_form, reporting_basis_default, supported_reporting_bases, gst_registration_status,
     profile_effective_from, applicability_review_status)
  values (v_business, 'sole_proprietorship', 'accrual', array['accrual']::text[], 'unknown', date '2026-04-01', 'unreviewed')
  on conflict (business_id) do nothing;

  -- Deliberately no GST/tax values and no posted journals: fixtures remain draft until a human
  -- completes independent applicability/rule review in a disposable test environment.
  insert into public.sales_invoices
    (business_id, customer_id, invoice_number, document_date, due_date, accounting_date, currency_code,
     accounts_receivable_account_id, net_amount, tax_amount, gross_amount, status)
  values (v_business, v_customer, 'DEMO-INV-001', date '2026-10-01', date '2026-10-16', date '2026-10-01',
     'INR', v_ar, 18000, 0, 18000, 'draft')
  on conflict (business_id, invoice_number) do nothing;

  insert into public.sales_invoice_lines
    (business_id, invoice_id, line_number, description, quantity, unit_price, discount_amount, net_amount, tax_amount, revenue_account_id)
  select v_business, i.id, 1, 'Website maintenance — demo fixture', 1, 18000, 0, 18000, 0, v_revenue
  from public.sales_invoices i where i.business_id=v_business and i.invoice_number='DEMO-INV-001'
  on conflict (invoice_id, line_number) do nothing;

  insert into public.supplier_bills
    (business_id, supplier_id, bill_number, supplier_reference, document_date, due_date, accounting_date,
     currency_code, accounts_payable_account_id, net_amount, tax_amount, gross_amount, status)
  values (v_business, v_supplier, 'DEMO-BILL-001', 'SUP-7781', date '2026-10-05', date '2026-11-04',
     date '2026-10-05', 'INR', v_ap, 4200, 0, 4200, 'draft')
  on conflict (business_id, bill_number) do nothing;

  insert into public.supplier_bill_lines
    (business_id, supplier_bill_id, line_number, description, quantity, unit_price, discount_amount, net_amount,
     tax_amount, recoverable_tax_amount, purchase_account_id)
  select v_business, b.id, 1, 'Paper and printing supplies — demo fixture', 20, 210, 0, 4200, 0, 0, v_expense
  from public.supplier_bills b where b.business_id=v_business and b.bill_number='DEMO-BILL-001'
  on conflict (supplier_bill_id, line_number) do nothing;
end $$;

commit;
