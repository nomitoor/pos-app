-- Cloud backup setup for the POS app.
-- Run once in the Supabase dashboard: SQL Editor → New query → paste → Run.
--
-- Creates a PRIVATE storage bucket "backups". Each signed-in account can
-- only read, write and delete files inside its own folder (named after its
-- user id), so one shop can never see another shop's backups.

insert into storage.buckets (id, name, public)
values ('backups', 'backups', false)
on conflict (id) do nothing;

drop policy if exists "backups: read own" on storage.objects;
create policy "backups: read own"
  on storage.objects for select to authenticated
  using (bucket_id = 'backups'
         and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "backups: upload own" on storage.objects;
create policy "backups: upload own"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'backups'
              and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "backups: update own" on storage.objects;
create policy "backups: update own"
  on storage.objects for update to authenticated
  using (bucket_id = 'backups'
         and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "backups: delete own" on storage.objects;
create policy "backups: delete own"
  on storage.objects for delete to authenticated
  using (bucket_id = 'backups'
         and (storage.foldername(name))[1] = (select auth.uid())::text);
