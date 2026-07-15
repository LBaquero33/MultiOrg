-- Reliability and administration follow-up for MultiOrg.
-- Keeps user-facing writes scoped to the active organization and fixes the
-- profile/avatar and parent-invite paths that were failing under RLS.

alter table public.sd_org_settings
  add column if not exists logo_path text,
  add column if not exists team_policy jsonb not null default jsonb_build_object(
    'coachesCanViewAllTeams', true,
    'restrictCoachActionsToTeam', true,
    'coachesCanManageTeams', false
  );

update public.sd_org_settings
set team_policy = coalesce(
  team_policy,
  jsonb_build_object(
    'coachesCanViewAllTeams', true,
    'restrictCoachActionsToTeam', true,
    'coachesCanManageTeams', false
  )
);

-- Coach/admin profiles use professional details while player fields remain
-- available for athletes. Nullable columns keep existing accounts compatible.
alter table public.profiles
  add column if not exists professional_title text,
  add column if not exists bio text,
  add column if not exists specialties text,
  add column if not exists website text,
  add column if not exists years_experience integer;

-- Make the own-profile contract explicit. The previous policies existed in
-- older projects, but this migration normalizes them after org migrations.
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
on public.profiles
for select
to authenticated
using (id = auth.uid());

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
on public.profiles
for insert
to authenticated
with check (id = auth.uid());

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
on public.profiles
for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

-- Avatar uploads live under <auth.uid()>/avatar.jpg.  A public bucket allows
-- members to render avatars without generating a signed URL per row.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = true;

drop policy if exists "avatars_public_read_v2" on storage.objects;
create policy "avatars_public_read_v2"
on storage.objects
for select
to public
using (bucket_id = 'avatars');

drop policy if exists "avatars_insert_own_v2" on storage.objects;
create policy "avatars_insert_own_v2"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "avatars_update_own_v2" on storage.objects;
create policy "avatars_update_own_v2"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "avatars_delete_own_v2" on storage.objects;
create policy "avatars_delete_own_v2"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Parent invite requests and issued invites must carry an org id. This makes
-- both player and coach paths valid under the multi-org RLS rules.
drop policy if exists "sd_parent_invite_requests_player_select" on public.sd_parent_invite_requests;
create policy "sd_parent_invite_requests_player_select"
on public.sd_parent_invite_requests
for select
to authenticated
using (
  child_id = auth.uid()
  and requested_by = auth.uid()
  and public.sd_is_org_member(org_id)
);

drop policy if exists "sd_parent_invite_requests_player_insert" on public.sd_parent_invite_requests;
create policy "sd_parent_invite_requests_player_insert"
on public.sd_parent_invite_requests
for insert
to authenticated
with check (
  child_id = auth.uid()
  and requested_by = auth.uid()
  and status = 'requested'
  and public.sd_is_org_member(org_id)
);

drop policy if exists "sd_parent_invite_requests_player_cancel" on public.sd_parent_invite_requests;
create policy "sd_parent_invite_requests_player_cancel"
on public.sd_parent_invite_requests
for update
to authenticated
using (
  child_id = auth.uid()
  and requested_by = auth.uid()
  and status = 'requested'
  and public.sd_is_org_member(org_id)
)
with check (
  child_id = auth.uid()
  and requested_by = auth.uid()
  and status = 'cancelled'
  and public.sd_is_org_member(org_id)
);

drop policy if exists "sd_parent_invite_requests_coach_select" on public.sd_parent_invite_requests;
create policy "sd_parent_invite_requests_coach_select"
on public.sd_parent_invite_requests
for select
to authenticated
using (public.sd_is_org_staff(org_id));

drop policy if exists "sd_parent_invite_requests_coach_update" on public.sd_parent_invite_requests;
create policy "sd_parent_invite_requests_coach_update"
on public.sd_parent_invite_requests
for update
to authenticated
using (public.sd_is_org_staff(org_id))
with check (public.sd_is_org_staff(org_id));

create or replace function public.sd_on_parent_invite_request_approved()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  coach_uid uuid;
begin
  if new.status = 'approved' and (old.status is distinct from 'approved') then
    coach_uid := auth.uid();
    if not exists (
      select 1
      from public.sd_parent_invites i
      where i.email_norm = new.email_norm
        and i.child_id = new.child_id
        and i.org_id = new.org_id
        and i.accepted_at is null
    ) then
      insert into public.sd_parent_invites (org_id, email_norm, child_id, invited_by, relationship)
      values (new.org_id, new.email_norm, new.child_id, coach_uid, new.relationship);
    end if;
  end if;
  return new;
end;
$$;

drop policy if exists "sd_parent_invites_coach_delete" on public.sd_parent_invites;
create policy "sd_parent_invites_coach_delete"
on public.sd_parent_invites
for delete
to authenticated
using (public.sd_is_org_staff(org_id));

-- Facility removal is intentionally restricted to organization admins, the
-- same people already allowed to create/edit resources.
drop policy if exists "sd_facilities_delete_admin" on public.sd_facilities;
create policy "sd_facilities_delete_admin"
on public.sd_facilities
for delete
to authenticated
using (org_id is not null and public.sd_is_org_admin(org_id));
