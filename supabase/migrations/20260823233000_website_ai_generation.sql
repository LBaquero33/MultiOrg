begin;

create table if not exists public.sd_public_site_ai_generations (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sd_public_sites(id) on delete cascade,
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  scope text not null check (scope in ('site', 'page', 'block')),
  status text not null default 'generating' check (status in ('generating', 'ready', 'applied', 'discarded', 'failed', 'expired')),
  target_page_id uuid references public.sd_public_site_pages(id) on delete set null,
  target_block_id uuid,
  base_revision integer not null check (base_revision > 0),
  usage_units integer not null check (usage_units in (1, 3, 10)),
  request_summary text not null check (char_length(request_summary) between 1 and 300),
  prompt_hash text not null check (prompt_hash ~ '^[0-9a-f]{64}$'),
  model text not null check (char_length(model) between 1 and 120),
  provider_response_id text,
  input_tokens integer not null default 0 check (input_tokens >= 0),
  output_tokens integer not null default 0 check (output_tokens >= 0),
  total_tokens integer not null default 0 check (total_tokens >= 0),
  proposal jsonb check (proposal is null or jsonb_typeof(proposal) = 'object'),
  error_code text,
  expires_at timestamptz not null default (now() + interval '24 hours'),
  applied_at timestamptz,
  applied_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists sd_public_site_ai_generations_org_usage
  on public.sd_public_site_ai_generations(org_id, created_at desc)
  where status in ('generating', 'ready', 'applied');

create index if not exists sd_public_site_ai_generations_site_status
  on public.sd_public_site_ai_generations(site_id, status, created_at desc);

alter table public.sd_public_site_ai_generations enable row level security;

create policy sd_public_site_ai_generations_read on public.sd_public_site_ai_generations
  for select to authenticated
  using (public.sd_public_site_can_manage(org_id));

grant select on public.sd_public_site_ai_generations to authenticated;
revoke insert, update, delete on public.sd_public_site_ai_generations from anon, authenticated;
grant select, insert, update, delete on public.sd_public_site_ai_generations to service_role;

create or replace function public.sd_apply_public_site_ai_generation(
  p_generation_id uuid,
  p_expected_revision integer
)
returns table(draft_revision integer, primary_page_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_generation public.sd_public_site_ai_generations%rowtype;
  v_site public.sd_public_sites%rowtype;
  v_page jsonb;
  v_site_patch jsonb;
  v_pages jsonb;
  v_page_id uuid;
  v_primary_page_id uuid;
  v_target_page public.sd_public_site_pages%rowtype;
  v_home_count integer;
  v_now timestamptz := now();
begin
  select * into v_generation
  from public.sd_public_site_ai_generations
  where id = p_generation_id
  for update;

  if v_generation.id is null then
    raise exception 'ai_generation_not_found';
  end if;
  if v_generation.created_by <> auth.uid() then
    raise exception 'ai_generation_not_found';
  end if;
  if v_generation.status <> 'ready' then
    raise exception 'ai_generation_not_ready';
  end if;
  if v_generation.expires_at <= v_now then
    update public.sd_public_site_ai_generations
    set status = 'expired', updated_at = v_now
    where id = v_generation.id;
    raise exception 'ai_generation_expired';
  end if;
  if v_generation.proposal is null then
    raise exception 'ai_generation_invalid';
  end if;

  select * into v_site
  from public.sd_public_sites
  where id = v_generation.site_id
  for update;

  if v_site.id is null or v_site.org_id <> v_generation.org_id then
    raise exception 'site_not_found';
  end if;
  if not public.sd_public_site_can_manage(v_site.org_id) then
    raise exception 'website_admin_required';
  end if;
  if v_site.draft_revision <> p_expected_revision
     or v_generation.base_revision <> p_expected_revision then
    raise exception 'website_revision_conflict';
  end if;

  v_site_patch := coalesce(v_generation.proposal -> 'site_patch', '{}'::jsonb);
  v_pages := coalesce(v_generation.proposal -> 'pages', '[]'::jsonb);
  if jsonb_typeof(v_pages) <> 'array'
     or jsonb_array_length(v_pages) < 1
     or jsonb_array_length(v_pages) > 10 then
    raise exception 'ai_generation_invalid';
  end if;

  if v_generation.scope = 'site' then
    select count(*) into v_home_count
    from jsonb_array_elements(v_pages) item
    where coalesce((item ->> 'is_home')::boolean, false);
    if v_home_count <> 1 then
      raise exception 'ai_generation_invalid';
    end if;

    delete from public.sd_public_site_navigation_items where site_id = v_site.id;
    delete from public.sd_public_site_pages where site_id = v_site.id;

    for v_page in select value from jsonb_array_elements(v_pages)
    loop
      v_page_id := (v_page ->> 'id')::uuid;
      insert into public.sd_public_site_pages(
        id, site_id, org_id, title, slug, page_type, is_home,
        navigation_location, navigation_parent_id, sort_order, status,
        blocks, seo, revision, created_by, updated_by
      ) values (
        v_page_id,
        v_site.id,
        v_site.org_id,
        left(coalesce(nullif(v_page ->> 'title', ''), 'Page'), 120),
        case when coalesce((v_page ->> 'is_home')::boolean, false) then '' else left(v_page ->> 'slug', 63) end,
        case when v_page ->> 'page_type' in ('standard', 'team', 'staff', 'schedule', 'facility', 'offering', 'contact', 'news', 'faq', 'gallery')
          then v_page ->> 'page_type' else 'standard' end,
        coalesce((v_page ->> 'is_home')::boolean, false),
        case when v_page ->> 'navigation_location' in ('header', 'footer', 'utility', 'hidden')
          then v_page ->> 'navigation_location' else 'header' end,
        null,
        coalesce((v_page ->> 'sort_order')::integer, 0),
        'draft',
        coalesce(v_page -> 'blocks', '[]'::jsonb),
        coalesce(v_page -> 'seo', '{}'::jsonb),
        1,
        auth.uid(),
        auth.uid()
      );
      if coalesce((v_page ->> 'is_home')::boolean, false) then
        v_primary_page_id := v_page_id;
      end if;
    end loop;

    insert into public.sd_public_site_navigation_items(
      site_id, org_id, location, parent_id, item_type, label, page_id,
      destination, sort_order, is_visible, created_by, updated_by
    )
    select
      v_site.id,
      v_site.org_id,
      case when item ->> 'navigation_location' in ('header', 'footer', 'utility')
        then item ->> 'navigation_location' else 'header' end,
      null,
      'page',
      left(coalesce(nullif(item ->> 'title', ''), 'Page'), 80),
      (item ->> 'id')::uuid,
      jsonb_build_object('page_id', item ->> 'id'),
      coalesce((item ->> 'sort_order')::integer, 0),
      item ->> 'navigation_location' <> 'hidden',
      auth.uid(),
      auth.uid()
    from jsonb_array_elements(v_pages) item
    where item ->> 'navigation_location' <> 'hidden';

    update public.sd_public_sites
    set name = left(coalesce(nullif(v_site_patch ->> 'name', ''), name), 120),
        theme = coalesce(v_site_patch -> 'theme', theme),
        settings = coalesce(v_site_patch -> 'settings', settings),
        draft_revision = p_expected_revision + 1,
        updated_by = auth.uid(),
        updated_at = v_now
    where id = v_site.id;
  else
    if jsonb_array_length(v_pages) <> 1 or v_generation.target_page_id is null then
      raise exception 'ai_generation_invalid';
    end if;
    v_page := v_pages -> 0;
    select * into v_target_page
    from public.sd_public_site_pages
    where id = v_generation.target_page_id
      and site_id = v_site.id
      and org_id = v_site.org_id
    for update;
    if v_target_page.id is null then
      raise exception 'page_not_found';
    end if;

    update public.sd_public_site_pages
    set title = case when v_generation.scope = 'page'
          then left(coalesce(nullif(v_page ->> 'title', ''), title), 120)
          else title end,
        slug = case
          when is_home then ''
          when v_generation.scope = 'page' then left(v_page ->> 'slug', 63)
          else slug end,
        page_type = case
          when v_generation.scope = 'page' and v_page ->> 'page_type' in ('standard', 'team', 'staff', 'schedule', 'facility', 'offering', 'contact', 'news', 'faq', 'gallery')
            then v_page ->> 'page_type'
          else page_type end,
        blocks = coalesce(v_page -> 'blocks', blocks),
        seo = case when v_generation.scope = 'page' then coalesce(v_page -> 'seo', seo) else seo end,
        status = 'draft',
        revision = revision + 1,
        updated_by = auth.uid(),
        updated_at = v_now
    where id = v_target_page.id;

    update public.sd_public_site_navigation_items
    set label = case when v_generation.scope = 'page'
          then left(coalesce(nullif(v_page ->> 'title', ''), label), 80)
          else label end,
        updated_by = auth.uid(),
        updated_at = v_now
    where page_id = v_target_page.id
      and org_id = v_site.org_id;

    update public.sd_public_sites
    set draft_revision = p_expected_revision + 1,
        updated_by = auth.uid(),
        updated_at = v_now
    where id = v_site.id;
    v_primary_page_id := v_target_page.id;
  end if;

  update public.sd_public_site_ai_generations
  set status = 'applied',
      applied_at = v_now,
      applied_by = auth.uid(),
      updated_at = v_now
  where id = v_generation.id;

  insert into public.sd_public_site_audit_log(
    site_id, org_id, actor_id, action, target_type, target_id, details
  ) values (
    v_site.id,
    v_site.org_id,
    auth.uid(),
    'ai_generation_applied',
    v_generation.scope,
    v_generation.id::text,
    jsonb_build_object(
      'scope', v_generation.scope,
      'model', v_generation.model,
      'usage_units', v_generation.usage_units,
      'total_tokens', v_generation.total_tokens
    )
  );

  return query select p_expected_revision + 1, v_primary_page_id;
end;
$$;

revoke all on function public.sd_apply_public_site_ai_generation(uuid, integer) from public;
grant execute on function public.sd_apply_public_site_ai_generation(uuid, integer) to authenticated;

commit;
