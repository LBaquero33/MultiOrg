-- Org customization/admin foundation for the multi-org desktop app.
--
-- Goal:
-- - Give each organization its own editable app chrome, terminology, feature flags,
--   facility resources, booking defaults, and admin-managed memberships.
-- - Backfill existing single-org facility data into the first org so current installs keep working.

create extension if not exists pgcrypto;

-- Generic updated-at helper may already exist, but keep this migration self-contained.
create or replace function public.sd_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Owners are distinct from coaches for admin privileges.
create or replace function public.sd_is_org_admin(org uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'auth'
as $$
  select exists(
    select 1
    from public.sd_org_memberships m
    where m.org_id = org
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.role in ('owner','coach')
  );
$$;

-- Coaches can operate the org; owners can configure it.
create or replace function public.sd_is_org_staff(org uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'auth'
as $$
  select exists(
    select 1
    from public.sd_org_memberships m
    where m.org_id = org
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.role in ('owner','coach')
  );
$$;

-- Organization-level settings. JSON blobs let us add customizable UI without a DB migration
-- every time a label, feature, or policy changes.
create table if not exists public.sd_org_settings (
  org_id uuid primary key references public.sd_orgs(id) on delete cascade,
  display_name text,
  short_name text,
  support_email text,
  website_host text,
  primary_color_hex text not null default '#0D2445',
  secondary_color_hex text not null default '#0A3854',
  accent_color_hex text not null default '#4D9EF9',
  terminology jsonb not null default '{}'::jsonb,
  feature_flags jsonb not null default '{}'::jsonb,
  booking_policy jsonb not null default '{}'::jsonb,
  dashboard_layout jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists trg_sd_org_settings_updated_at on public.sd_org_settings;
create trigger trg_sd_org_settings_updated_at before update on public.sd_org_settings
for each row execute function public.sd_set_updated_at();

alter table public.sd_org_settings enable row level security;
grant select, insert, update, delete on table public.sd_org_settings to authenticated;

drop policy if exists "sd_org_settings_select_member" on public.sd_org_settings;
create policy "sd_org_settings_select_member"
on public.sd_org_settings
for select
to authenticated
using (public.sd_is_org_member(org_id));

drop policy if exists "sd_org_settings_write_admin" on public.sd_org_settings;
create policy "sd_org_settings_write_admin"
on public.sd_org_settings
for all
to authenticated
using (public.sd_is_org_admin(org_id))
with check (public.sd_is_org_admin(org_id));

-- Facility resources become org-scoped and customizable.
alter table public.sd_facilities
  add column if not exists org_id uuid references public.sd_orgs(id) on delete cascade;

alter table public.sd_facilities
  add column if not exists resource_type text not null default 'cage';

alter table public.sd_facilities
  add column if not exists color_hex text;

alter table public.sd_facilities
  add column if not exists capacity int not null default 1;

alter table public.sd_facilities
  add column if not exists metadata jsonb not null default '{}'::jsonb;

do $$
declare
  first_org uuid;
begin
  select id into first_org from public.sd_orgs order by created_at asc limit 1;
  if first_org is not null then
    update public.sd_facilities
    set org_id = coalesce(org_id, first_org)
    where org_id is null;
  end if;
end $$;

create index if not exists idx_sd_facilities_org_active
on public.sd_facilities(org_id, is_active, sort_order);

-- The old unique(name) constraint makes no sense for multi-org. Replace with org-scoped uniqueness.
alter table public.sd_facilities
  drop constraint if exists sd_facilities_name_key;

create unique index if not exists sd_facilities_org_name_unique
on public.sd_facilities(org_id, lower(name))
where org_id is not null;

drop policy if exists "sd_facilities_select" on public.sd_facilities;
create policy "sd_facilities_select"
on public.sd_facilities
for select
to authenticated
using (org_id is null or public.sd_is_org_member(org_id));

drop policy if exists "sd_facilities_write_coach" on public.sd_facilities;
create policy "sd_facilities_write_admin"
on public.sd_facilities
for all
to authenticated
using (org_id is not null and public.sd_is_org_admin(org_id))
with check (org_id is not null and public.sd_is_org_admin(org_id));

-- Bookings inherit org scope for clean filtering and conflict checks.
alter table public.sd_facility_bookings
  add column if not exists org_id uuid references public.sd_orgs(id) on delete cascade;

do $$
begin
  update public.sd_facility_bookings b
  set org_id = f.org_id
  from public.sd_facilities f
  where b.facility_id = f.id
    and b.org_id is null
    and f.org_id is not null;
end $$;

create index if not exists idx_sd_facility_bookings_org_date
on public.sd_facility_bookings(org_id, start_at, end_at);

drop policy if exists "sd_facility_bookings_select" on public.sd_facility_bookings;
create policy "sd_facility_bookings_select"
on public.sd_facility_bookings
for select
to authenticated
using (
  (org_id is not null and public.sd_is_org_member(org_id))
  or player_id = auth.uid()
);

drop policy if exists "sd_facility_bookings_insert" on public.sd_facility_bookings;
create policy "sd_facility_bookings_insert"
on public.sd_facility_bookings
for insert
to authenticated
with check (
  (
    org_id is not null
    and public.sd_is_org_staff(org_id)
    and created_by = auth.uid()
    and (is_block or player_id is not null)
  )
  or (
    org_id is not null
    and public.sd_is_org_member(org_id)
    and created_by = auth.uid()
    and player_id = auth.uid()
    and is_block = false
    and status = 'pending'
    and approved_by is null
    and approved_at is null
  )
);

drop policy if exists "sd_facility_bookings_update" on public.sd_facility_bookings;
create policy "sd_facility_bookings_update"
on public.sd_facility_bookings
for update
to authenticated
using (
  (org_id is not null and public.sd_is_org_staff(org_id))
  or (player_id = auth.uid() and status = 'pending' and is_block = false)
)
with check (
  (org_id is not null and public.sd_is_org_staff(org_id))
  or (player_id = auth.uid() and status in ('pending','cancelled') and is_block = false)
);

-- Seed settings for existing orgs.
insert into public.sd_org_settings (org_id, display_name, short_name, terminology, feature_flags, booking_policy, dashboard_layout)
select
  o.id,
  o.name,
  o.name,
  jsonb_build_object(
    'player', 'Player',
    'players', 'Players',
    'coach', 'Coach',
    'coaches', 'Coaches',
    'facility', 'Facility',
    'facilities', 'Facilities',
    'program', 'Program',
    'testing', 'Testing'
  ),
  jsonb_build_object(
    'facilities', true,
    'chat', true,
    'programs', true,
    'testing', true,
    'bpAnalysis', true,
    'parentPortal', true,
    'billing', true
  ),
  jsonb_build_object(
    'defaultDurationMinutes', 60,
    'minDurationMinutes', 30,
    'maxDurationMinutes', 120,
    'allowPlayerRequests', true,
    'requireCoachApproval', true
  ),
  jsonb_build_object(
    'showOperations', true,
    'showRosterBadges', true,
    'showFacilitySnapshot', true
  )
from public.sd_orgs o
on conflict (org_id) do nothing;
