-- Phase 4: versioned, inheritable baseball rulesets.
-- Rollback: detach rulesets from games, then drop the policies, functions, and tables.

create table if not exists public.sd_game_rulesets (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  name text not null,
  scope_type text not null default 'organization'
    check (scope_type in ('base','governing_body','league','season','division','tournament','game')),
  scope_id uuid,
  parent_ruleset_id uuid references public.sd_game_rulesets(id),
  source_name text,
  source_version text,
  is_active boolean not null default true,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, name)
);

create table if not exists public.sd_game_ruleset_versions (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  ruleset_id uuid not null references public.sd_game_rulesets(id) on delete cascade,
  version integer not null check (version > 0),
  configuration jsonb not null default '{}'::jsonb,
  resolved_configuration jsonb not null default '{}'::jsonb,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (ruleset_id, version)
);

create index if not exists sd_game_rulesets_org_scope_idx
  on public.sd_game_rulesets(org_id, scope_type, scope_id) where is_active;
create index if not exists sd_game_ruleset_versions_ruleset_idx
  on public.sd_game_ruleset_versions(ruleset_id, version desc);

drop trigger if exists trg_sd_game_rulesets_updated_at on public.sd_game_rulesets;
create trigger trg_sd_game_rulesets_updated_at before update on public.sd_game_rulesets
for each row execute function public.sd_touch_updated_at();

alter table public.sd_game_rulesets enable row level security;
alter table public.sd_game_ruleset_versions enable row level security;

drop policy if exists sd_game_rulesets_select on public.sd_game_rulesets;
create policy sd_game_rulesets_select on public.sd_game_rulesets for select
using (public.sd_is_org_member(org_id) or public.sd_is_platform_admin_game_support());
drop policy if exists sd_game_rulesets_manage on public.sd_game_rulesets;
create policy sd_game_rulesets_manage on public.sd_game_rulesets for all
using (public.sd_is_org_admin(org_id)) with check (public.sd_is_org_admin(org_id));

drop policy if exists sd_game_ruleset_versions_select on public.sd_game_ruleset_versions;
create policy sd_game_ruleset_versions_select on public.sd_game_ruleset_versions for select
using (public.sd_is_org_member(org_id) or public.sd_is_platform_admin_game_support());
drop policy if exists sd_game_ruleset_versions_manage on public.sd_game_ruleset_versions;
create policy sd_game_ruleset_versions_manage on public.sd_game_ruleset_versions for all
using (public.sd_is_org_admin(org_id)) with check (public.sd_is_org_admin(org_id));

grant select on public.sd_game_rulesets, public.sd_game_ruleset_versions to authenticated;
grant insert, update, delete on public.sd_game_rulesets, public.sd_game_ruleset_versions to authenticated;

create or replace function public.sd_jsonb_deep_merge(base jsonb, override_value jsonb)
returns jsonb language sql immutable set search_path = '' as $$
  select coalesce(jsonb_object_agg(
    coalesce(b.key, o.key),
    case
      when jsonb_typeof(b.value) = 'object' and jsonb_typeof(o.value) = 'object'
        then public.sd_jsonb_deep_merge(b.value, o.value)
      else coalesce(o.value, b.value)
    end
  ), '{}'::jsonb)
  from jsonb_each(coalesce(base, '{}'::jsonb)) b
  full join jsonb_each(coalesce(override_value, '{}'::jsonb)) o using (key);
$$;

create or replace function public.sd_resolve_ruleset_version(p_ruleset_id uuid, p_version integer)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_row public.sd_game_ruleset_versions;
  v_parent uuid;
  v_parent_version integer;
  v_parent_config jsonb := '{}'::jsonb;
begin
  select * into v_row from public.sd_game_ruleset_versions
  where ruleset_id = p_ruleset_id and version = p_version;
  if not found or not public.sd_is_org_member(v_row.org_id) then
    raise exception 'ruleset_not_available';
  end if;
  select parent_ruleset_id into v_parent from public.sd_game_rulesets where id = p_ruleset_id;
  if v_parent is not null then
    select max(version) into v_parent_version from public.sd_game_ruleset_versions where ruleset_id = v_parent;
    v_parent_config := public.sd_resolve_ruleset_version(v_parent, v_parent_version);
  end if;
  return public.sd_jsonb_deep_merge(v_parent_config, v_row.configuration);
end;
$$;
grant execute on function public.sd_resolve_ruleset_version(uuid, integer) to authenticated;

comment on table public.sd_game_ruleset_versions is
  'Immutable competition-rule versions; completed games retain resolved snapshots.';
