begin;
alter table public.sd_strength_logs
  add column if not exists result_values jsonb not null default '{}'::jsonb;
alter table public.sd_strength_logs
  drop constraint if exists sd_strength_logs_result_values_object_check;
alter table public.sd_strength_logs
  add constraint sd_strength_logs_result_values_object_check
  check (jsonb_typeof(result_values) = 'object');
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('exercise-demos', 'exercise-demos', true, 262144000, array['video/mp4'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists "exercise demos are publicly readable" on storage.objects;
create policy "exercise demos are publicly readable"
on storage.objects for select
using (bucket_id = 'exercise-demos');
drop policy if exists "organization staff upload exercise demos" on storage.objects;
create policy "organization staff upload exercise demos"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'exercise-demos'
  and exists (
    select 1
    from public.sd_org_memberships membership
    where membership.org_id::text = (storage.foldername(name))[1]
      and membership.user_id = (select auth.uid())
      and membership.status = 'active'
      and membership.role in ('owner', 'admin', 'coach')
  )
);
drop policy if exists "organization staff update exercise demos" on storage.objects;
create policy "organization staff update exercise demos"
on storage.objects for update to authenticated
using (
  bucket_id = 'exercise-demos'
  and owner_id = (select auth.uid()::text)
)
with check (
  bucket_id = 'exercise-demos'
  and owner_id = (select auth.uid()::text)
);
drop policy if exists "organization staff delete exercise demos" on storage.objects;
create policy "organization staff delete exercise demos"
on storage.objects for delete to authenticated
using (
  bucket_id = 'exercise-demos'
  and owner_id = (select auth.uid()::text)
);
commit;
