-- Facilities scheduling for DHD Self Development.
-- - 3 cages are bookable resources.
-- - Players create pending requests.
-- - Coaches can approve/deny and reassign cages/coaches.

create table if not exists public.sd_facilities (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  is_active boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Seed the 3 cages (idempotent).
insert into public.sd_facilities (name, sort_order)
values
  ('Cage 1', 1),
  ('Cage 2', 2),
  ('Cage 3', 3)
on conflict (name) do nothing;

create index if not exists idx_sd_facilities_active on public.sd_facilities(is_active, sort_order);

create table if not exists public.sd_facility_bookings (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.sd_facilities(id) on delete restrict,
  player_id uuid not null references auth.users(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','approved','denied','cancelled')),
  activity_type text not null default 'bp' check (activity_type in ('bp','bullpen','extra_work','lesson','other')),
  start_at timestamptz not null,
  end_at timestamptz not null,
  coach_id uuid references auth.users(id) on delete set null,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  title text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_at > start_at)
);

create index if not exists idx_sd_facility_bookings_date on public.sd_facility_bookings(start_at, end_at);
create index if not exists idx_sd_facility_bookings_facility on public.sd_facility_bookings(facility_id, start_at);
create index if not exists idx_sd_facility_bookings_player on public.sd_facility_bookings(player_id, start_at);
create index if not exists idx_sd_facility_bookings_status on public.sd_facility_bookings(status, start_at);

-- Updated-at trigger (reuse sd_set_updated_at from sd tables migration).
drop trigger if exists trg_sd_facilities_updated_at on public.sd_facilities;
create trigger trg_sd_facilities_updated_at before update on public.sd_facilities
for each row execute function public.sd_set_updated_at();

drop trigger if exists trg_sd_facility_bookings_updated_at on public.sd_facility_bookings;
create trigger trg_sd_facility_bookings_updated_at before update on public.sd_facility_bookings
for each row execute function public.sd_set_updated_at();

alter table public.sd_facilities enable row level security;
alter table public.sd_facility_bookings enable row level security;

-- Facilities: all authenticated can read; only coaches can modify.
drop policy if exists "sd_facilities_select" on public.sd_facilities;
create policy "sd_facilities_select"
on public.sd_facilities
for select
to authenticated
using (true);

drop policy if exists "sd_facilities_write_coach" on public.sd_facilities;
create policy "sd_facilities_write_coach"
on public.sd_facilities
for all
using (public.sd_is_coach(auth.uid()))
with check (public.sd_is_coach(auth.uid()));

-- Bookings: players see their own; coaches see all.
drop policy if exists "sd_facility_bookings_select" on public.sd_facility_bookings;
create policy "sd_facility_bookings_select"
on public.sd_facility_bookings
for select
using (player_id = auth.uid() or public.sd_is_coach(auth.uid()));

-- Players create their own pending requests. Coaches can create for anyone.
drop policy if exists "sd_facility_bookings_insert" on public.sd_facility_bookings;
create policy "sd_facility_bookings_insert"
on public.sd_facility_bookings
for insert
with check (
  (public.sd_is_coach(auth.uid()) and created_by = auth.uid())
  or (
    created_by = auth.uid()
    and player_id = auth.uid()
    and status = 'pending'
    and approved_by is null
    and approved_at is null
  )
);

-- Updates:
-- - coaches can update any booking
-- - players can cancel their own pending booking (or update times while still pending)
drop policy if exists "sd_facility_bookings_update" on public.sd_facility_bookings;
create policy "sd_facility_bookings_update"
on public.sd_facility_bookings
for update
using (
  public.sd_is_coach(auth.uid())
  or (player_id = auth.uid() and status = 'pending')
)
with check (
  public.sd_is_coach(auth.uid())
  or (player_id = auth.uid() and status in ('pending','cancelled'))
);

