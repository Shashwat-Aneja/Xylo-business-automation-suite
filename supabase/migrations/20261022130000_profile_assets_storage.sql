-- Store user-uploaded profile photos and business logos in a private bucket.
-- Objects are private; the app uses short-lived signed URLs for display.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'profile-assets',
  'profile-assets',
  false,
  3145728,
  array['image/png','image/jpeg','image/webp','image/svg+xml']
)
on conflict (id) do update
set public = false,
    file_size_limit = 3145728,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Users can read own profile assets" on storage.objects;
create policy "Users can read own profile assets"
on storage.objects for select
to authenticated
using (bucket_id = 'profile-assets' and (storage.foldername(name))[1] = (select auth.uid()::text));

drop policy if exists "Users can upload own profile assets" on storage.objects;
create policy "Users can upload own profile assets"
on storage.objects for insert
to authenticated
with check (bucket_id = 'profile-assets' and (storage.foldername(name))[1] = (select auth.uid()::text));

drop policy if exists "Users can update own profile assets" on storage.objects;
create policy "Users can update own profile assets"
on storage.objects for update
to authenticated
using (bucket_id = 'profile-assets' and (storage.foldername(name))[1] = (select auth.uid()::text))
with check (bucket_id = 'profile-assets' and (storage.foldername(name))[1] = (select auth.uid()::text));

drop policy if exists "Users can delete own profile assets" on storage.objects;
create policy "Users can delete own profile assets"
on storage.objects for delete
to authenticated
using (bucket_id = 'profile-assets' and (storage.foldername(name))[1] = (select auth.uid()::text));
