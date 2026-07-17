-- Global, reversible platform control for the existing Player Development AI
-- and Copilot experience. The feature is intentionally disabled by default.

create table if not exists public.sd_platform_feature_flags (
  key text primary key,
  enabled boolean not null default false,
  description text not null default '',
  last_request_id uuid unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  constraint sd_platform_feature_flags_key_format
    check (key ~ '^[a-z][a-z0-9_]{2,79}$')
);

alter table public.sd_platform_feature_flags enable row level security;

drop policy if exists "sd_platform_feature_flags_authenticated_read"
  on public.sd_platform_feature_flags;
create policy "sd_platform_feature_flags_authenticated_read"
  on public.sd_platform_feature_flags
  for select
  to authenticated
  using (true);

revoke all on table public.sd_platform_feature_flags
  from public, anon, authenticated;
grant select on table public.sd_platform_feature_flags to authenticated;
grant all on table public.sd_platform_feature_flags to service_role;

insert into public.sd_platform_feature_flags (key, enabled, description)
values (
  'player_development_copilot',
  false,
  'Enables AI-assisted coach and player Copilot experiences across Home Plate.'
)
on conflict (key) do nothing;

create or replace function public.sd_set_platform_feature_flag(
  p_actor_id uuid,
  p_key text,
  p_enabled boolean,
  p_request_id uuid
)
returns public.sd_platform_feature_flags
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_existing public.sd_platform_feature_flags%rowtype;
  v_updated public.sd_platform_feature_flags%rowtype;
begin
  if p_actor_id is null or not exists (
    select 1
    from public.sd_platform_admins administrator
    where administrator.user_id = p_actor_id
  ) then
    raise exception 'not_platform_admin' using errcode = '42501';
  end if;

  select *
  into v_existing
  from public.sd_platform_feature_flags flag
  where flag.key = p_key
  for update;

  if not found then
    raise exception 'platform_feature_not_found' using errcode = 'P0002';
  end if;

  if v_existing.last_request_id = p_request_id then
    return v_existing;
  end if;

  update public.sd_platform_feature_flags
  set enabled = p_enabled,
      last_request_id = p_request_id,
      updated_at = now(),
      updated_by = p_actor_id
  where key = p_key
  returning * into v_updated;

  insert into public.sd_platform_audit_logs (
    actor_id,
    action,
    target_type,
    target_id,
    details
  ) values (
    p_actor_id,
    'update_platform_feature_flag',
    'platform_feature_flag',
    p_key,
    pg_catalog.jsonb_build_object(
      'previous_enabled', v_existing.enabled,
      'new_enabled', v_updated.enabled,
      'request_id', p_request_id
    )
  );

  return v_updated;
end;
$$;

revoke all on function public.sd_set_platform_feature_flag(uuid, text, boolean, uuid)
  from public, anon, authenticated;
grant execute on function public.sd_set_platform_feature_flag(uuid, text, boolean, uuid)
  to service_role;
