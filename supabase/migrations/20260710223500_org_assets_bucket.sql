-- Public organization branding assets. Paths are always <org-id>/logo.jpg.

insert into storage.buckets (id, name, public)
values ('org-assets', 'org-assets', true)
on conflict (id) do update set public = true;

drop policy if exists "org_assets_public_read" on storage.objects;
create policy "org_assets_public_read"
on storage.objects
for select
to public
using (bucket_id = 'org-assets');

drop policy if exists "org_assets_admin_insert" on storage.objects;
create policy "org_assets_admin_insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'org-assets'
  and case
    when coalesce((storage.foldername(name))[1], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then public.sd_is_org_admin((storage.foldername(name))[1]::uuid)
    else false
  end
);

drop policy if exists "org_assets_admin_update" on storage.objects;
create policy "org_assets_admin_update"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'org-assets'
  and case
    when coalesce((storage.foldername(name))[1], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then public.sd_is_org_admin((storage.foldername(name))[1]::uuid)
    else false
  end
)
with check (
  bucket_id = 'org-assets'
  and case
    when coalesce((storage.foldername(name))[1], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then public.sd_is_org_admin((storage.foldername(name))[1]::uuid)
    else false
  end
);

drop policy if exists "org_assets_admin_delete" on storage.objects;
create policy "org_assets_admin_delete"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'org-assets'
  and case
    when coalesce((storage.foldername(name))[1], '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then public.sd_is_org_admin((storage.foldername(name))[1]::uuid)
    else false
  end
);
