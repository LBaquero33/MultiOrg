begin;
create table if not exists public.sd_chat_message_reactions (
  message_id uuid not null references public.sd_chat_messages(id) on delete cascade,
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  channel_id uuid not null references public.sd_chat_channels(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null check (emoji in ('👍', '❤️', '😂', '😮', '😢', '🎉', '👏', '🔥')),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, emoji)
);
create index if not exists ix_sd_chat_message_reactions_channel
  on public.sd_chat_message_reactions(channel_id, created_at);
create or replace function public.sd_scope_chat_message_reaction()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  message_row public.sd_chat_messages%rowtype;
begin
  select * into message_row from public.sd_chat_messages where id = new.message_id;
  if not found or message_row.deleted_at is not null then
    raise exception 'chat_message_not_found' using errcode = 'P0002';
  end if;
  new.org_id := message_row.org_id;
  new.channel_id := message_row.channel_id;
  new.user_id := auth.uid();
  return new;
end;
$$;
drop trigger if exists sd_scope_chat_message_reaction_trigger on public.sd_chat_message_reactions;
create trigger sd_scope_chat_message_reaction_trigger
before insert or update on public.sd_chat_message_reactions
for each row execute function public.sd_scope_chat_message_reaction();
alter table public.sd_chat_message_reactions enable row level security;
drop policy if exists "chat members read reactions" on public.sd_chat_message_reactions;
create policy "chat members read reactions" on public.sd_chat_message_reactions
for select to authenticated using (public.sd_chat_is_member(channel_id, (select auth.uid())));
drop policy if exists "chat members add reactions" on public.sd_chat_message_reactions;
create policy "chat members add reactions" on public.sd_chat_message_reactions
for insert to authenticated with check (
  user_id = (select auth.uid()) and public.sd_chat_is_member(channel_id, (select auth.uid()))
);
drop policy if exists "chat members remove own reactions" on public.sd_chat_message_reactions;
create policy "chat members remove own reactions" on public.sd_chat_message_reactions
for delete to authenticated using (
  user_id = (select auth.uid()) and public.sd_chat_is_member(channel_id, (select auth.uid()))
);
create or replace function public.sd_toggle_chat_message_reaction(p_message_id uuid, p_emoji text)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_channel_id uuid;
  v_org_id uuid;
begin
  if v_user_id is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_emoji not in ('👍', '❤️', '😂', '😮', '😢', '🎉', '👏', '🔥') then
    raise exception 'unsupported_reaction' using errcode = '22023';
  end if;
  select channel_id, org_id into v_channel_id, v_org_id from public.sd_chat_messages
  where id = p_message_id and deleted_at is null;
  if v_channel_id is null then raise exception 'chat_message_not_found' using errcode = 'P0002'; end if;
  if not public.sd_chat_is_member(v_channel_id, v_user_id) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.sd_chat_message_reactions
    where message_id = p_message_id and user_id = v_user_id and emoji = p_emoji
  ) then
    delete from public.sd_chat_message_reactions
    where message_id = p_message_id and user_id = v_user_id and emoji = p_emoji;
    return false;
  end if;
  insert into public.sd_chat_message_reactions(message_id, org_id, channel_id, user_id, emoji)
  values (p_message_id, v_org_id, v_channel_id, v_user_id, p_emoji);
  return true;
end;
$$;
alter table public.sd_chat_channels add column if not exists team_id uuid references public.sd_teams(id) on delete set null;
create unique index if not exists ux_sd_chat_channels_active_team
  on public.sd_chat_channels(org_id, team_id)
  where team_id is not null and is_archived = false;
create or replace function public.sd_get_or_create_team_chat(p_org_id uuid, p_team_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role text;
  v_channel_id uuid;
  v_team_name text;
begin
  if v_actor_id is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select role into v_actor_role from public.sd_org_memberships
  where org_id = p_org_id and user_id = v_actor_id and status = 'active';
  if v_actor_role is null then raise exception 'not_authorized' using errcode = '42501'; end if;
  select name into v_team_name from public.sd_teams
  where id = p_team_id and org_id = p_org_id and is_active = true;
  if v_team_name is null then raise exception 'team_not_found' using errcode = 'P0002'; end if;
  if v_actor_role = 'coach' and not exists (
    select 1 from public.sd_coach_team_assignments assignment
    where assignment.organization_id = p_org_id and assignment.team_id = p_team_id
      and assignment.coach_id = v_actor_id and assignment.active = true and assignment.ended_at is null
  ) then raise exception 'team_not_authorized' using errcode = '42501'; end if;
  if v_actor_role = 'player' and not exists (
    select 1 from public.sd_player_team_memberships roster
    where roster.organization_id = p_org_id and roster.team_id = p_team_id
      and roster.player_id = v_actor_id and roster.active = true and roster.ended_at is null
  ) then raise exception 'team_not_authorized' using errcode = '42501'; end if;
  if v_actor_role = 'parent' and not exists (
    select 1
    from public.sd_parent_child_links link
    join public.sd_player_team_memberships roster
      on roster.organization_id = link.org_id and roster.player_id = link.child_id
    where link.org_id = p_org_id and link.parent_id = v_actor_id
      and roster.team_id = p_team_id and roster.active = true and roster.ended_at is null
  ) then raise exception 'team_not_authorized' using errcode = '42501'; end if;

  select id into v_channel_id from public.sd_chat_channels
  where org_id = p_org_id and team_id = p_team_id and is_archived = false limit 1;
  if v_channel_id is null then
    insert into public.sd_chat_channels(
      org_id, channel_type, conversation_kind, minor_visibility, title, created_by, team_id
    ) values (p_org_id, 'group', 'group', 'standard', v_team_name, v_actor_id, p_team_id)
    returning id into v_channel_id;
  end if;

  insert into public.sd_chat_memberships(org_id, channel_id, user_id, member_role)
  select p_org_id, v_channel_id, member_id, case when member_id = v_actor_id then 'admin' else 'member' end
  from (
    select v_actor_id as member_id
    union
    select roster.player_id from public.sd_player_team_memberships roster
    where roster.organization_id = p_org_id and roster.team_id = p_team_id
      and roster.active = true and roster.ended_at is null
    union
    select assignment.coach_id from public.sd_coach_team_assignments assignment
    where assignment.organization_id = p_org_id and assignment.team_id = p_team_id
      and assignment.active = true and assignment.ended_at is null
    union
    select link.parent_id
    from public.sd_player_team_memberships roster
    join public.sd_parent_child_links link
      on link.org_id = roster.organization_id and link.child_id = roster.player_id
    where roster.organization_id = p_org_id and roster.team_id = p_team_id
      and roster.active = true and roster.ended_at is null
  ) members
  on conflict (channel_id, user_id) do nothing;
  return v_channel_id;
end;
$$;
create table if not exists public.sd_program_set_media (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  player_id uuid not null references public.profiles(id) on delete cascade,
  assignment_id uuid not null references public.sd_program_assignments(id) on delete cascade,
  template_id uuid references public.sd_program_templates(id) on delete set null,
  log_date date not null,
  exercise_name text not null check (length(btrim(exercise_name)) between 1 and 180),
  set_number integer not null check (set_number between 1 and 50),
  storage_path text not null unique,
  file_name text not null check (length(btrim(file_name)) between 1 and 255),
  mime_type text not null check (mime_type in ('video/mp4', 'video/quicktime')),
  byte_size bigint not null check (byte_size between 1 and 262144000),
  uploaded_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, player_id, assignment_id, log_date, exercise_name, set_number)
);
create or replace function public.sd_scope_program_set_media()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not exists (
    select 1 from public.sd_program_assignments assignment
    where assignment.id = new.assignment_id and assignment.org_id = new.org_id
      and assignment.player_id = new.player_id
  ) then raise exception 'program_assignment_mismatch' using errcode = '42501'; end if;
  new.uploaded_by := auth.uid();
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists sd_scope_program_set_media_trigger on public.sd_program_set_media;
create trigger sd_scope_program_set_media_trigger before insert or update on public.sd_program_set_media
for each row execute function public.sd_scope_program_set_media();
alter table public.sd_program_set_media enable row level security;
drop policy if exists "program set media read" on public.sd_program_set_media;
create policy "program set media read" on public.sd_program_set_media for select to authenticated
using (player_id = (select auth.uid()) or public.sd_can_manage_team_player(org_id, player_id)
  or public.sd_is_linked_parent_in_org((select auth.uid()), player_id, org_id));
drop policy if exists "players create program set media" on public.sd_program_set_media;
create policy "players create program set media" on public.sd_program_set_media for insert to authenticated
with check (player_id = (select auth.uid()) and uploaded_by = (select auth.uid()));
drop policy if exists "players update program set media" on public.sd_program_set_media;
create policy "players update program set media" on public.sd_program_set_media for update to authenticated
using (player_id = (select auth.uid())) with check (player_id = (select auth.uid()) and uploaded_by = (select auth.uid()));
drop policy if exists "players delete program set media" on public.sd_program_set_media;
create policy "players delete program set media" on public.sd_program_set_media for delete to authenticated
using (player_id = (select auth.uid()));
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('program-set-videos', 'program-set-videos', false, 262144000, array['video/mp4','video/quicktime'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists "players upload program set videos" on storage.objects;
create policy "players upload program set videos" on storage.objects for insert to authenticated with check (
  bucket_id = 'program-set-videos' and owner_id = (select auth.uid()::text)
  and (storage.foldername(name))[2] = (select auth.uid()::text)
);
drop policy if exists "authorized users read program set videos" on storage.objects;
create policy "authorized users read program set videos" on storage.objects for select to authenticated using (
  bucket_id = 'program-set-videos' and exists (
    select 1 from public.sd_program_set_media media where media.storage_path = name
      and (media.player_id = (select auth.uid()) or public.sd_can_manage_team_player(media.org_id, media.player_id)
        or public.sd_is_linked_parent_in_org((select auth.uid()), media.player_id, media.org_id))
  )
);
drop policy if exists "players delete program set videos" on storage.objects;
create policy "players delete program set videos" on storage.objects for delete to authenticated
using (bucket_id = 'program-set-videos' and owner_id = (select auth.uid()::text));
revoke all on function public.sd_toggle_chat_message_reaction(uuid, text) from public, anon, authenticated;
revoke all on function public.sd_get_or_create_team_chat(uuid, uuid) from public, anon, authenticated;
grant select, insert, delete on public.sd_chat_message_reactions to authenticated;
grant execute on function public.sd_toggle_chat_message_reaction(uuid, text) to authenticated;
grant execute on function public.sd_get_or_create_team_chat(uuid, uuid) to authenticated;
grant select, insert, update, delete on public.sd_program_set_media to authenticated;
commit;
