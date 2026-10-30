begin;
alter table public.sd_public_booking_requests
  drop constraint if exists sd_public_booking_requests_status_check;
alter table public.sd_public_booking_requests
  add constraint sd_public_booking_requests_status_check check (status in (
    'holding',
    'pending_approval',
    'awaiting_payment',
    'authorized_pending_approval',
    'capturing',
    'paid',
    'confirmed',
    'denied',
    'cancelled',
    'expired',
    'refunded'
  ));
alter table public.sd_public_booking_requests
  add column if not exists booking_mode text not null default 'paid'
    check (booking_mode in ('unpaid', 'paid')),
  add column if not exists authorized_at timestamptz,
  add column if not exists authorization_expires_at timestamptz,
  add column if not exists captured_at timestamptz,
  add column if not exists denied_at timestamptz,
  add column if not exists cancelled_at timestamptz;
create index if not exists sd_public_booking_authorization_expiry
  on public.sd_public_booking_requests(authorization_expires_at)
  where status = 'authorized_pending_approval';
create or replace function public.sd_create_public_booking_hold(
  p_site_id uuid,
  p_org_id uuid,
  p_facility_id uuid,
  p_contact_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_amount_cents integer,
  p_currency text,
  p_notes text,
  p_policy_snapshot jsonb,
  p_expires_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request_id uuid;
  v_booking_mode text;
begin
  if p_end_at <= p_start_at or p_start_at <= now() or p_amount_cents < 0 then
    raise exception 'invalid_booking_request';
  end if;

  select facility.public_booking_mode into v_booking_mode
  from public.sd_facilities facility
  join public.sd_facility_locations location on location.id = facility.location_id
  where facility.id = p_facility_id
    and facility.org_id = p_org_id
    and facility.is_active
    and location.is_active
    and location.is_public
    and facility.public_booking_mode in ('unpaid', 'paid');

  if v_booking_mode is null then
    raise exception 'facility_not_public';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_facility_id::text, 0));

  if exists (
    select 1 from public.sd_resource_reservations reservation
    where reservation.resource_id = p_facility_id
      and reservation.status in ('held', 'confirmed')
      and coalesce(reservation.expires_at, 'infinity'::timestamptz) > now()
      and reservation.start_at < p_end_at
      and reservation.end_at > p_start_at
  ) then
    raise exception 'booking_time_unavailable';
  end if;

  insert into public.sd_public_booking_requests (
    site_id, org_id, facility_id, contact_id, start_at, end_at, status,
    amount_cents, currency, notes, policy_snapshot, expires_at, booking_mode
  ) values (
    p_site_id, p_org_id, p_facility_id, p_contact_id, p_start_at, p_end_at,
    'holding', p_amount_cents, lower(p_currency), nullif(trim(p_notes), ''),
    coalesce(p_policy_snapshot, '{}'::jsonb), p_expires_at, v_booking_mode
  ) returning id into v_request_id;

  return v_request_id;
end;
$$;
revoke all on function public.sd_create_public_booking_hold(uuid, uuid, uuid, uuid, timestamptz, timestamptz, integer, text, text, jsonb, timestamptz) from public;
grant execute on function public.sd_create_public_booking_hold(uuid, uuid, uuid, uuid, timestamptz, timestamptz, integer, text, text, jsonb, timestamptz) to service_role;
create or replace function public.sd_sync_public_booking_reservation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_location_id uuid;
  v_reservation_status text;
begin
  if tg_op = 'DELETE' then
    update public.sd_resource_reservations
    set status = 'cancelled', expires_at = null, updated_at = now()
    where source_kind = 'public_booking' and source_id = old.id;
    return old;
  end if;

  select location_id into v_location_id
  from public.sd_facilities
  where id = new.facility_id and org_id = new.org_id;

  if v_location_id is null then return new; end if;

  if new.status not in (
    'holding', 'pending_approval', 'awaiting_payment',
    'authorized_pending_approval', 'capturing', 'confirmed'
  ) then
    update public.sd_resource_reservations
    set status = 'cancelled', expires_at = null, updated_at = now()
    where source_kind = 'public_booking' and source_id = new.id;
    return new;
  end if;

  v_reservation_status := case when new.status = 'confirmed'
    then 'confirmed' else 'held' end;

  insert into public.sd_resource_reservations(
    org_id, location_id, resource_id, source_kind, source_id,
    start_at, end_at, status, expires_at, created_by
  ) values (
    new.org_id, v_location_id, new.facility_id, 'public_booking', new.id,
    new.start_at, new.end_at, v_reservation_status,
    coalesce(new.authorization_expires_at, new.expires_at), null
  )
  on conflict (source_kind, source_id, resource_id) do update
  set location_id = excluded.location_id,
      start_at = excluded.start_at,
      end_at = excluded.end_at,
      status = excluded.status,
      expires_at = excluded.expires_at,
      updated_at = now();

  return new;
end;
$$;
drop trigger if exists trg_sd_sync_public_booking_reservation
  on public.sd_public_booking_requests;
create trigger trg_sd_sync_public_booking_reservation
after insert or update or delete on public.sd_public_booking_requests
for each row execute function public.sd_sync_public_booking_reservation();
-- Rebuild active requests in the shared reservation ledger. Historical
-- overlaps are preserved and skipped instead of deleting operational data.
do $$
declare
  v_request public.sd_public_booking_requests;
  v_location_id uuid;
begin
  for v_request in
    select * from public.sd_public_booking_requests
    where status in ('holding', 'pending_approval', 'awaiting_payment', 'authorized_pending_approval', 'capturing', 'confirmed')
  loop
    begin
      select location_id into v_location_id
      from public.sd_facilities
      where id = v_request.facility_id and org_id = v_request.org_id;

      if v_location_id is not null then
        insert into public.sd_resource_reservations(
          org_id, location_id, resource_id, source_kind, source_id,
          start_at, end_at, status, expires_at, created_by
        ) values (
          v_request.org_id, v_location_id, v_request.facility_id,
          'public_booking', v_request.id, v_request.start_at, v_request.end_at,
          case when v_request.status = 'confirmed' then 'confirmed' else 'held' end,
          coalesce(v_request.authorization_expires_at, v_request.expires_at), null
        ) on conflict (source_kind, source_id, resource_id) do update
        set location_id = excluded.location_id,
            start_at = excluded.start_at,
            end_at = excluded.end_at,
            status = excluded.status,
            expires_at = excluded.expires_at,
            updated_at = now();
      end if;
    exception when exclusion_violation then
      null;
    end;
  end loop;
end $$;
commit;
