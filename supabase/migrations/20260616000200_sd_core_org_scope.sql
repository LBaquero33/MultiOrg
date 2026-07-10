-- Multi-org tenant scope for the core Self Development feature tables.
--
-- This migration is intentionally additive and backfills existing single-org rows
-- into the first available org so local/dev data keeps working.

create extension if not exists pgcrypto;

create or replace function public.sd_default_org_id()
returns uuid
language sql
stable
security definer
set search_path to 'public'
as $$
  select id from public.sd_orgs order by created_at asc, name asc limit 1;
$$;

create or replace function public.sd_user_primary_org_id(target_user_id uuid)
returns uuid
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(
    (
      select m.org_id
      from public.sd_org_memberships m
      where m.user_id = target_user_id
        and m.status = 'active'
      order by case m.role when 'owner' then 0 when 'coach' then 1 when 'player' then 2 else 3 end,
               m.created_at asc
      limit 1
    ),
    public.sd_default_org_id()
  );
$$;

-- Core training/performance tables.
alter table public.sd_program_templates add column if not exists org_id uuid references public.sd_orgs(id) on delete cascade;
alter table public.sd_program_assignments add column if not exists org_id uuid references public.sd_orgs(id) on delete cascade;
alter table public.sd_daily_logs add column if not exists org_id uuid references public.sd_orgs(id) on delete cascade;
alter table public.sd_strength_logs add column if not exists org_id uuid references public.sd_orgs(id) on delete cascade;
alter table public.sd_testing_entries add column if not exists org_id uuid references public.sd_orgs(id) on delete cascade;
alter table public.sd_bp_sessions add column if not exists org_id uuid references public.sd_orgs(id) on delete cascade;
alter table public.sd_player_onboarding add column if not exists org_id uuid references public.sd_orgs(id) on delete cascade;
alter table public.sd_exercise_library add column if not exists org_id uuid references public.sd_orgs(id) on delete cascade;
alter table public.sd_access_entitlements add column if not exists org_id uuid references public.sd_orgs(id) on delete cascade;

-- Parent/account tables.
alter table public.sd_parent_invites add column if not exists org_id uuid references public.sd_orgs(id) on delete cascade;
alter table public.sd_parent_child_links add column if not exists org_id uuid references public.sd_orgs(id) on delete cascade;
alter table public.sd_payment_requests add column if not exists org_id uuid references public.sd_orgs(id) on delete cascade;
alter table public.sd_parent_invite_requests add column if not exists org_id uuid references public.sd_orgs(id) on delete cascade;
alter table public.sd_parent_codes add column if not exists org_id uuid references public.sd_orgs(id) on delete cascade;

-- Chat tables.
alter table public.sd_chat_channels add column if not exists org_id uuid references public.sd_orgs(id) on delete cascade;
alter table public.sd_chat_memberships add column if not exists org_id uuid references public.sd_orgs(id) on delete cascade;
alter table public.sd_chat_messages add column if not exists org_id uuid references public.sd_orgs(id) on delete cascade;

-- Backfill training/performance.
update public.sd_program_templates
set org_id = public.sd_user_primary_org_id(coach_id)
where org_id is null;

update public.sd_program_assignments a
set org_id = coalesce(t.org_id, public.sd_user_primary_org_id(a.coach_id), public.sd_user_primary_org_id(a.player_id))
from public.sd_program_templates t
where a.template_id = t.id
  and a.org_id is null;

update public.sd_daily_logs
set org_id = public.sd_user_primary_org_id(player_id)
where org_id is null;

update public.sd_strength_logs
set org_id = coalesce(
  (select org_id from public.sd_program_assignments a where a.id = sd_strength_logs.assignment_id),
  public.sd_user_primary_org_id(player_id)
)
where org_id is null;

update public.sd_testing_entries
set org_id = public.sd_user_primary_org_id(player_id)
where org_id is null;

update public.sd_bp_sessions
set org_id = public.sd_user_primary_org_id(player_id)
where org_id is null;

update public.sd_player_onboarding
set org_id = public.sd_user_primary_org_id(player_id)
where org_id is null;

update public.sd_exercise_library
set org_id = public.sd_user_primary_org_id(coach_id)
where org_id is null;

update public.sd_access_entitlements
set org_id = public.sd_user_primary_org_id(user_id)
where org_id is null;

-- Backfill parent/account.
update public.sd_parent_invites
set org_id = coalesce(public.sd_user_primary_org_id(invited_by), public.sd_user_primary_org_id(child_id))
where org_id is null;

update public.sd_parent_child_links
set org_id = coalesce(public.sd_user_primary_org_id(created_by), public.sd_user_primary_org_id(child_id), public.sd_user_primary_org_id(parent_id))
where org_id is null;

update public.sd_payment_requests
set org_id = coalesce(public.sd_user_primary_org_id(child_id), public.sd_user_primary_org_id(payer_id))
where org_id is null;

update public.sd_parent_invite_requests
set org_id = public.sd_default_org_id()
where org_id is null;

update public.sd_parent_codes
set org_id = public.sd_user_primary_org_id(child_id)
where org_id is null;

-- Backfill chat.
update public.sd_chat_channels
set org_id = coalesce(public.sd_user_primary_org_id(created_by), public.sd_default_org_id())
where org_id is null;

update public.sd_chat_memberships m
set org_id = coalesce(c.org_id, public.sd_user_primary_org_id(m.user_id))
from public.sd_chat_channels c
where m.channel_id = c.id
  and m.org_id is null;

update public.sd_chat_messages msg
set org_id = coalesce(c.org_id, public.sd_user_primary_org_id(msg.sender_id))
from public.sd_chat_channels c
where msg.channel_id = c.id
  and msg.org_id is null;

-- Keep org_id synced from parent rows.
create or replace function public.sd_set_assignment_org_id()
returns trigger
language plpgsql
as $$
begin
  if new.org_id is null then
    select org_id into new.org_id from public.sd_program_templates where id = new.template_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sd_program_assignments_org_id on public.sd_program_assignments;
create trigger trg_sd_program_assignments_org_id
before insert or update of template_id, org_id
on public.sd_program_assignments
for each row execute function public.sd_set_assignment_org_id();

create or replace function public.sd_set_chat_child_org_id()
returns trigger
language plpgsql
as $$
begin
  if new.org_id is null then
    select org_id into new.org_id from public.sd_chat_channels where id = new.channel_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sd_chat_memberships_org_id on public.sd_chat_memberships;
create trigger trg_sd_chat_memberships_org_id
before insert or update of channel_id, org_id
on public.sd_chat_memberships
for each row execute function public.sd_set_chat_child_org_id();

drop trigger if exists trg_sd_chat_messages_org_id on public.sd_chat_messages;
create trigger trg_sd_chat_messages_org_id
before insert or update of channel_id, org_id
on public.sd_chat_messages
for each row execute function public.sd_set_chat_child_org_id();

-- Unique constraints that were single-org should include org_id now.
alter table public.sd_daily_logs drop constraint if exists sd_daily_logs_player_id_log_date_key;
create unique index if not exists ux_sd_daily_logs_org_player_date
on public.sd_daily_logs(org_id, player_id, log_date);

alter table public.sd_testing_entries drop constraint if exists sd_testing_entries_player_id_entry_date_key;
create unique index if not exists ux_sd_testing_entries_org_player_date
on public.sd_testing_entries(org_id, player_id, entry_date);

alter table public.sd_bp_sessions drop constraint if exists sd_bp_sessions_player_id_session_date_source_reps_type_key;
create unique index if not exists ux_sd_bp_sessions_org_player_date_source_reps
on public.sd_bp_sessions(org_id, player_id, session_date, source, reps_type);

drop index if exists idx_sd_exercise_library_unique;
create unique index if not exists ux_sd_exercise_library_org_coach_name
on public.sd_exercise_library(org_id, coach_id, name_norm);

-- Tenant indexes.
create index if not exists idx_sd_program_templates_org on public.sd_program_templates(org_id, coach_id);
create index if not exists idx_sd_program_assignments_org_player on public.sd_program_assignments(org_id, player_id, ended_at);
create index if not exists idx_sd_daily_logs_org_player_date on public.sd_daily_logs(org_id, player_id, log_date);
create index if not exists idx_sd_strength_logs_org_player_date on public.sd_strength_logs(org_id, player_id, log_date);
create index if not exists idx_sd_testing_entries_org_player_date on public.sd_testing_entries(org_id, player_id, entry_date);
create index if not exists idx_sd_bp_sessions_org_player_date on public.sd_bp_sessions(org_id, player_id, session_date);
create index if not exists idx_sd_player_onboarding_org_player on public.sd_player_onboarding(org_id, player_id);
create index if not exists idx_sd_parent_invites_org_child on public.sd_parent_invites(org_id, child_id);
create index if not exists idx_sd_parent_child_links_org_parent on public.sd_parent_child_links(org_id, parent_id, child_id);
create index if not exists idx_sd_payment_requests_org_child on public.sd_payment_requests(org_id, child_id);
create index if not exists idx_sd_parent_codes_org_child on public.sd_parent_codes(org_id, child_id);
create index if not exists idx_sd_chat_channels_org on public.sd_chat_channels(org_id, channel_type);
create index if not exists idx_sd_chat_memberships_org_user on public.sd_chat_memberships(org_id, user_id);
create index if not exists idx_sd_chat_messages_org_channel_created on public.sd_chat_messages(org_id, channel_id, created_at desc);

-- Org-aware helper for parent links.
create or replace function public.sd_is_linked_parent_in_org(parent_uid uuid, child_uid uuid, target_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from public.sd_parent_child_links l
    where l.parent_id = parent_uid
      and l.child_id = child_uid
      and l.org_id = target_org_id
  );
$$;

-- Core RLS: tenant membership first, legacy null org fallback second.
drop policy if exists "sd_program_templates_select" on public.sd_program_templates;
create policy "sd_program_templates_select"
on public.sd_program_templates
for select
using (
  coach_id = auth.uid()
  or public.sd_is_org_staff(org_id)
  or exists (
    select 1 from public.sd_program_assignments a
    where a.template_id = sd_program_templates.id
      and a.player_id = auth.uid()
      and a.ended_at is null
  )
);

drop policy if exists "sd_program_templates_insert" on public.sd_program_templates;
create policy "sd_program_templates_insert"
on public.sd_program_templates
for insert
with check (coach_id = auth.uid() and public.sd_is_org_staff(org_id));

drop policy if exists "sd_program_templates_update" on public.sd_program_templates;
create policy "sd_program_templates_update"
on public.sd_program_templates
for update
using (coach_id = auth.uid() and public.sd_is_org_staff(org_id))
with check (coach_id = auth.uid() and public.sd_is_org_staff(org_id));

drop policy if exists "sd_assignments_select" on public.sd_program_assignments;
create policy "sd_assignments_select"
on public.sd_program_assignments
for select
using (
  player_id = auth.uid()
  or public.sd_is_org_staff(org_id)
);

drop policy if exists "sd_assignments_insert" on public.sd_program_assignments;
create policy "sd_assignments_insert"
on public.sd_program_assignments
for insert
with check (coach_id = auth.uid() and public.sd_is_org_staff(org_id));

drop policy if exists "sd_assignments_update" on public.sd_program_assignments;
create policy "sd_assignments_update"
on public.sd_program_assignments
for update
using (coach_id = auth.uid() and public.sd_is_org_staff(org_id))
with check (coach_id = auth.uid() and public.sd_is_org_staff(org_id));

drop policy if exists "sd_daily_logs_select" on public.sd_daily_logs;
create policy "sd_daily_logs_select"
on public.sd_daily_logs
for select
using (
  player_id = auth.uid()
  or public.sd_is_org_staff(org_id)
  or public.sd_is_linked_parent_in_org(auth.uid(), player_id, org_id)
);

drop policy if exists "sd_strength_logs_select" on public.sd_strength_logs;
create policy "sd_strength_logs_select"
on public.sd_strength_logs
for select
using (
  player_id = auth.uid()
  or public.sd_is_org_staff(org_id)
  or public.sd_is_linked_parent_in_org(auth.uid(), player_id, org_id)
);

drop policy if exists "sd_testing_select" on public.sd_testing_entries;
create policy "sd_testing_select"
on public.sd_testing_entries
for select
using (
  player_id = auth.uid()
  or public.sd_is_org_staff(org_id)
  or public.sd_is_linked_parent_in_org(auth.uid(), player_id, org_id)
);

drop policy if exists "sd_bp_sessions_select" on public.sd_bp_sessions;
create policy "sd_bp_sessions_select"
on public.sd_bp_sessions
for select
using (
  player_id = auth.uid()
  or public.sd_is_org_staff(org_id)
  or public.sd_is_linked_parent_in_org(auth.uid(), player_id, org_id)
);

drop policy if exists "sd_bp_events_select" on public.sd_bp_events;
create policy "sd_bp_events_select"
on public.sd_bp_events
for select
using (
  exists (
    select 1 from public.sd_bp_sessions s
    where s.id = sd_bp_events.session_id
      and (
        s.player_id = auth.uid()
        or public.sd_is_org_staff(s.org_id)
        or public.sd_is_linked_parent_in_org(auth.uid(), s.player_id, s.org_id)
      )
  )
);

drop policy if exists "sd_onboarding_select_coach_all" on public.sd_player_onboarding;
create policy "sd_onboarding_select_coach_all"
on public.sd_player_onboarding
for select
using (public.sd_is_org_staff(org_id));

drop policy if exists "sd_exercise_library_select" on public.sd_exercise_library;
create policy "sd_exercise_library_select"
on public.sd_exercise_library
for select
using (coach_id = auth.uid() and public.sd_is_org_staff(org_id));

drop policy if exists "sd_exercise_library_write" on public.sd_exercise_library;
create policy "sd_exercise_library_write"
on public.sd_exercise_library
for all
using (coach_id = auth.uid() and public.sd_is_org_staff(org_id))
with check (coach_id = auth.uid() and public.sd_is_org_staff(org_id));

-- Parent/billing policies.
drop policy if exists "sd_parent_invites_coach_select" on public.sd_parent_invites;
create policy "sd_parent_invites_coach_select"
on public.sd_parent_invites
for select
using (public.sd_is_org_staff(org_id));

drop policy if exists "sd_parent_invites_coach_insert" on public.sd_parent_invites;
create policy "sd_parent_invites_coach_insert"
on public.sd_parent_invites
for insert
with check (public.sd_is_org_staff(org_id) and invited_by = auth.uid());

drop policy if exists "sd_parent_invites_coach_update" on public.sd_parent_invites;
create policy "sd_parent_invites_coach_update"
on public.sd_parent_invites
for update
using (public.sd_is_org_staff(org_id))
with check (public.sd_is_org_staff(org_id));

drop policy if exists "sd_parent_child_links_coach_all" on public.sd_parent_child_links;
create policy "sd_parent_child_links_coach_all"
on public.sd_parent_child_links
for all
using (public.sd_is_org_staff(org_id))
with check (public.sd_is_org_staff(org_id));

drop policy if exists "sd_payment_requests_coach_select" on public.sd_payment_requests;
create policy "sd_payment_requests_coach_select"
on public.sd_payment_requests
for select
using (public.sd_is_org_staff(org_id));

drop policy if exists "sd_payment_requests_coach_update" on public.sd_payment_requests;
create policy "sd_payment_requests_coach_update"
on public.sd_payment_requests
for update
using (public.sd_is_org_staff(org_id))
with check (public.sd_is_org_staff(org_id));

-- Chat policies.
drop policy if exists "sd_chat_channels_select" on public.sd_chat_channels;
create policy "sd_chat_channels_select"
on public.sd_chat_channels
for select
to authenticated
using (
  public.sd_chat_is_member(id, auth.uid())
  or (
    channel_type = 'announcement'
    and public.sd_is_org_member(org_id)
    and (
      audience = 'all'
      or (audience = 'players' and exists (
        select 1 from public.sd_org_memberships m
        where m.org_id = sd_chat_channels.org_id
          and m.user_id = auth.uid()
          and m.status = 'active'
          and m.role = 'player'
      ))
    )
  )
);

drop policy if exists "sd_chat_channels_insert" on public.sd_chat_channels;
create policy "sd_chat_channels_insert"
on public.sd_chat_channels
for insert
to authenticated
with check (
  created_by = auth.uid()
  and public.sd_is_org_member(org_id)
  and (
    channel_type in ('dm','group')
    or (channel_type = 'announcement' and public.sd_is_org_staff(org_id))
  )
);

drop policy if exists "sd_chat_channels_update_admin" on public.sd_chat_channels;
create policy "sd_chat_channels_update_admin"
on public.sd_chat_channels
for update
to authenticated
using (public.sd_chat_is_admin(id, auth.uid()) or public.sd_is_org_staff(org_id))
with check (public.sd_chat_is_admin(id, auth.uid()) or public.sd_is_org_staff(org_id));

drop policy if exists "sd_chat_memberships_select" on public.sd_chat_memberships;
create policy "sd_chat_memberships_select"
on public.sd_chat_memberships
for select
to authenticated
using (
  public.sd_chat_is_member(channel_id, auth.uid())
  or public.sd_is_org_staff(org_id)
);

drop policy if exists "sd_chat_messages_select" on public.sd_chat_messages;
create policy "sd_chat_messages_select"
on public.sd_chat_messages
for select
to authenticated
using (
  exists (
    select 1 from public.sd_chat_channels c
    where c.id = sd_chat_messages.channel_id
      and (
        public.sd_chat_is_member(c.id, auth.uid())
        or (
          c.channel_type = 'announcement'
          and public.sd_is_org_member(c.org_id)
          and (
            c.audience = 'all'
            or (c.audience = 'players' and exists (
              select 1 from public.sd_org_memberships m
              where m.org_id = c.org_id
                and m.user_id = auth.uid()
                and m.status = 'active'
                and m.role = 'player'
            ))
          )
        )
      )
  )
);

drop policy if exists "sd_chat_messages_insert" on public.sd_chat_messages;
create policy "sd_chat_messages_insert"
on public.sd_chat_messages
for insert
to authenticated
with check (
  sender_id = auth.uid()
  and exists (
    select 1 from public.sd_chat_channels c
    where c.id = sd_chat_messages.channel_id
      and c.org_id = sd_chat_messages.org_id
      and (
        (c.channel_type in ('dm','group') and public.sd_chat_is_member(c.id, auth.uid()))
        or (c.channel_type = 'announcement' and public.sd_is_org_staff(c.org_id))
      )
  )
);

-- Org-aware chat helpers.
create or replace function public.sd_get_or_create_dm(other_user_id uuid, target_org_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  me uuid;
  a text;
  b text;
  k text;
  ch uuid;
begin
  me := auth.uid();
  if me is null then
    raise exception 'not_authenticated';
  end if;
  if other_user_id is null then
    raise exception 'missing_other_user';
  end if;
  if other_user_id = me then
    raise exception 'cannot_dm_self';
  end if;
  if not public.sd_is_org_member(target_org_id) then
    raise exception 'not_authorized';
  end if;
  if not exists (
    select 1 from public.sd_org_memberships m
    where m.org_id = target_org_id
      and m.user_id = other_user_id
      and m.status = 'active'
  ) then
    raise exception 'other_user_not_in_org';
  end if;

  a := least(me::text, other_user_id::text);
  b := greatest(me::text, other_user_id::text);
  k := target_org_id::text || ':' || a || ':' || b;

  select c.id into ch
  from public.sd_chat_channels c
  where c.org_id = target_org_id
    and c.channel_type = 'dm'
    and c.dm_key = k
  limit 1;

  if ch is null then
    insert into public.sd_chat_channels(org_id, channel_type, created_by, dm_key)
    values (target_org_id, 'dm', me, k)
    returning id into ch;

    insert into public.sd_chat_memberships(org_id, channel_id, user_id, member_role)
    values (target_org_id, ch, me, 'admin')
    on conflict do nothing;
    insert into public.sd_chat_memberships(org_id, channel_id, user_id, member_role)
    values (target_org_id, ch, other_user_id, 'member')
    on conflict do nothing;
  end if;

  return ch;
end;
$$;

revoke all on function public.sd_get_or_create_dm(uuid, uuid) from public;
grant execute on function public.sd_get_or_create_dm(uuid, uuid) to authenticated;

