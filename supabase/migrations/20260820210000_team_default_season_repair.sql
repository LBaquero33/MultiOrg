-- Ensure every team belongs to a valid organization season. The normalized
-- roster assignment RPCs intentionally reject seasonless teams.

insert into public.sd_seasons (
  organization_id,
  name,
  status,
  is_default
)
select
  organization.id,
  'Current Season',
  'active',
  true
from public.sd_orgs organization
where not exists (
  select 1
  from public.sd_seasons season
  where season.organization_id = organization.id
)
on conflict (organization_id, name) do nothing;
with ranked_seasons as (
  select
    season.id,
    season.organization_id,
    row_number() over (
      partition by season.organization_id
      order by
        case when season.status = 'active' then 0 else 1 end,
        season.start_date desc nulls last,
        season.created_at asc
    ) as rank
  from public.sd_seasons season
  where not exists (
    select 1
    from public.sd_seasons current_default
    where current_default.organization_id = season.organization_id
      and current_default.is_default
  )
)
update public.sd_seasons season
set is_default = true,
    updated_at = now()
from ranked_seasons ranked
where ranked.rank = 1
  and ranked.id = season.id;
update public.sd_teams team
set season_id = season.id
from public.sd_seasons season
where team.season_id is null
  and season.organization_id = team.org_id
  and season.is_default;
create or replace function public.sd_apply_team_default_season()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_season_id uuid;
begin
  if new.season_id is null then
    select season.id
      into v_season_id
    from public.sd_seasons season
    where season.organization_id = new.org_id
      and season.is_default
    limit 1;

    if v_season_id is null then
      select season.id
        into v_season_id
      from public.sd_seasons season
      where season.organization_id = new.org_id
      order by
        case when season.status = 'active' then 0 else 1 end,
        season.start_date desc nulls last,
        season.created_at asc
      limit 1;
    end if;

    if v_season_id is null then
      insert into public.sd_seasons (
        organization_id,
        name,
        status,
        is_default,
        created_by,
        updated_by
      ) values (
        new.org_id,
        'Current Season',
        'active',
        true,
        new.created_by,
        new.created_by
      )
      returning id into v_season_id;
    end if;

    new.season_id := v_season_id;
  end if;

  if not exists (
    select 1
    from public.sd_seasons season
    where season.id = new.season_id
      and season.organization_id = new.org_id
  ) then
    raise exception 'team_season_organization_mismatch' using errcode = '23503';
  end if;

  return new;
end;
$$;
drop trigger if exists sd_teams_apply_default_season on public.sd_teams;
create trigger sd_teams_apply_default_season
before insert or update of org_id, season_id on public.sd_teams
for each row execute function public.sd_apply_team_default_season();
revoke all on function public.sd_apply_team_default_season() from public, anon, authenticated;
grant execute on function public.sd_apply_team_default_season() to service_role;
