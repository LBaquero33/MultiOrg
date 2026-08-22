begin;

alter table public.sd_bp_sessions
  add column if not exists activity_type text not null default 'bp',
  add column if not exists video_path text;

alter table public.sd_bp_sessions
  drop constraint if exists sd_bp_sessions_activity_type_check;
alter table public.sd_bp_sessions
  add constraint sd_bp_sessions_activity_type_check
  check (activity_type in ('bp', 'bullpen'));

alter table public.sd_bp_sessions
  drop constraint if exists sd_bp_sessions_source_check;
alter table public.sd_bp_sessions
  add constraint sd_bp_sessions_source_check
  check (source in ('rapsodo', 'hitrax', 'trackman', 'video'));

drop index if exists public.ux_sd_bp_sessions_org_player_date_source_reps;
create unique index ux_sd_bp_sessions_org_player_date_activity_source_reps
on public.sd_bp_sessions(org_id, player_id, session_date, activity_type, source, reps_type);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'player-session-videos',
  'player-session-videos',
  false,
  262144000,
  array['video/mp4', 'video/quicktime']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "players upload their session videos" on storage.objects;
create policy "players upload their session videos"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'player-session-videos'
  and (storage.foldername(name))[2] = (select auth.uid()::text)
  and exists (
    select 1
    from public.sd_org_memberships membership
    where membership.org_id::text = (storage.foldername(name))[1]
      and membership.user_id = (select auth.uid())
      and membership.status = 'active'
      and membership.role = 'player'
  )
);

drop policy if exists "authorized users read player session videos" on storage.objects;
create policy "authorized users read player session videos"
on storage.objects for select to authenticated
using (
  bucket_id = 'player-session-videos'
  and (
    (storage.foldername(name))[2] = (select auth.uid()::text)
    or case
      when (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
       and (storage.foldername(name))[2] ~* '^[0-9a-f-]{36}$'
      then public.sd_can_manage_team_player(
        ((storage.foldername(name))[1])::uuid,
        ((storage.foldername(name))[2])::uuid
      )
      or public.sd_is_linked_parent_in_org(
        (select auth.uid()),
        ((storage.foldername(name))[2])::uuid,
        ((storage.foldername(name))[1])::uuid
      )
      else false
    end
  )
);

drop policy if exists "players update their session videos" on storage.objects;
create policy "players update their session videos"
on storage.objects for update to authenticated
using (
  bucket_id = 'player-session-videos'
  and owner_id = (select auth.uid()::text)
)
with check (
  bucket_id = 'player-session-videos'
  and owner_id = (select auth.uid()::text)
  and (storage.foldername(name))[2] = (select auth.uid()::text)
);

drop policy if exists "players delete their session videos" on storage.objects;
create policy "players delete their session videos"
on storage.objects for delete to authenticated
using (
  bucket_id = 'player-session-videos'
  and owner_id = (select auth.uid()::text)
);

commit;
