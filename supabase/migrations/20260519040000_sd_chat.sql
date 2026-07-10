-- Org-wide chat system: DMs + group DMs + announcements (coach-post-only).

create extension if not exists pgcrypto;

-- Channels
create table if not exists public.sd_chat_channels (
  id uuid primary key default gen_random_uuid(),
  channel_type text not null, -- dm|group|announcement
  title text,
  audience text, -- all|players (announcement only)
  created_by uuid references auth.users(id) on delete set null,
  -- dm uniqueness helper: deterministic key for the 2 participants, e.g. "{minUid}:{maxUid}"
  dm_key text,
  is_archived boolean not null default false,
  pinned_rank int,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Constraints
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'sd_chat_channels_type_chk') then
    alter table public.sd_chat_channels
      add constraint sd_chat_channels_type_chk
      check (channel_type in ('dm','group','announcement'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'sd_chat_channels_audience_chk') then
    alter table public.sd_chat_channels
      add constraint sd_chat_channels_audience_chk
      check (
        (channel_type <> 'announcement' and audience is null)
        or (channel_type = 'announcement' and audience in ('all','players'))
      );
  end if;
  if not exists (select 1 from pg_constraint where conname = 'sd_chat_channels_dm_key_chk') then
    alter table public.sd_chat_channels
      add constraint sd_chat_channels_dm_key_chk
      check (
        (channel_type <> 'dm' and dm_key is null)
        or (channel_type = 'dm' and dm_key is not null)
      );
  end if;
end $$;

-- Unique dm key (one DM per pair)
create unique index if not exists ux_sd_chat_channels_dm_key
on public.sd_chat_channels(dm_key)
where channel_type = 'dm';

-- Unique announcement titles (so bootstrap stays idempotent).
create unique index if not exists ux_sd_chat_channels_announcement_title
on public.sd_chat_channels(title)
where channel_type = 'announcement';

create index if not exists idx_sd_chat_channels_type on public.sd_chat_channels(channel_type, created_at desc);
create index if not exists idx_sd_chat_channels_pinned on public.sd_chat_channels(pinned_rank) where channel_type = 'announcement';

drop trigger if exists sd_chat_channels_touch on public.sd_chat_channels;
create trigger sd_chat_channels_touch
before update on public.sd_chat_channels
for each row execute function public.sd_touch_updated_at();

alter table public.sd_chat_channels enable row level security;

-- Memberships
create table if not exists public.sd_chat_memberships (
  channel_id uuid not null references public.sd_chat_channels(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  member_role text not null default 'member', -- member|admin
  joined_at timestamptz not null default now(),
  last_read_at timestamptz,
  muted boolean not null default false,
  primary key (channel_id, user_id)
);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'sd_chat_memberships_role_chk') then
    alter table public.sd_chat_memberships
      add constraint sd_chat_memberships_role_chk
      check (member_role in ('member','admin'));
  end if;
end $$;

create index if not exists idx_sd_chat_memberships_user on public.sd_chat_memberships(user_id, joined_at desc);
create index if not exists idx_sd_chat_memberships_channel on public.sd_chat_memberships(channel_id, joined_at desc);

alter table public.sd_chat_memberships enable row level security;

-- Prevent membership escalation or changing the composite key.
create or replace function public.sd_chat_guard_membership_update()
returns trigger
language plpgsql
as $$
begin
  if new.channel_id is distinct from old.channel_id or new.user_id is distinct from old.user_id then
    raise exception 'membership_key_change_not_allowed';
  end if;

  if new.member_role is distinct from old.member_role then
    -- Only coaches or existing channel admins can change roles.
    if not (public.sd_is_coach(auth.uid()) or public.sd_chat_is_admin(old.channel_id, auth.uid())) then
      raise exception 'membership_role_change_not_allowed';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sd_chat_guard_membership_update on public.sd_chat_memberships;
create trigger trg_sd_chat_guard_membership_update
before update on public.sd_chat_memberships
for each row execute function public.sd_chat_guard_membership_update();

-- Messages
create table if not exists public.sd_chat_messages (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.sd_chat_channels(id) on delete cascade,
  sender_id uuid references auth.users(id) on delete set null,
  body text not null,
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  deleted_at timestamptz
);

create index if not exists idx_sd_chat_messages_channel_created on public.sd_chat_messages(channel_id, created_at desc);

alter table public.sd_chat_messages enable row level security;

-- Prevent message sender/channel tampering on update.
create or replace function public.sd_chat_guard_message_update()
returns trigger
language plpgsql
as $$
begin
  if new.channel_id is distinct from old.channel_id then
    raise exception 'message_channel_change_not_allowed';
  end if;
  if new.sender_id is distinct from old.sender_id then
    raise exception 'message_sender_change_not_allowed';
  end if;
  if new.created_at is distinct from old.created_at then
    raise exception 'message_created_at_change_not_allowed';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sd_chat_guard_message_update on public.sd_chat_messages;
create trigger trg_sd_chat_guard_message_update
before update on public.sd_chat_messages
for each row execute function public.sd_chat_guard_message_update();

-- Helpers for RLS
create or replace function public.sd_is_player(uid uuid)
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = uid and p.role = 'player'
  );
$$;

create or replace function public.sd_chat_is_member(ch_id uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1 from public.sd_chat_memberships m
    where m.channel_id = ch_id and m.user_id = uid
  );
$$;

revoke all on function public.sd_chat_is_member(uuid, uuid) from public;
grant execute on function public.sd_chat_is_member(uuid, uuid) to anon, authenticated;

create or replace function public.sd_chat_is_admin(ch_id uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from public.sd_chat_channels c
    where c.id = ch_id
      and c.created_by = uid
  )
  or exists (
    select 1
    from public.sd_chat_memberships m
    where m.channel_id = ch_id and m.user_id = uid and m.member_role = 'admin'
  );
$$;

revoke all on function public.sd_chat_is_admin(uuid, uuid) from public;
grant execute on function public.sd_chat_is_admin(uuid, uuid) to anon, authenticated;

-- CHANNEL POLICIES
drop policy if exists "sd_chat_channels_select" on public.sd_chat_channels;
create policy "sd_chat_channels_select"
on public.sd_chat_channels
for select
to authenticated
using (
  public.sd_chat_is_member(id, auth.uid())
  or (
    channel_type = 'announcement'
    and (
      audience = 'all'
      or (audience = 'players' and public.sd_is_player(auth.uid()))
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
  and (
    channel_type in ('dm','group')
    or (channel_type = 'announcement' and public.sd_is_coach(auth.uid()))
  )
);

drop policy if exists "sd_chat_channels_update_admin" on public.sd_chat_channels;
create policy "sd_chat_channels_update_admin"
on public.sd_chat_channels
for update
to authenticated
using (public.sd_chat_is_admin(id, auth.uid()) or public.sd_is_coach(auth.uid()))
with check (public.sd_chat_is_admin(id, auth.uid()) or public.sd_is_coach(auth.uid()));

-- MEMBERSHIP POLICIES
drop policy if exists "sd_chat_memberships_select" on public.sd_chat_memberships;
create policy "sd_chat_memberships_select"
on public.sd_chat_memberships
for select
to authenticated
using (
  public.sd_chat_is_member(channel_id, auth.uid())
  or public.sd_is_coach(auth.uid())
);

-- Insert memberships:
-- - DM/group: only channel admin/creator (or coach) can add members.
-- - Announcement: a user can create their own membership row for read-state (last_read_at/muted).
drop policy if exists "sd_chat_memberships_insert" on public.sd_chat_memberships;
create policy "sd_chat_memberships_insert"
on public.sd_chat_memberships
for insert
to authenticated
with check (
  (
    public.sd_is_coach(auth.uid())
  )
  or (
    exists (select 1 from public.sd_chat_channels c where c.id = channel_id and c.channel_type in ('dm','group') and public.sd_chat_is_admin(c.id, auth.uid()))
  )
  or (
    user_id = auth.uid()
    and exists (
      select 1 from public.sd_chat_channels c
      where c.id = channel_id
        and c.channel_type = 'announcement'
        and (
          c.audience = 'all'
          or (c.audience = 'players' and public.sd_is_player(auth.uid()))
        )
    )
  )
);

-- Update memberships:
-- - user can update their own last_read_at + muted
-- - admin/coach can manage
drop policy if exists "sd_chat_memberships_update" on public.sd_chat_memberships;
create policy "sd_chat_memberships_update"
on public.sd_chat_memberships
for update
to authenticated
using (
  user_id = auth.uid()
  or public.sd_chat_is_admin(channel_id, auth.uid())
  or public.sd_is_coach(auth.uid())
)
with check (
  user_id = auth.uid()
  or public.sd_chat_is_admin(channel_id, auth.uid())
  or public.sd_is_coach(auth.uid())
);

drop policy if exists "sd_chat_memberships_delete_admin" on public.sd_chat_memberships;
create policy "sd_chat_memberships_delete_admin"
on public.sd_chat_memberships
for delete
to authenticated
using (public.sd_chat_is_admin(channel_id, auth.uid()) or public.sd_is_coach(auth.uid()));

-- MESSAGE POLICIES
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
          and (
            c.audience = 'all'
            or (c.audience = 'players' and public.sd_is_player(auth.uid()))
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
      and (
        (c.channel_type in ('dm','group') and public.sd_chat_is_member(c.id, auth.uid()))
        or (c.channel_type = 'announcement' and public.sd_is_coach(auth.uid()))
      )
  )
);

drop policy if exists "sd_chat_messages_update_own_or_coach" on public.sd_chat_messages;
create policy "sd_chat_messages_update_own_or_coach"
on public.sd_chat_messages
for update
to authenticated
using (sender_id = auth.uid() or public.sd_is_coach(auth.uid()))
with check (sender_id = auth.uid() or public.sd_is_coach(auth.uid()));

drop policy if exists "sd_chat_messages_delete_own_or_coach" on public.sd_chat_messages;
create policy "sd_chat_messages_delete_own_or_coach"
on public.sd_chat_messages
for delete
to authenticated
using (sender_id = auth.uid() or public.sd_is_coach(auth.uid()));

-- Convenience view: last message per channel (for fast channel list rendering).
create or replace view public.sd_chat_channel_last_message as
select distinct on (m.channel_id)
  m.channel_id,
  left(m.body, 140) as body_preview,
  m.created_at as message_created_at
from public.sd_chat_messages m
where m.deleted_at is null
order by m.channel_id, m.created_at desc;

-- RPC: get or create DM for current user + other user.
create or replace function public.sd_get_or_create_dm(other_user_id uuid)
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

  a := least(me::text, other_user_id::text);
  b := greatest(me::text, other_user_id::text);
  k := a || ':' || b;

  select c.id into ch
  from public.sd_chat_channels c
  where c.channel_type = 'dm' and c.dm_key = k
  limit 1;

  if ch is null then
    insert into public.sd_chat_channels(channel_type, created_by, dm_key)
    values ('dm', me, k)
    returning id into ch;

    -- memberships for both participants
    insert into public.sd_chat_memberships(channel_id, user_id, member_role)
    values (ch, me, 'admin')
    on conflict do nothing;
    insert into public.sd_chat_memberships(channel_id, user_id, member_role)
    values (ch, other_user_id, 'member')
    on conflict do nothing;
  end if;

  return ch;
end;
$$;

revoke all on function public.sd_get_or_create_dm(uuid) from public;
grant execute on function public.sd_get_or_create_dm(uuid) to authenticated;

-- Enable Realtime for chat tables
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'sd_chat_messages'
  ) then
    execute 'alter publication supabase_realtime add table public.sd_chat_messages';
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'sd_chat_channels'
  ) then
    execute 'alter publication supabase_realtime add table public.sd_chat_channels';
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'sd_chat_memberships'
  ) then
    execute 'alter publication supabase_realtime add table public.sd_chat_memberships';
  end if;
end $$;

-- Bootstrap announcement channels (idempotent)
insert into public.sd_chat_channels(channel_type, title, audience, created_by, pinned_rank)
values
  ('announcement', 'Announcements • All Players', 'players', null, 1),
  ('announcement', 'Announcements • All Users', 'all', null, 2),
  ('announcement', 'Announcements • Organization', 'all', null, 3)
on conflict do nothing;
