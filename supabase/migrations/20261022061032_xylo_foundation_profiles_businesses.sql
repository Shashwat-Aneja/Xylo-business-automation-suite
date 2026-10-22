-- Xylo foundation: user profiles and business workspaces.
-- Authentication credentials remain in Supabase Auth; public profile data is separate.

create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  preferred_name text,
  avatar_url text,
  locale text not null default 'en',
  timezone text not null default 'UTC',
  onboarding_completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_full_name_length check (full_name is null or char_length(full_name) <= 160),
  constraint profiles_preferred_name_length check (preferred_name is null or char_length(preferred_name) <= 80)
);

create table public.businesses (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  legal_name text,
  display_name text not null,
  country_code text not null default 'IN',
  base_currency text not null default 'INR',
  timezone text not null default 'Asia/Kolkata',
  fiscal_year_start_month smallint not null default 4,
  accounting_basis text not null default 'accrual',
  industry text,
  website text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint businesses_display_name_length check (char_length(display_name) between 1 and 160),
  constraint businesses_legal_name_length check (legal_name is null or char_length(legal_name) <= 200),
  constraint businesses_country_code_format check (country_code ~ '^[A-Z]{2}$'),
  constraint businesses_currency_format check (base_currency ~ '^[A-Z]{3}$'),
  constraint businesses_fiscal_year_month check (fiscal_year_start_month between 1 and 12),
  constraint businesses_accounting_basis check (accounting_basis in ('cash', 'accrual'))
);
create index businesses_owner_created_idx on public.businesses (owner_id, created_at desc);

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = ''
as $$
begin new.updated_at := now(); return new; end;
$$;
revoke all on function public.set_updated_at() from public;

create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
create trigger businesses_set_updated_at before update on public.businesses
for each row execute function public.set_updated_at();

-- Supabase Auth inserts the profile automatically. The trigger uses a fixed search_path.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (user_id, full_name)
  values (new.id, nullif(trim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), ''))
  on conflict (user_id) do nothing;
  return new;
end;
$$;
revoke all on function public.handle_new_user() from public;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.businesses enable row level security;

grant select, insert, update on public.profiles to authenticated;
grant select, insert, update, delete on public.businesses to authenticated;

create policy "Users can read their own profile" on public.profiles
for select to authenticated using ((select auth.uid()) = user_id);
create policy "Users can create their own profile" on public.profiles
for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Users can update their own profile" on public.profiles
for update to authenticated using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "Owners can read their businesses" on public.businesses
for select to authenticated using ((select auth.uid()) = owner_id);
create policy "Owners can create their businesses" on public.businesses
for insert to authenticated with check ((select auth.uid()) = owner_id);
create policy "Owners can update their businesses" on public.businesses
for update to authenticated using ((select auth.uid()) = owner_id)
with check ((select auth.uid()) = owner_id);
create policy "Owners can delete their businesses" on public.businesses
for delete to authenticated using ((select auth.uid()) = owner_id);

comment on table public.profiles is 'User-facing profile metadata. Authentication credentials remain in Supabase Auth.';
comment on table public.businesses is 'Business workspace settings, including explicit jurisdiction, currency, timezone, and accounting basis.';
