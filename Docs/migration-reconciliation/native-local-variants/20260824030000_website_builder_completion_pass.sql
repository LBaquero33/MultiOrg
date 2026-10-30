begin;
alter table public.sd_public_site_pages
  drop constraint if exists sd_public_site_pages_page_type_check;
alter table public.sd_public_site_pages
  add constraint sd_public_site_pages_page_type_check
  check (page_type in (
    'standard', 'team', 'staff', 'schedule', 'development', 'facility',
    'offering', 'contact', 'news', 'faq', 'gallery'
  ));
create table if not exists public.sd_public_site_permissions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  can_edit boolean not null default false,
  can_publish boolean not null default false,
  status text not null default 'active' check (status in ('active', 'revoked')),
  granted_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, org_id),
  check (not can_publish or can_edit)
);
create index if not exists sd_public_site_permissions_org_status
  on public.sd_public_site_permissions(org_id, status, user_id);
alter table public.sd_public_site_permissions enable row level security;
create or replace function public.sd_public_site_is_org_admin(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.sd_org_memberships membership
    where membership.org_id = p_org_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
      and membership.role in ('owner', 'admin')
  );
$$;
create or replace function public.sd_public_site_can_edit(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.sd_public_site_is_org_admin(p_org_id)
    or (
      exists (
        select 1
        from public.sd_org_memberships membership
        where membership.org_id = p_org_id
          and membership.user_id = auth.uid()
          and membership.status = 'active'
      )
      and exists (
        select 1
        from public.sd_public_site_permissions permission
        where permission.org_id = p_org_id
          and permission.user_id = auth.uid()
          and permission.status = 'active'
          and permission.can_edit
      )
    );
$$;
create or replace function public.sd_public_site_can_publish(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.sd_public_site_is_org_admin(p_org_id)
    or (
      exists (
        select 1
        from public.sd_org_memberships membership
        where membership.org_id = p_org_id
          and membership.user_id = auth.uid()
          and membership.status = 'active'
      )
      and exists (
        select 1
        from public.sd_public_site_permissions permission
        where permission.org_id = p_org_id
          and permission.user_id = auth.uid()
          and permission.status = 'active'
          and permission.can_edit
          and permission.can_publish
      )
    );
$$;
create or replace function public.sd_public_site_can_manage(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.sd_public_site_can_edit(p_org_id);
$$;
revoke all on function public.sd_public_site_is_org_admin(uuid) from public;
revoke all on function public.sd_public_site_can_edit(uuid) from public;
revoke all on function public.sd_public_site_can_publish(uuid) from public;
revoke all on function public.sd_public_site_can_manage(uuid) from public;
grant execute on function public.sd_public_site_is_org_admin(uuid) to authenticated;
grant execute on function public.sd_public_site_can_edit(uuid) to authenticated;
grant execute on function public.sd_public_site_can_publish(uuid) to authenticated;
grant execute on function public.sd_public_site_can_manage(uuid) to authenticated;
create policy sd_public_site_permissions_read on public.sd_public_site_permissions
  for select to authenticated
  using (user_id = auth.uid() or public.sd_public_site_is_org_admin(org_id));
revoke insert, update, delete on public.sd_public_site_permissions from anon, authenticated;
grant select on public.sd_public_site_permissions to authenticated;
grant select, insert, update, delete on public.sd_public_site_permissions to service_role;
drop policy if exists sd_public_site_media_storage_select on storage.objects;
drop policy if exists sd_public_site_media_storage_insert on storage.objects;
drop policy if exists sd_public_site_media_storage_update on storage.objects;
drop policy if exists sd_public_site_media_storage_delete on storage.objects;
create policy sd_public_site_media_storage_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'organization-site-media'
    and public.sd_public_site_can_edit(((storage.foldername(name))[1])::uuid)
  );
create policy sd_public_site_media_storage_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'organization-site-media'
    and public.sd_public_site_can_edit(((storage.foldername(name))[1])::uuid)
  );
create policy sd_public_site_media_storage_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'organization-site-media'
    and public.sd_public_site_can_edit(((storage.foldername(name))[1])::uuid)
  )
  with check (
    bucket_id = 'organization-site-media'
    and public.sd_public_site_can_edit(((storage.foldername(name))[1])::uuid)
  );
create policy sd_public_site_media_storage_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'organization-site-media'
    and public.sd_public_site_can_edit(((storage.foldername(name))[1])::uuid)
  );
create table if not exists public.sd_public_site_draft_checkpoints (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sd_public_sites(id) on delete cascade,
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  revision integer not null check (revision > 0),
  reason text not null check (char_length(reason) between 1 and 80),
  generation_id uuid references public.sd_public_site_ai_generations(id) on delete set null,
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists sd_public_site_draft_checkpoints_site_created
  on public.sd_public_site_draft_checkpoints(site_id, created_at desc);
alter table public.sd_public_site_draft_checkpoints enable row level security;
create policy sd_public_site_draft_checkpoints_read on public.sd_public_site_draft_checkpoints
  for select to authenticated using (public.sd_public_site_can_edit(org_id));
grant select on public.sd_public_site_draft_checkpoints to authenticated;
grant select, insert, update, delete on public.sd_public_site_draft_checkpoints to service_role;
create table if not exists public.sd_public_site_editor_presence (
  site_id uuid not null references public.sd_public_sites(id) on delete cascade,
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  page_id uuid references public.sd_public_site_pages(id) on delete set null,
  display_name text,
  last_seen_at timestamptz not null default now(),
  primary key (site_id, user_id)
);
alter table public.sd_public_site_editor_presence enable row level security;
create policy sd_public_site_editor_presence_manage on public.sd_public_site_editor_presence
  for all to authenticated
  using (public.sd_public_site_can_edit(org_id))
  with check (public.sd_public_site_can_edit(org_id) and user_id = auth.uid());
grant select, insert, update, delete on public.sd_public_site_editor_presence to authenticated;
create table if not exists public.sd_public_site_ai_allowances (
  org_id uuid primary key references public.sd_orgs(id) on delete cascade,
  monthly_units integer not null default 30 check (monthly_units between 0 and 10000),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);
alter table public.sd_public_site_ai_allowances enable row level security;
create policy sd_public_site_ai_allowances_read on public.sd_public_site_ai_allowances
  for select to authenticated
  using (
    public.sd_public_site_can_edit(org_id)
    or exists (select 1 from public.sd_platform_admins platform where platform.user_id = auth.uid())
  );
revoke insert, update, delete on public.sd_public_site_ai_allowances from anon, authenticated;
grant select on public.sd_public_site_ai_allowances to authenticated;
grant select, insert, update, delete on public.sd_public_site_ai_allowances to service_role;
create table if not exists public.sd_public_site_stock_assets (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sd_public_sites(id) on delete cascade,
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  provider text not null check (provider in ('pexels')),
  provider_asset_id text not null,
  media_type text not null check (media_type in ('photo', 'video')),
  source_url text not null,
  delivery_url text not null,
  photographer_name text,
  photographer_url text,
  attribution text not null,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  selected_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (site_id, provider, provider_asset_id)
);
alter table public.sd_public_site_stock_assets enable row level security;
create policy sd_public_site_stock_assets_manage on public.sd_public_site_stock_assets
  for all to authenticated
  using (public.sd_public_site_can_edit(org_id))
  with check (public.sd_public_site_can_edit(org_id));
grant select, insert, update, delete on public.sd_public_site_stock_assets to authenticated;
grant select, insert, update, delete on public.sd_public_site_stock_assets to service_role;
alter table public.sd_public_site_ai_generations
  add column if not exists planning_status text not null default 'not_started'
    check (planning_status in ('not_started', 'ready', 'approved')),
  add column if not exists blueprint jsonb check (blueprint is null or jsonb_typeof(blueprint) = 'object'),
  add column if not exists reserved_units integer not null default 0 check (reserved_units >= 0),
  add column if not exists selected_page_ids uuid[] not null default '{}',
  add column if not exists stock_attribution jsonb not null default '[]'::jsonb
    check (jsonb_typeof(stock_attribution) = 'array'),
  add column if not exists validation_results jsonb not null default '{}'::jsonb
    check (jsonb_typeof(validation_results) = 'object'),
  add column if not exists estimated_cost_usd numeric(12,6) not null default 0 check (estimated_cost_usd >= 0);
create or replace function public.sd_capture_public_site_draft_checkpoint(
  p_site_id uuid,
  p_reason text,
  p_generation_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_site public.sd_public_sites%rowtype;
  v_checkpoint_id uuid;
  v_snapshot jsonb;
begin
  select * into v_site from public.sd_public_sites where id = p_site_id;
  if v_site.id is null or not public.sd_public_site_can_edit(v_site.org_id) then
    raise exception 'website_editor_required';
  end if;

  select jsonb_build_object(
    'site', to_jsonb(v_site) - 'created_by' - 'updated_by',
    'pages', coalesce((
      select jsonb_agg(to_jsonb(page_row) - 'created_by' - 'updated_by' order by page_row.sort_order, page_row.created_at)
      from public.sd_public_site_pages page_row where page_row.site_id = p_site_id
    ), '[]'::jsonb),
    'navigation', coalesce((
      select jsonb_agg(to_jsonb(nav_row) - 'created_by' - 'updated_by' order by nav_row.location, nav_row.sort_order)
      from public.sd_public_site_navigation_items nav_row where nav_row.site_id = p_site_id
    ), '[]'::jsonb),
    'forms', coalesce((
      select jsonb_agg(to_jsonb(form_row) - 'created_by' - 'updated_by')
      from public.sd_public_form_definitions form_row where form_row.site_id = p_site_id
    ), '[]'::jsonb)
  ) into v_snapshot;

  insert into public.sd_public_site_draft_checkpoints(
    site_id, org_id, revision, reason, generation_id, snapshot, created_by
  ) values (
    v_site.id, v_site.org_id, v_site.draft_revision,
    left(coalesce(nullif(btrim(p_reason), ''), 'manual'), 80),
    p_generation_id, v_snapshot, auth.uid()
  ) returning id into v_checkpoint_id;

  return v_checkpoint_id;
end;
$$;
create or replace function public.sd_publish_public_site_v2(
  p_site_id uuid,
  p_expected_revision integer
)
returns table(version_id uuid, version_number integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id from public.sd_public_sites where id = p_site_id;
  if v_org_id is null or not public.sd_public_site_can_publish(v_org_id) then
    raise exception 'website_publisher_required';
  end if;
  return query select * from public.sd_publish_public_site(p_site_id, p_expected_revision);
end;
$$;
create or replace function public.sd_apply_public_site_ai_generation_selection(
  p_generation_id uuid,
  p_expected_revision integer,
  p_selected_page_ids uuid[] default null
)
returns table(draft_revision integer, primary_page_id uuid, checkpoint_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_generation public.sd_public_site_ai_generations%rowtype;
  v_site public.sd_public_sites%rowtype;
  v_pages jsonb;
  v_page jsonb;
  v_generated_id uuid;
  v_target_id uuid;
  v_primary_page_id uuid;
  v_checkpoint_id uuid;
  v_all_ids uuid[];
  v_selected uuid[];
  v_now timestamptz := now();
begin
  select * into v_generation
  from public.sd_public_site_ai_generations
  where id = p_generation_id
  for update;
  if v_generation.id is null or v_generation.created_by <> auth.uid() then
    raise exception 'ai_generation_not_found';
  end if;
  if v_generation.status <> 'ready' then raise exception 'ai_generation_not_ready'; end if;
  if v_generation.expires_at <= v_now then raise exception 'ai_generation_expired'; end if;

  select * into v_site
  from public.sd_public_sites
  where id = v_generation.site_id and org_id = v_generation.org_id
  for update;
  if v_site.id is null then raise exception 'site_not_found'; end if;
  if not public.sd_public_site_can_edit(v_site.org_id) then
    raise exception 'website_editor_required';
  end if;
  if v_site.draft_revision <> p_expected_revision
     or v_generation.base_revision <> p_expected_revision then
    raise exception 'website_revision_conflict';
  end if;

  v_pages := coalesce(v_generation.proposal -> 'pages', '[]'::jsonb);
  if jsonb_typeof(v_pages) <> 'array' or jsonb_array_length(v_pages) < 1 then
    raise exception 'ai_generation_invalid';
  end if;
  select array_agg((item ->> 'id')::uuid)
  into v_all_ids
  from jsonb_array_elements(v_pages) item;
  v_selected := coalesce(p_selected_page_ids, v_all_ids);
  if cardinality(v_selected) < 1
     or exists (select 1 from unnest(v_selected) selected where not selected = any(v_all_ids)) then
    raise exception 'ai_generation_selection_invalid';
  end if;

  v_checkpoint_id := public.sd_capture_public_site_draft_checkpoint(
    v_site.id,
    'before_ai_apply',
    v_generation.id
  );

  if v_generation.scope <> 'site' or cardinality(v_selected) = cardinality(v_all_ids) then
    return query
      select applied.draft_revision, applied.primary_page_id, v_checkpoint_id
      from public.sd_apply_public_site_ai_generation(p_generation_id, p_expected_revision) applied;
    return;
  end if;

  for v_page in
    select value from jsonb_array_elements(v_pages)
    where (value ->> 'id')::uuid = any(v_selected)
  loop
    v_generated_id := (v_page ->> 'id')::uuid;
    v_target_id := null;
    select page_row.id into v_target_id
    from public.sd_public_site_pages page_row
    where page_row.site_id = v_site.id
      and (
        page_row.id = v_generated_id
        or (coalesce(v_page ->> 'slug', '') <> '' and lower(page_row.slug) = lower(v_page ->> 'slug'))
        or (coalesce((v_page ->> 'is_home')::boolean, false) and page_row.is_home)
      )
    order by case when page_row.id = v_generated_id then 0 when page_row.is_home then 1 else 2 end
    limit 1
    for update;

    if coalesce((v_page ->> 'is_home')::boolean, false) then
      update public.sd_public_site_pages
      set is_home = false, slug = case when slug = '' then 'home-' || left(id::text, 8) else slug end
      where site_id = v_site.id and is_home and id is distinct from v_target_id;
    end if;

    if v_target_id is null then
      v_target_id := v_generated_id;
      insert into public.sd_public_site_pages(
        id, site_id, org_id, title, slug, page_type, is_home,
        navigation_location, navigation_parent_id, sort_order, status,
        blocks, seo, revision, created_by, updated_by
      ) values (
        v_target_id, v_site.id, v_site.org_id,
        left(coalesce(nullif(v_page ->> 'title', ''), 'Page'), 120),
        case when coalesce((v_page ->> 'is_home')::boolean, false) then '' else left(v_page ->> 'slug', 63) end,
        case when v_page ->> 'page_type' in ('standard','team','staff','schedule','development','facility','offering','contact','news','faq','gallery')
          then v_page ->> 'page_type' else 'standard' end,
        coalesce((v_page ->> 'is_home')::boolean, false),
        case when v_page ->> 'navigation_location' in ('header','footer','utility','hidden')
          then v_page ->> 'navigation_location' else 'header' end,
        null,
        coalesce((v_page ->> 'sort_order')::integer, 0),
        'draft', coalesce(v_page -> 'blocks', '[]'::jsonb), coalesce(v_page -> 'seo', '{}'::jsonb),
        1, auth.uid(), auth.uid()
      );
    else
      update public.sd_public_site_pages
      set title = left(coalesce(nullif(v_page ->> 'title', ''), title), 120),
          slug = case when coalesce((v_page ->> 'is_home')::boolean, false) then '' else left(v_page ->> 'slug', 63) end,
          page_type = case when v_page ->> 'page_type' in ('standard','team','staff','schedule','development','facility','offering','contact','news','faq','gallery')
            then v_page ->> 'page_type' else page_type end,
          is_home = coalesce((v_page ->> 'is_home')::boolean, false),
          navigation_location = case when v_page ->> 'navigation_location' in ('header','footer','utility','hidden')
            then v_page ->> 'navigation_location' else navigation_location end,
          sort_order = coalesce((v_page ->> 'sort_order')::integer, sort_order),
          status = 'draft',
          blocks = coalesce(v_page -> 'blocks', blocks),
          seo = coalesce(v_page -> 'seo', seo),
          revision = revision + 1,
          updated_by = auth.uid(),
          updated_at = v_now
      where id = v_target_id;
    end if;

    delete from public.sd_public_site_navigation_items
    where site_id = v_site.id and page_id = v_target_id;
    if coalesce(v_page ->> 'navigation_location', 'header') <> 'hidden' then
      insert into public.sd_public_site_navigation_items(
        site_id, org_id, location, item_type, label, page_id, destination,
        sort_order, is_visible, created_by, updated_by
      ) values (
        v_site.id, v_site.org_id,
        case when v_page ->> 'navigation_location' in ('header','footer','utility')
          then v_page ->> 'navigation_location' else 'header' end,
        'page', left(coalesce(nullif(v_page ->> 'title', ''), 'Page'), 80),
        v_target_id, jsonb_build_object('page_id', v_target_id),
        coalesce((v_page ->> 'sort_order')::integer, 0), true, auth.uid(), auth.uid()
      );
    end if;
    if v_primary_page_id is null then v_primary_page_id := v_target_id; end if;
  end loop;

  update public.sd_public_sites
  set draft_revision = p_expected_revision + 1,
      updated_by = auth.uid(),
      updated_at = v_now
  where id = v_site.id;
  update public.sd_public_site_ai_generations
  set status = 'applied', selected_page_ids = v_selected,
      applied_at = v_now, applied_by = auth.uid(), updated_at = v_now
  where id = v_generation.id;
  insert into public.sd_public_site_audit_log(
    site_id, org_id, actor_id, action, target_type, target_id, details
  ) values (
    v_site.id, v_site.org_id, auth.uid(), 'ai_generation_pages_applied', 'site',
    v_generation.id::text,
    jsonb_build_object('selected_page_ids', v_selected, 'checkpoint_id', v_checkpoint_id)
  );

  return query select p_expected_revision + 1, v_primary_page_id, v_checkpoint_id;
end;
$$;
revoke all on function public.sd_capture_public_site_draft_checkpoint(uuid, text, uuid) from public;
grant execute on function public.sd_capture_public_site_draft_checkpoint(uuid, text, uuid) to authenticated;
revoke all on function public.sd_publish_public_site(uuid, integer) from anon, authenticated;
revoke all on function public.sd_publish_public_site_v2(uuid, integer) from public;
grant execute on function public.sd_publish_public_site_v2(uuid, integer) to authenticated;
revoke all on function public.sd_apply_public_site_ai_generation(uuid, integer) from anon, authenticated;
revoke all on function public.sd_apply_public_site_ai_generation_selection(uuid, integer, uuid[]) from public;
grant execute on function public.sd_apply_public_site_ai_generation_selection(uuid, integer, uuid[]) to authenticated;
commit;
