-- Account/Profile: full bio fields + avatar storage + player->parent request flow + entitlement visibility.

-- 1) Extend public.profiles (full bio + avatar)
alter table public.profiles
  add column if not exists avatar_path text,
  add column if not exists phone text,
  add column if not exists grad_year int,
  add column if not exists primary_position text,
  add column if not exists bats text,
  add column if not exists throws text,
  add column if not exists school text,
  add column if not exists team text,
  add column if not exists height_in int,
  add column if not exists weight_lb int,
  add column if not exists notes text;

-- Allow players to read linked parent profiles (so they can display parent names in-app).
drop policy if exists "profiles_select_child_parents" on public.profiles;
create policy "profiles_select_child_parents"
on public.profiles
for select
to authenticated
using (
  exists (
    select 1 from public.sd_parent_child_links l
    where l.child_id = auth.uid()
      and l.parent_id = profiles.id
  )
);

-- 2) Storage bucket for avatars (public)
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = excluded.public;

-- RLS: users can manage files only inside their own folder: {uid}/...
-- Note: public reads are served via the public bucket endpoint; no SELECT policy needed here.
drop policy if exists "avatars_insert_own_folder" on storage.objects;
create policy "avatars_insert_own_folder"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

drop policy if exists "avatars_update_own_folder" on storage.objects;
create policy "avatars_update_own_folder"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
)
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

drop policy if exists "avatars_delete_own_folder" on storage.objects;
create policy "avatars_delete_own_folder"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

-- 3) Player -> Parent request table (coach approves -> creates sd_parent_invites row)
create table if not exists public.sd_parent_invite_requests (
  id uuid primary key default gen_random_uuid(),
  email_norm text not null,
  child_id uuid not null references auth.users(id) on delete cascade,
  requested_by uuid not null references auth.users(id) on delete cascade,
  relationship text,
  status text not null default 'requested',
  coach_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_sd_parent_invite_requests_child on public.sd_parent_invite_requests(child_id, created_at desc);
create index if not exists idx_sd_parent_invite_requests_status on public.sd_parent_invite_requests(status, created_at desc);
create index if not exists idx_sd_parent_invite_requests_email on public.sd_parent_invite_requests(email_norm);

drop trigger if exists sd_parent_invite_requests_touch on public.sd_parent_invite_requests;
create trigger sd_parent_invite_requests_touch
before update on public.sd_parent_invite_requests
for each row execute function public.sd_touch_updated_at();

alter table public.sd_parent_invite_requests enable row level security;

-- Player can create and view their own requests.
drop policy if exists "sd_parent_invite_requests_player_select" on public.sd_parent_invite_requests;
create policy "sd_parent_invite_requests_player_select"
on public.sd_parent_invite_requests
for select
to authenticated
using (child_id = auth.uid() and requested_by = auth.uid());

drop policy if exists "sd_parent_invite_requests_player_insert" on public.sd_parent_invite_requests;
create policy "sd_parent_invite_requests_player_insert"
on public.sd_parent_invite_requests
for insert
to authenticated
with check (
  child_id = auth.uid()
  and requested_by = auth.uid()
  and status = 'requested'
);

-- Player can cancel only their own requested rows.
drop policy if exists "sd_parent_invite_requests_player_cancel" on public.sd_parent_invite_requests;
create policy "sd_parent_invite_requests_player_cancel"
on public.sd_parent_invite_requests
for update
to authenticated
using (child_id = auth.uid() and requested_by = auth.uid() and status = 'requested')
with check (child_id = auth.uid() and requested_by = auth.uid() and status = 'cancelled');

-- Coach can read and update all requests (approve/reject).
drop policy if exists "sd_parent_invite_requests_coach_select" on public.sd_parent_invite_requests;
create policy "sd_parent_invite_requests_coach_select"
on public.sd_parent_invite_requests
for select
to authenticated
using (public.sd_is_coach(auth.uid()));

drop policy if exists "sd_parent_invite_requests_coach_update" on public.sd_parent_invite_requests;
create policy "sd_parent_invite_requests_coach_update"
on public.sd_parent_invite_requests
for update
to authenticated
using (public.sd_is_coach(auth.uid()))
with check (public.sd_is_coach(auth.uid()));

-- When a coach approves, create a parent invite.
create or replace function public.sd_on_parent_invite_request_approved()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  coach_uid uuid;
begin
  -- Only act on transitions to approved.
  if new.status = 'approved' and (old.status is distinct from 'approved') then
    coach_uid := auth.uid();
    if not exists (
      select 1 from public.sd_parent_invites i
      where i.email_norm = new.email_norm
        and i.child_id = new.child_id
        and i.accepted_at is null
    ) then
      insert into public.sd_parent_invites (email_norm, child_id, invited_by, relationship)
      values (new.email_norm, new.child_id, coach_uid, new.relationship);
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sd_parent_invite_requests_approved on public.sd_parent_invite_requests;
create trigger trg_sd_parent_invite_requests_approved
after update of status
on public.sd_parent_invite_requests
for each row
when (new.status = 'approved')
execute function public.sd_on_parent_invite_request_approved();

-- 4) Allow linked parents and coaches to view a player's entitlement row (read-only).
drop policy if exists "sd_access_entitlements_select_own" on public.sd_access_entitlements;
create policy "sd_access_entitlements_select_own"
on public.sd_access_entitlements
for select
to authenticated
using (
  auth.uid() = user_id
  or public.sd_is_coach(auth.uid())
  or public.sd_is_linked_parent(auth.uid(), user_id)
);
