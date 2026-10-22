-- Audit trail for server-side transactional mail. Do not expose this table to browser clients.
create table if not exists public.email_delivery_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  recipient_email text not null,
  message_type text not null check (message_type in ('account_email_test', 'invoice_reminder')),
  status text not null check (status in ('accepted', 'failed', 'delivered', 'bounced', 'complained')),
  provider_message_id text,
  error_code text,
  created_at timestamptz not null default now()
);

create index if not exists email_delivery_attempts_user_created_idx
  on public.email_delivery_attempts (user_id, created_at desc);
create unique index if not exists email_delivery_attempts_provider_message_idx
  on public.email_delivery_attempts (provider_message_id)
  where provider_message_id is not null;

alter table public.email_delivery_attempts enable row level security;
revoke all on table public.email_delivery_attempts from anon, authenticated;
grant select, insert on table public.email_delivery_attempts to service_role;
