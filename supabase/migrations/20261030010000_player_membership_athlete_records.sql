-- Facility-style organizations (training facility, independent trainer, hybrid
-- academy) scope player development through sd_organization_athletes. A player
-- membership without a matching athlete record left the player's own workspace
-- empty. Keep the two in step: every active player membership in a non-team
-- organization gets an athlete record linked to that account.
--
-- Rollback: drop trigger trg_sd_org_memberships_player_athlete on
-- public.sd_org_memberships; drop function public.sd_ensure_player_athlete_record();
-- (backfilled rows are ordinary athlete records and can stay).

create or replace function public.sd_ensure_player_athlete_record()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_type text;
  v_name text;
begin
  if new.role <> 'player' or new.status <> 'active' then
    return new;
  end if;

  select organization_type into v_org_type from public.sd_orgs where id = new.org_id;
  if v_org_type is null or v_org_type = 'team_program' then
    return new;
  end if;

  select coalesce(
           nullif(btrim(p.full_name), ''),
           nullif(split_part(u.email, '@', 1), ''),
           'Athlete'
         )
    into v_name
    from auth.users u
    left join public.profiles p on p.id = u.id
   where u.id = new.user_id;

  insert into public.sd_organization_athletes (org_id, athlete_user_id, display_name, status, created_by)
  values (new.org_id, new.user_id, left(coalesce(v_name, 'Athlete'), 160), 'active', new.created_by)
  on conflict (org_id, athlete_user_id) do nothing;

  return new;
end;
$$;

revoke all on function public.sd_ensure_player_athlete_record() from public, anon, authenticated;

drop trigger if exists trg_sd_org_memberships_player_athlete on public.sd_org_memberships;
create trigger trg_sd_org_memberships_player_athlete
  after insert or update of role, status on public.sd_org_memberships
  for each row execute function public.sd_ensure_player_athlete_record();

-- Backfill existing active player memberships that have no athlete record.
insert into public.sd_organization_athletes (org_id, athlete_user_id, display_name, status, created_by)
select m.org_id,
       m.user_id,
       left(coalesce(nullif(btrim(p.full_name), ''), nullif(split_part(u.email, '@', 1), ''), 'Athlete'), 160),
       'active',
       m.created_by
  from public.sd_org_memberships m
  join public.sd_orgs o on o.id = m.org_id
  join auth.users u on u.id = m.user_id
  left join public.profiles p on p.id = m.user_id
 where m.role = 'player'
   and m.status = 'active'
   and o.organization_type <> 'team_program'
on conflict (org_id, athlete_user_id) do nothing;
