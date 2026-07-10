-- Allow all authenticated users to see approved facility bookings so players can
-- request times with visibility into cage availability.
--
-- Privacy note:
-- - This exposes player_id/created_by UUIDs to other authenticated users.
-- - If we later want to hide those, replace this with a SECURITY DEFINER RPC
--   that returns a redacted "public" booking shape.

alter table public.sd_facility_bookings enable row level security;

drop policy if exists "sd_facility_bookings_select" on public.sd_facility_bookings;
create policy "sd_facility_bookings_select"
on public.sd_facility_bookings
for select
using (
  public.sd_is_coach(auth.uid())
  or player_id = auth.uid()
  or status = 'approved'
);

-- Optional: prevent overlapping approved bookings per cage.
-- Uses an exclusion constraint on tstzrange; allows overlaps for pending/denied/cancelled.
create extension if not exists btree_gist;

alter table public.sd_facility_bookings
  drop constraint if exists sd_facility_bookings_no_overlap_approved;

alter table public.sd_facility_bookings
  add constraint sd_facility_bookings_no_overlap_approved
  exclude using gist (
    facility_id with =,
    tstzrange(start_at, end_at, '[)') with &&
  )
  where (status = 'approved');

