begin;

alter table public.profiles
  add column if not exists instagram_url text,
  add column if not exists perfect_game_url text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'organization-logos',
  'organization-logos',
  true,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "organization logos are publicly readable" on storage.objects;
create policy "organization logos are publicly readable"
on storage.objects for select
using (bucket_id = 'organization-logos');

drop policy if exists "organization admins upload logos" on storage.objects;
create policy "organization admins upload logos"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'organization-logos'
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and exists (
    select 1
    from public.sd_org_memberships membership
    where membership.org_id = ((storage.foldername(name))[1])::uuid
      and membership.user_id = auth.uid()
      and membership.status = 'active'
      and membership.role in ('owner', 'admin')
  )
);

drop policy if exists "organization admins update logos" on storage.objects;
create policy "organization admins update logos"
on storage.objects for update to authenticated
using (
  bucket_id = 'organization-logos'
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and exists (
    select 1
    from public.sd_org_memberships membership
    where membership.org_id = ((storage.foldername(name))[1])::uuid
      and membership.user_id = auth.uid()
      and membership.status = 'active'
      and membership.role in ('owner', 'admin')
  )
)
with check (
  bucket_id = 'organization-logos'
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and exists (
    select 1
    from public.sd_org_memberships membership
    where membership.org_id = ((storage.foldername(name))[1])::uuid
      and membership.user_id = auth.uid()
      and membership.status = 'active'
      and membership.role in ('owner', 'admin')
  )
);

drop policy if exists "organization admins delete logos" on storage.objects;
create policy "organization admins delete logos"
on storage.objects for delete to authenticated
using (
  bucket_id = 'organization-logos'
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and exists (
    select 1
    from public.sd_org_memberships membership
    where membership.org_id = ((storage.foldername(name))[1])::uuid
      and membership.user_id = auth.uid()
      and membership.status = 'active'
      and membership.role in ('owner', 'admin')
  )
);

drop policy if exists "sd_bp_sessions_select" on public.sd_bp_sessions;
create policy "sd_bp_sessions_select"
on public.sd_bp_sessions for select to authenticated
using (
  player_id = auth.uid()
  or public.sd_can_manage_team_player(org_id, player_id)
  or public.sd_is_linked_parent_in_org(auth.uid(), player_id, org_id)
);

drop policy if exists "sd_development_import_jobs_staff_read" on public.sd_development_import_jobs;
create policy "sd_development_import_jobs_authorized_read"
on public.sd_development_import_jobs for select to authenticated
using (
  player_id = auth.uid()
  or (
    player_id is not null
    and public.sd_can_manage_team_player(org_id, player_id)
  )
  or (
    player_id is not null
    and public.sd_is_linked_parent_in_org(auth.uid(), player_id, org_id)
  )
  or (
    player_id is null
    and requested_by = auth.uid()
    and exists (
      select 1
      from public.sd_org_memberships membership
      where membership.org_id = sd_development_import_jobs.org_id
        and membership.user_id = auth.uid()
        and membership.status = 'active'
        and membership.role in ('owner', 'admin', 'coach')
    )
  )
);

create or replace function public.sd_create_owned_organization_for_actor(
  p_actor_id uuid,
  p_name text,
  p_slug text,
  p_billing_email text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := gen_random_uuid();
  v_name text := btrim(coalesce(p_name, ''));
  v_slug text := lower(btrim(coalesce(p_slug, '')));
  v_email text := nullif(lower(btrim(coalesce(p_billing_email, ''))), '');
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  if p_actor_id is null then
    raise exception 'actor_required' using errcode = '22023';
  end if;
  if length(v_name) < 2 or length(v_name) > 120 then
    raise exception 'invalid_organization_name' using errcode = '22023';
  end if;
  if v_slug !~ '^[a-z0-9][a-z0-9-]{2,47}$' then
    raise exception 'invalid_organization_slug' using errcode = '22023';
  end if;

  insert into public.sd_orgs (
    id, name, slug, status, plan, billing_email, support_email, timezone
  ) values (
    v_org_id, v_name, v_slug, 'active', 'starter', v_email, v_email, 'America/New_York'
  );

  insert into public.sd_org_memberships (
    org_id, user_id, role, status, created_by
  ) values (
    v_org_id, p_actor_id, 'owner', 'active', p_actor_id
  );

  insert into public.sd_org_settings (
    org_id, display_name, short_name, feature_flags
  ) values (
    v_org_id,
    v_name,
    left(v_name, 24),
    jsonb_build_object(
      'facilities', true,
      'chat', true,
      'programs', true,
      'testing', true,
      'bpAnalysis', true,
      'parentPortal', true,
      'billing', true
    )
  );

  insert into public.sd_org_billing_accounts (org_id, provider, billing_email)
  values (v_org_id, 'stripe', v_email)
  on conflict (org_id) do nothing;

  return v_org_id;
end;
$$;

revoke all on function public.sd_create_owned_organization_for_actor(uuid, text, text, text)
from public, anon, authenticated;
grant execute on function public.sd_create_owned_organization_for_actor(uuid, text, text, text)
to service_role;

commit;
