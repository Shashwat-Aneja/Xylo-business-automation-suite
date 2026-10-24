-- Route manual journal posting through a single validated PostgreSQL transaction.
-- Apply only after the accounting foundation and interconnected accounting migrations.

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
  if new.status = 'posted' and
     (tg_op = 'INSERT' or (tg_op = 'UPDATE' and old.status is distinct from 'posted')) then
    if new.source_document_type is null
       or new.source_document_id is null
       or current_setting('xylo.posting_source_type', true) is distinct from new.source_document_type
       or current_setting('xylo.posting_source_id', true) is distinct from new.source_document_id::text then
      raise exception using errcode = '42501',
        message = 'ALL_JOURNALS_MUST_USE_CONTROLLED_POSTING_WORKFLOW';
    end if;

    select count(*), coalesce(sum(debit), 0), coalesce(sum(credit), 0)
      into v_count, v_debits, v_credits
      from public.journal_lines where journal_entry_id = new.id;

    if v_count < 2 or v_debits <= 0 or v_debits <> v_credits then
      raise exception using errcode = '23514',
        message = 'JOURNAL_NOT_BALANCED',
        detail = format('Posted journals require at least two lines and equal positive debits/credits; lines=%s debits=%s credits=%s', v_count, v_debits, v_credits);
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.assert_journal_balanced() from public, anon, authenticated;

create or replace function public.post_manual_journal_entry(
  p_journal_entry_id uuid,
  p_idempotency_key text
)
returns table (journal_entry_id uuid, entry_status text)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_entry public.journal_entries%rowtype;
  v_period_status text;
  v_line_count integer;
  v_debits numeric(18,2);
  v_credits numeric(18,2);
begin
  if auth.uid() is null then
    raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED';
  end if;
  if nullif(trim(p_idempotency_key), '') is null then
    raise exception using errcode = '22023', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;

  select * into v_entry
    from public.journal_entries
    where id = p_journal_entry_id
    for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'JOURNAL_ENTRY_NOT_FOUND';
  end if;
  if not exists (
    select 1 from public.businesses b
    where b.id = v_entry.business_id and b.owner_id = auth.uid()
  ) then
    raise exception using errcode = '42501', message = 'BUSINESS_ACCESS_DENIED';
  end if;

  if v_entry.status = 'posted' then
    if v_entry.source_document_type = 'manual_journal'
       and v_entry.source_document_id = v_entry.id then
      return query select v_entry.id, v_entry.status;
      return;
    end if;
    raise exception using errcode = '55000', message = 'JOURNAL_ENTRY_ALREADY_POSTED';
  end if;
  if v_entry.status <> 'draft' then
    raise exception using errcode = '55000', message = 'JOURNAL_ENTRY_NOT_POSTABLE';
  end if;
  if v_entry.source_document_type is not null then
    raise exception using errcode = '55000', message = 'SOURCE_DOCUMENT_JOURNALS_REQUIRE_THEIR_OWN_POSTING_WORKFLOW';
  end if;

  select status into v_period_status
    from public.accounting_periods
    where business_id = v_entry.business_id
      and v_entry.entry_date between starts_on and ends_on
    order by starts_on desc
    limit 1
    for update;
  if v_period_status is distinct from 'open' then
    raise exception using errcode = '55000', message = 'ACCOUNTING_PERIOD_MISSING_OR_CLOSED';
  end if;

  if exists (
    select 1
    from public.journal_lines jl
    left join public.accounts a on a.id = jl.account_id
    where jl.journal_entry_id = v_entry.id
      and (a.id is null or a.business_id <> v_entry.business_id or not a.is_active)
  ) then
    raise exception using errcode = '23514', message = 'JOURNAL_LINES_REQUIRE_ACTIVE_ACCOUNTS_IN_SAME_BUSINESS';
  end if;

  select count(*), coalesce(sum(debit), 0), coalesce(sum(credit), 0)
    into v_line_count, v_debits, v_credits
    from public.journal_lines
    where journal_entry_id = v_entry.id;
  if v_line_count < 2 or v_debits <= 0 or v_debits <> v_credits then
    raise exception using errcode = '23514', message = 'JOURNAL_NOT_BALANCED';
  end if;

  if exists (
    select 1 from public.journal_entries
    where business_id = v_entry.business_id
      and idempotency_key = p_idempotency_key
      and id <> v_entry.id
  ) then
    raise exception using errcode = '23505', message = 'IDEMPOTENCY_KEY_ALREADY_USED';
  end if;

  perform set_config('xylo.posting_source_type', 'manual_journal', true);
  perform set_config('xylo.posting_source_id', v_entry.id::text, true);
  update public.journal_entries
    set status = 'posted',
        posted_at = now(),
        source_document_type = 'manual_journal',
        source_document_id = v_entry.id,
        entry_kind = 'standard',
        idempotency_key = p_idempotency_key,
        policy_version = 'accounting-core-v1'
    where id = v_entry.id;

  insert into public.accounting_audit_events
    (business_id, actor_id, event_type, entity_type, entity_id, metadata)
  values (
    v_entry.business_id, auth.uid(), 'journal_entry.posted',
    'journal_entry', v_entry.id,
    jsonb_build_object('idempotency_key', p_idempotency_key, 'policy_version', 'accounting-core-v1')
  );

  return query select v_entry.id, 'posted'::text;
end;
$$;

revoke all on function public.post_manual_journal_entry(uuid, text) from public, anon;
grant execute on function public.post_manual_journal_entry(uuid, text) to authenticated;
comment on function public.post_manual_journal_entry(uuid, text) is
  'Validates ownership, open accounting period, active same-business accounts, and balanced lines before posting a manual journal and recording an audit event.';
