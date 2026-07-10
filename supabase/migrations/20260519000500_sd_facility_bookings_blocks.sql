-- Support coach-created "blocks" (cage unavailable) that are not tied to a player.
-- Blocks show up as approved bookings for availability + conflict checking.

alter table public.sd_facility_bookings
  add column if not exists is_block boolean not null default false;

-- Make player_id nullable so blocks don't need a player.
alter table public.sd_facility_bookings
  alter column player_id drop not null;

-- Enforce: block => no player, non-block => player required.
alter table public.sd_facility_bookings
  drop constraint if exists sd_facility_bookings_block_player_check;

alter table public.sd_facility_bookings
  add constraint sd_facility_bookings_block_player_check
  check (
    (is_block and player_id is null)
    or ((not is_block) and player_id is not null)
  );

-- Ensure the existing select policy stays intact (defined in 20260519000100),
-- but update insert/update policies to allow coach-created blocks.
drop policy if exists "sd_facility_bookings_insert" on public.sd_facility_bookings;
create policy "sd_facility_bookings_insert"
on public.sd_facility_bookings
for insert
with check (
  (
    public.sd_is_coach(auth.uid())
    and created_by = auth.uid()
    and (
      is_block
      or (player_id is not null)
    )
  )
  or (
    created_by = auth.uid()
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
using (
  public.sd_is_coach(auth.uid())
  or (player_id = auth.uid() and status = 'pending' and is_block = false)
)
with check (
  public.sd_is_coach(auth.uid())
  or (player_id = auth.uid() and status in ('pending','cancelled') and is_block = false)
);

