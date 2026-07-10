-- Cage 3 split support:
-- - Add sub-resources Cage 3.1 and Cage 3.2
-- - Allow a booking to span two facilities (full cage) via `span_facility_id`
-- - Enforce no-overlap for approved bookings across both primary + span facilities

create extension if not exists pgcrypto;

-- 1) Seed sub-cages (keep legacy "Cage 3" for now, but mark inactive).
insert into public.sd_facilities (name, sort_order, is_active)
values
  ('Cage 3.1', 31, true),
  ('Cage 3.2', 32, true)
on conflict (name) do update
  set is_active = excluded.is_active;

update public.sd_facilities
set is_active = false
where name = 'Cage 3';

-- 2) Add span column.
alter table public.sd_facility_bookings
  add column if not exists span_facility_id uuid references public.sd_facilities(id) on delete restrict;

-- Basic sanity: span must not equal primary.
alter table public.sd_facility_bookings
  drop constraint if exists sd_facility_bookings_span_not_self;
alter table public.sd_facility_bookings
  add constraint sd_facility_bookings_span_not_self
  check (span_facility_id is null or span_facility_id <> facility_id);

-- 3) RLS: no changes needed (span is just another column).

-- 4) Conflict checking:
-- Existing exclusion constraint prevents overlaps per `facility_id` for approved bookings.
-- We add a trigger to also prevent overlaps on `span_facility_id` (when present).

create or replace function public.sd_facility_bookings_check_span_overlap()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  -- Enforce for approved bookings.
  if new.status = 'approved' then
    if exists (
      select 1
      from public.sd_facility_bookings b
      where b.id <> new.id
        and b.status = 'approved'
        and tstzrange(b.start_at, b.end_at, '[)') && tstzrange(new.start_at, new.end_at, '[)')
        and (
          -- primary clashes
          b.facility_id = new.facility_id
          -- existing spans collide with new primary
          or b.span_facility_id = new.facility_id
          -- new spans collide with existing primary
          or (new.span_facility_id is not null and b.facility_id = new.span_facility_id)
          -- span-to-span collisions
          or (new.span_facility_id is not null and b.span_facility_id = new.span_facility_id)
        )
    ) then
      raise exception 'facility_span_overlap';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sd_facility_bookings_check_span_overlap on public.sd_facility_bookings;
create trigger trg_sd_facility_bookings_check_span_overlap
before insert or update of facility_id, span_facility_id, status, start_at, end_at
on public.sd_facility_bookings
for each row
execute function public.sd_facility_bookings_check_span_overlap();
