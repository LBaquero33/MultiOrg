-- Auth hardening for parent invite acceptance and player-development controls.
-- Preconditions: sd_parent_invites, sd_parent_child_links, sd_org_memberships,
-- sd_training_staff_roles and sd_testing_field_definitions exist; org_id has
-- been added by 20260616000200_sd_core_org_scope. Existing rows are retained.
-- Pending legacy invitations without a hash, or with a null org, remain safely
-- unaccepted and must be reissued through parent-invites; this migration never
-- turns an old email-only link into a trusted acceptance.
-- Rollback: revoke/drop sd_issue_parent_invite, sd_accept_parent_invite and
-- sd_can_manage_player_development, restore prior policies only after a safe
-- replacement is ready. Do not restore the legacy email-only parent UPDATE.

begin;

alter table public.sd_parent_invites
  add column if not exists acceptance_token_hash bytea,
  add column if not exists acceptance_token_expires_at timestamptz;

alter table public.sd_parent_invites
  drop constraint if exists sd_parent_invites_acceptance_token_hash_size;
alter table public.sd_parent_invites
  add constraint sd_parent_invites_acceptance_token_hash_size
  check (acceptance_token_hash is null or octet_length(acceptance_token_hash) = 32);

create or replace function public.sd_can_manage_player_development(
  p_org_id uuid,
  p_actor_id uuid default auth.uid()
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_staff_kind text;
begin
  if p_org_id is null or p_actor_id is null then return false; end if;
  if auth.role() <> 'service_role' and p_actor_id is distinct from auth.uid() then
    return false;
  end if;
  select lower(m.role) into v_role
  from public.sd_org_memberships m
  where m.org_id = p_org_id and m.user_id = p_actor_id and m.status = 'active'
  limit 1;
  if v_role is null then return false; end if;
  if v_role in ('owner', 'admin') then return true; end if;
  if v_role <> 'coach' then return false; end if;
  if exists (
    select 1 from public.sd_training_staff_roles s
    where s.org_id = p_org_id and s.user_id = p_actor_id
      and s.status = 'active' and s.staff_kind = 'front_desk'
  ) then return false; end if;
  select s.staff_kind into v_staff_kind
  from public.sd_training_staff_roles s
  where s.org_id = p_org_id and s.user_id = p_actor_id and s.status = 'active'
  order by case s.staff_kind when 'trainer' then 1 else 2 end
  limit 1;
  return coalesce(v_staff_kind, 'trainer') = 'trainer';
end;
$$;
revoke all on function public.sd_can_manage_player_development(uuid, uuid)
  from public, anon;
grant execute on function public.sd_can_manage_player_development(uuid, uuid)
  to authenticated, service_role;

-- Keep direct REST table mutations aligned with the capability check used by
-- atomic program RPCs. Players retain their own testing-entry policy below;
-- staff managers must be active coaches/trainers or organization owner/admin.
drop policy if exists "sd_program_templates_insert" on public.sd_program_templates;
create policy "sd_program_templates_insert"
on public.sd_program_templates for insert to authenticated
with check (
  coach_id = auth.uid()
  and public.sd_can_manage_player_development(org_id)
);
drop policy if exists "sd_program_templates_update" on public.sd_program_templates;
create policy "sd_program_templates_update"
on public.sd_program_templates for update to authenticated
using (
  public.sd_can_manage_player_development(org_id)
  and (coach_id = auth.uid() or exists (
    select 1 from public.sd_org_memberships m
    where m.org_id = sd_program_templates.org_id and m.user_id = auth.uid()
      and m.status = 'active' and lower(m.role) in ('owner', 'admin')
  ))
)
with check (
  public.sd_can_manage_player_development(org_id)
  and (coach_id = auth.uid() or exists (
    select 1 from public.sd_org_memberships m
    where m.org_id = sd_program_templates.org_id and m.user_id = auth.uid()
      and m.status = 'active' and lower(m.role) in ('owner', 'admin')
  ))
);
drop policy if exists "sd_program_templates_delete" on public.sd_program_templates;
create policy "sd_program_templates_delete"
on public.sd_program_templates for delete to authenticated
using (
  public.sd_can_manage_player_development(org_id)
  and (coach_id = auth.uid() or exists (
    select 1 from public.sd_org_memberships m
    where m.org_id = sd_program_templates.org_id and m.user_id = auth.uid()
      and m.status = 'active' and lower(m.role) in ('owner', 'admin')
  ))
);

drop policy if exists "sd_program_days_write" on public.sd_program_days;
create policy "sd_program_days_write"
on public.sd_program_days for all to authenticated
using (
  exists (
    select 1 from public.sd_program_templates t
    where t.id = sd_program_days.template_id
      and public.sd_can_manage_player_development(t.org_id)
      and (t.coach_id = auth.uid() or exists (
        select 1 from public.sd_org_memberships m
        where m.org_id = t.org_id and m.user_id = auth.uid()
          and m.status = 'active' and lower(m.role) in ('owner', 'admin')
      ))
  )
)
with check (
  exists (
    select 1 from public.sd_program_templates t
    where t.id = sd_program_days.template_id
      and public.sd_can_manage_player_development(t.org_id)
      and (t.coach_id = auth.uid() or exists (
        select 1 from public.sd_org_memberships m
        where m.org_id = t.org_id and m.user_id = auth.uid()
          and m.status = 'active' and lower(m.role) in ('owner', 'admin')
      ))
  )
);

drop policy if exists "sd_assignments_insert" on public.sd_program_assignments;
create policy "sd_assignments_insert"
on public.sd_program_assignments for insert to authenticated
with check (
  coach_id = auth.uid()
  and public.sd_can_manage_player_development(org_id)
  and exists (
    select 1 from public.sd_program_templates t
    where t.id = sd_program_assignments.template_id
      and t.org_id = sd_program_assignments.org_id
  )
  and (
    exists (
      select 1 from public.sd_org_memberships m
      where m.org_id = sd_program_assignments.org_id and m.user_id = auth.uid()
        and m.status = 'active' and lower(m.role) in ('owner', 'admin')
    )
    or (player_id is not null and public.sd_can_manage_team_player(org_id, player_id))
    or (war_athlete_id is not null and exists (
      select 1 from public.sd_organization_athletes athlete
      where athlete.id = sd_program_assignments.war_athlete_id
        and athlete.org_id = sd_program_assignments.org_id
        and athlete.status in ('active', 'invited')
    ))
  )
  and (war_athlete_id is null or exists (
    select 1 from public.sd_organization_athletes athlete
    where athlete.id = sd_program_assignments.war_athlete_id
      and athlete.org_id = sd_program_assignments.org_id
      and athlete.status in ('active', 'invited')
  ))
);
drop policy if exists "sd_assignments_update" on public.sd_program_assignments;
create policy "sd_assignments_update"
on public.sd_program_assignments for update to authenticated
using (
  public.sd_can_manage_player_development(org_id)
  and exists (
    select 1 from public.sd_program_templates t
    where t.id = sd_program_assignments.template_id
      and t.org_id = sd_program_assignments.org_id
  )
  and (coach_id = auth.uid() or exists (
    select 1 from public.sd_org_memberships m
    where m.org_id = sd_program_assignments.org_id and m.user_id = auth.uid()
      and m.status = 'active' and lower(m.role) in ('owner', 'admin')
  ))
  and (
    exists (
      select 1 from public.sd_org_memberships m
      where m.org_id = sd_program_assignments.org_id and m.user_id = auth.uid()
        and m.status = 'active' and lower(m.role) in ('owner', 'admin')
    )
    or (player_id is not null and public.sd_can_manage_team_player(org_id, player_id))
    or (war_athlete_id is not null and exists (
      select 1 from public.sd_organization_athletes athlete
      where athlete.id = sd_program_assignments.war_athlete_id
        and athlete.org_id = sd_program_assignments.org_id
        and athlete.status in ('active', 'invited')
    ))
  )
)
with check (
  public.sd_can_manage_player_development(org_id)
  and exists (
    select 1 from public.sd_program_templates t
    where t.id = sd_program_assignments.template_id
      and t.org_id = sd_program_assignments.org_id
  )
  and (coach_id = auth.uid() or exists (
    select 1 from public.sd_org_memberships m
    where m.org_id = sd_program_assignments.org_id and m.user_id = auth.uid()
      and m.status = 'active' and lower(m.role) in ('owner', 'admin')
  ))
  and (
    exists (
      select 1 from public.sd_org_memberships m
      where m.org_id = sd_program_assignments.org_id and m.user_id = auth.uid()
        and m.status = 'active' and lower(m.role) in ('owner', 'admin')
    )
    or (player_id is not null and public.sd_can_manage_team_player(org_id, player_id))
    or (war_athlete_id is not null and exists (
      select 1 from public.sd_organization_athletes athlete
      where athlete.id = sd_program_assignments.war_athlete_id
        and athlete.org_id = sd_program_assignments.org_id
        and athlete.status in ('active', 'invited')
    ))
  )
  and (war_athlete_id is null or exists (
    select 1 from public.sd_organization_athletes athlete
    where athlete.id = sd_program_assignments.war_athlete_id
      and athlete.org_id = sd_program_assignments.org_id
      and athlete.status in ('active', 'invited')
  ))
);

-- Custom field definitions are organization-wide controls, so require the
-- manager capability and reject front-desk staff even if legacy coach role
-- membership remains active.
drop policy if exists "testing fields managed by organization staff"
  on public.sd_testing_field_definitions;
create policy "testing fields managed by player-development managers"
on public.sd_testing_field_definitions for all to authenticated
using (public.sd_can_manage_player_development(org_id))
with check (public.sd_can_manage_player_development(org_id));

drop policy if exists "sd_testing_write_coach" on public.sd_testing_entries;
create policy "sd_testing_write_coach"
on public.sd_testing_entries for all to authenticated
using (
  public.sd_can_manage_player_development(org_id)
  and (
    exists (
      select 1 from public.sd_org_memberships m
      where m.org_id = sd_testing_entries.org_id and m.user_id = auth.uid()
        and m.status = 'active' and lower(m.role) in ('owner', 'admin')
    )
    or public.sd_can_manage_team_player(org_id, player_id)
  )
)
with check (
  public.sd_can_manage_player_development(org_id)
  and (
    exists (
      select 1 from public.sd_org_memberships m
      where m.org_id = sd_testing_entries.org_id and m.user_id = auth.uid()
        and m.status = 'active' and lower(m.role) in ('owner', 'admin')
    )
    or public.sd_can_manage_team_player(org_id, player_id)
  )
);

-- Pending invites are not readable or mutable by an email-matching account.
-- A high-entropy, single-use token is delivered out of band and its hash is
-- accepted only by the RPC below; table child/org binding remains immutable.
drop policy if exists "sd_parent_invites_parent_select" on public.sd_parent_invites;
drop policy if exists "sd_parent_invites_parent_accept" on public.sd_parent_invites;
drop policy if exists "sd_parent_invites_coach_update" on public.sd_parent_invites;
-- Only the service-only issue RPC may choose a token hash; a client-created
-- token would bypass the required out-of-band mailbox delivery.
drop policy if exists "sd_parent_invites_coach_insert" on public.sd_parent_invites;
revoke insert, update on public.sd_parent_invites from authenticated;

create or replace function public.sd_guard_parent_invite_binding()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.accepted_at is not null then
    raise exception using errcode = '42501', message = 'parent_invite_already_accepted';
  end if;
  if new.id is distinct from old.id
     or new.email_norm is distinct from old.email_norm
     or new.child_id is distinct from old.child_id
     or new.org_id is distinct from old.org_id
     or new.invited_by is distinct from old.invited_by
     or new.relationship is distinct from old.relationship
     or new.created_at is distinct from old.created_at then
    raise exception using errcode = '42501', message = 'parent_invite_binding_immutable';
  end if;
  if (new.parent_id is distinct from old.parent_id or new.accepted_at is distinct from old.accepted_at)
     and current_setting('app.accept_parent_invite', true) is distinct from 'on' then
    raise exception using errcode = '42501', message = 'parent_invite_acceptance_rpc_required';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_sd_guard_parent_invite_binding on public.sd_parent_invites;
create trigger trg_sd_guard_parent_invite_binding
before update on public.sd_parent_invites
for each row execute function public.sd_guard_parent_invite_binding();

create or replace function public.sd_accept_parent_invite(
  p_invite_id uuid,
  p_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, extensions, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_invite public.sd_parent_invites%rowtype;
  v_child_membership public.sd_org_memberships%rowtype;
begin
  if v_actor is null or v_email = '' then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_token is null or length(p_token) < 32 or length(p_token) > 256 then
    raise exception using errcode = '42501', message = 'parent_invite_token_invalid';
  end if;
  select * into v_invite
  from public.sd_parent_invites
  where id = p_invite_id
  for update;
  if not found or v_invite.accepted_at is not null or v_invite.parent_id is not null
     or v_invite.email_norm <> v_email
     or v_invite.org_id is null
     or v_invite.acceptance_token_hash is null
     or v_invite.acceptance_token_expires_at is null
     or v_invite.acceptance_token_expires_at <= now()
     or v_invite.acceptance_token_hash <> extensions.digest(convert_to(p_token, 'UTF8'), 'sha256') then
    raise exception using errcode = '42501', message = 'parent_invite_invalid_or_expired';
  end if;
  select * into v_child_membership
  from public.sd_org_memberships
  where org_id = v_invite.org_id and user_id = v_invite.child_id
  for share;
  if not found or v_child_membership.status <> 'active'
     or lower(v_child_membership.role) <> 'player' then
    raise exception using errcode = '42501', message = 'parent_invite_child_not_in_org';
  end if;
  perform set_config('app.accept_parent_invite', 'on', true);
  update public.sd_parent_invites
  set parent_id = v_actor,
      accepted_at = now(),
      acceptance_token_hash = null,
      acceptance_token_expires_at = null
  where id = v_invite.id;
  return jsonb_build_object('accepted', true, 'org_id', v_invite.org_id,
    'child_id', v_invite.child_id);
end;
$$;
revoke all on function public.sd_accept_parent_invite(uuid, text)
  from public, anon;
grant execute on function public.sd_accept_parent_invite(uuid, text)
  to authenticated;

create or replace function public.sd_issue_parent_invite(
  p_org_id uuid,
  p_child_id uuid,
  p_email_norm text,
  p_relationship text,
  p_invited_by uuid,
  p_token_hash bytea,
  p_expires_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_id uuid;
begin
  if auth.role() <> 'service_role' then
    raise exception using errcode = '42501', message = 'service_role_required';
  end if;
  if p_org_id is null or p_child_id is null or p_invited_by is null
     or p_email_norm is null
     or p_email_norm !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
     or p_token_hash is null or octet_length(p_token_hash) <> 32
     or p_expires_at is null or p_expires_at <= now()
     or p_expires_at > now() + interval '14 days'
     or coalesce(char_length(p_relationship), 0) > 80 then
    raise exception using errcode = '22023', message = 'parent_invite_invalid';
  end if;
  if not public.sd_can_manage_player_development(p_org_id, p_invited_by) then
    raise exception using errcode = '42501', message = 'parent_invite_actor_not_authorized';
  end if;
  if not exists (
    select 1 from public.sd_org_memberships m
    where m.org_id = p_org_id and m.user_id = p_child_id
      and m.status = 'active' and lower(m.role) = 'player'
  ) then
    raise exception using errcode = '42501', message = 'parent_invite_child_not_in_org';
  end if;
  insert into public.sd_parent_invites(
    org_id, email_norm, child_id, invited_by, relationship,
    acceptance_token_hash, acceptance_token_expires_at
  ) values (
    p_org_id, lower(btrim(p_email_norm)), p_child_id, p_invited_by,
    nullif(btrim(p_relationship), ''), p_token_hash, p_expires_at
  ) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.sd_issue_parent_invite(uuid, uuid, text, text, uuid, bytea, timestamptz)
  from public, anon, authenticated;
grant execute on function public.sd_issue_parent_invite(uuid, uuid, text, text, uuid, bytea, timestamptz)
  to service_role;

create or replace function public.sd_on_parent_invite_accept()
returns trigger
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_parent_membership public.sd_org_memberships%rowtype;
  v_existing_link_org uuid;
begin
  if new.accepted_at is not null and new.parent_id is not null then
    if new.org_id is null then
      raise exception using errcode = '23502', message = 'parent_invite_org_required';
    end if;
    perform 1 from public.sd_org_memberships m
    where m.org_id = new.org_id and m.user_id = new.child_id
      and m.status = 'active' and lower(m.role) = 'player'
    for share;
    if not found then
      raise exception using errcode = '42501', message = 'parent_invite_child_not_in_org';
    end if;
    select * into v_parent_membership
    from public.sd_org_memberships m
    where m.org_id = new.org_id and m.user_id = new.parent_id
    for update;
    if not found then
      insert into public.sd_org_memberships(org_id, user_id, role, status, created_by)
      values (new.org_id, new.parent_id, 'parent', 'active', new.invited_by);
    elsif v_parent_membership.status <> 'active' then
      raise exception using errcode = '42501', message = 'parent_org_membership_disabled';
    elsif lower(v_parent_membership.role) <> 'parent' then
      raise exception using errcode = '42501', message = 'parent_org_membership_role_conflict';
    end if;
    perform pg_advisory_xact_lock(hashtextextended(
      new.parent_id::text || ':' || new.child_id::text, 0
    ));
    select l.org_id into v_existing_link_org
    from public.sd_parent_child_links l
    where l.parent_id = new.parent_id and l.child_id = new.child_id
    for update;
    if found and v_existing_link_org is distinct from new.org_id then
      raise exception using errcode = '42501', message = 'parent_link_org_conflict';
    end if;
    insert into public.sd_parent_child_links(
      parent_id, child_id, org_id, relationship, created_by
    ) values (
      new.parent_id, new.child_id, new.org_id, new.relationship, new.invited_by
    )
    on conflict (parent_id, child_id) do nothing;
  end if;
  return new;
end;
$$;

commit;
