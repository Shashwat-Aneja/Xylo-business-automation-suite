-- Trigger functions are invoked by PostgreSQL triggers, not directly through the Data API.
-- Remove direct RPC execution for browser roles.
revoke all on function public.handle_new_user() from anon, authenticated;
revoke all on function public.set_updated_at() from anon, authenticated;
