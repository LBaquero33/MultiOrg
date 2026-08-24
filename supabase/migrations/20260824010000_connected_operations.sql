begin;

create extension if not exists btree_gist;

-- Facilities are organized as Organization -> Location -> Resource. Existing
-- sd_facilities rows remain the resource records used by released clients.
create table if not exists public.sd_facility_locations (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 120),
  address text,
  timezone text not null default 'America/New_York',
  description text,
  is_active boolean not null default true,
  is_public boolean not null default true,
  sort_order integer not null default 0,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists sd_facility_locations_org_name
  on public.sd_facility_locations(org_id, lower(name));
create index if not exists sd_facility_locations_active
  on public.sd_facility_locations(org_id, is_active, sort_order, name);

alter table public.sd_facilities
  add column if not exists location_id uuid references public.sd_facility_locations(id) on delete restrict,
  add column if not exists public_booking_mode text not null default 'none'
    check (public_booking_mode in ('none', 'unpaid', 'paid')),
  add column if not exists public_hourly_rate_cents integer
    check (public_hourly_rate_cents is null or public_hourly_rate_cents >= 0),
  add column if not exists public_description text;

insert into public.sd_facility_locations(org_id, name, is_public, sort_order)
select distinct facility.org_id, 'Main Location', false, 0
from public.sd_facilities facility
where facility.org_id is not null
  and facility.location_id is null
  and not exists (
    select 1
    from public.sd_facility_locations location
    where location.org_id = facility.org_id
      and lower(location.name) = 'main location'
  );

update public.sd_facilities facility
set location_id = location.id
from public.sd_facility_locations location
where facility.location_id is null
  and facility.org_id = location.org_id
  and lower(location.name) = 'main location';

create index if not exists sd_facilities_location_active
  on public.sd_facilities(org_id, location_id, is_active, sort_order);

create table if not exists public.sd_facility_packages (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  location_id uuid not null references public.sd_facility_locations(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 120),
  description text,
  is_active boolean not null default true,
  public_booking_mode text not null default 'none'
    check (public_booking_mode in ('none', 'unpaid', 'paid')),
  public_price_cents integer check (public_price_cents is null or public_price_cents >= 0),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, org_id)
);

create unique index if not exists sd_facility_packages_location_name
  on public.sd_facility_packages(location_id, lower(name));

create table if not exists public.sd_facility_package_resources (
  package_id uuid not null references public.sd_facility_packages(id) on delete cascade,
  resource_id uuid not null references public.sd_facilities(id) on delete restrict,
  sort_order integer not null default 0,
  primary key (package_id, resource_id)
);

create table if not exists public.sd_facility_location_permissions (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  location_id uuid not null references public.sd_facility_locations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  can_view boolean not null default true,
  can_book boolean not null default true,
  can_approve boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (location_id, user_id)
);

-- One reservation ledger allows facility bookings, events, tryout sessions,
-- and camps to participate in the same conflict check.
create table if not exists public.sd_resource_reservations (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  location_id uuid not null references public.sd_facility_locations(id) on delete restrict,
  resource_id uuid not null references public.sd_facilities(id) on delete restrict,
  source_kind text not null check (source_kind in (
    'facility_booking', 'team_event', 'registration_session', 'public_booking', 'manual_block'
  )),
  source_id uuid not null,
  start_at timestamptz not null,
  end_at timestamptz not null,
  status text not null default 'held' check (status in ('held', 'confirmed', 'released', 'cancelled')),
  expires_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_at > start_at),
  unique (source_kind, source_id, resource_id)
);

create index if not exists sd_resource_reservations_scope
  on public.sd_resource_reservations(org_id, location_id, start_at, end_at);

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'sd_resource_reservations_no_overlap'
  ) then
    alter table public.sd_resource_reservations
      add constraint sd_resource_reservations_no_overlap
      exclude using gist (
        resource_id with =,
        tstzrange(start_at, end_at, '[)') with &&
      ) where (status in ('held', 'confirmed'));
  end if;
end $$;

create or replace function public.sd_can_use_facility_location(
  p_organization_id uuid,
  p_location_id uuid,
  p_actor_id uuid default auth.uid(),
  p_permission text default 'view'
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    p_actor_id is not null
    and exists (
      select 1
      from public.sd_facility_locations location
      where location.id = p_location_id
        and location.org_id = p_organization_id
        and location.is_active
    )
    and (
      exists (
        select 1
        from public.sd_org_memberships membership
        where membership.org_id = p_organization_id
          and membership.user_id = p_actor_id
          and membership.status = 'active'
          and membership.role in ('owner', 'admin')
      )
      or exists (
        select 1
        from public.sd_org_memberships membership
        join public.sd_facility_location_permissions permission
          on permission.org_id = membership.org_id
         and permission.user_id = membership.user_id
         and permission.location_id = p_location_id
        where membership.org_id = p_organization_id
          and membership.user_id = p_actor_id
          and membership.status = 'active'
          and membership.role = 'coach'
          and case p_permission
            when 'approve' then permission.can_approve
            when 'book' then permission.can_book
            else permission.can_view
          end
      )
    );
$$;

-- Released clients still write sd_facility_bookings. Keep that table as the
-- compatible booking record while synchronizing every active booking into the
-- shared reservation ledger used by facilities, events, and registration
-- sessions.
create or replace function public.sd_sync_facility_booking_reservation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.sd_facility_bookings;
  v_location_id uuid;
  v_reservation_status text;
begin
  if tg_op = 'DELETE' then
    update public.sd_resource_reservations reservation
    set status = 'cancelled', expires_at = null, updated_at = now()
    where reservation.source_kind = 'facility_booking'
      and reservation.source_id = old.id;
    return old;
  end if;

  v_booking := new;
  select facility.location_id into v_location_id
  from public.sd_facilities facility
  where facility.id = v_booking.facility_id
    and facility.org_id = v_booking.org_id;

  if v_location_id is null then
    return new;
  end if;

  if v_booking.status not in ('pending', 'approved') then
    update public.sd_resource_reservations reservation
    set status = 'cancelled', expires_at = null, updated_at = now()
    where reservation.source_kind = 'facility_booking'
      and reservation.source_id = v_booking.id;
    return new;
  end if;

  v_reservation_status := case when v_booking.status = 'approved'
    then 'confirmed' else 'held' end;

  delete from public.sd_resource_reservations reservation
  where reservation.source_kind = 'facility_booking'
    and reservation.source_id = v_booking.id
    and reservation.resource_id <> v_booking.facility_id;

  insert into public.sd_resource_reservations(
    org_id, location_id, resource_id, source_kind, source_id,
    start_at, end_at, status, expires_at, created_by
  ) values (
    v_booking.org_id, v_location_id, v_booking.facility_id,
    'facility_booking', v_booking.id, v_booking.start_at, v_booking.end_at,
    v_reservation_status, null, v_booking.created_by
  )
  on conflict (source_kind, source_id, resource_id) do update
  set org_id = excluded.org_id,
      location_id = excluded.location_id,
      start_at = excluded.start_at,
      end_at = excluded.end_at,
      status = excluded.status,
      expires_at = null,
      updated_at = now();

  return new;
end;
$$;

drop trigger if exists trg_sd_sync_facility_booking_reservation
  on public.sd_facility_bookings;
create trigger trg_sd_sync_facility_booking_reservation
after insert or update of facility_id, org_id, start_at, end_at, status
on public.sd_facility_bookings
for each row execute function public.sd_sync_facility_booking_reservation();

drop trigger if exists trg_sd_release_facility_booking_reservation
  on public.sd_facility_bookings;
create trigger trg_sd_release_facility_booking_reservation
after delete on public.sd_facility_bookings
for each row execute function public.sd_sync_facility_booking_reservation();

-- Backfill compatible booking rows. Historical conflicts are preserved rather
-- than making this additive migration destructive; future writes are protected
-- by the exclusion constraint and trigger above.
do $$
declare
  v_booking public.sd_facility_bookings;
  v_location_id uuid;
  v_reservation_status text;
begin
  for v_booking in
    select booking.*
    from public.sd_facility_bookings booking
    where booking.status in ('approved', 'pending')
    order by case when booking.status = 'approved' then 0 else 1 end,
      booking.created_at, booking.id
  loop
    select facility.location_id into v_location_id
    from public.sd_facilities facility
    where facility.id = v_booking.facility_id
      and facility.org_id = v_booking.org_id;

    if v_location_id is null then
      continue;
    end if;

    v_reservation_status := case when v_booking.status = 'approved'
      then 'confirmed' else 'held' end;

    begin
      insert into public.sd_resource_reservations(
        org_id, location_id, resource_id, source_kind, source_id,
        start_at, end_at, status, expires_at, created_by
      ) values (
        v_booking.org_id, v_location_id, v_booking.facility_id,
        'facility_booking', v_booking.id, v_booking.start_at, v_booking.end_at,
        v_reservation_status, null, v_booking.created_by
      )
      on conflict (source_kind, source_id, resource_id) do update
      set org_id = excluded.org_id,
          location_id = excluded.location_id,
          start_at = excluded.start_at,
          end_at = excluded.end_at,
          status = excluded.status,
          expires_at = null,
          updated_at = now();
    exception
      when exclusion_violation then
        null;
    end;
  end loop;
end $$;

-- Extend the existing offering record rather than introducing a competing
-- tryout/camp model.
alter table public.sd_registration_offerings
  add column if not exists format text not null default 'group'
    check (format in ('group', 'individual')),
  add column if not exists response_contact_name text,
  add column if not exists response_contact_email text,
  add column if not exists location_id uuid references public.sd_facility_locations(id) on delete set null,
  add column if not exists public_visible boolean not null default false,
  add column if not exists player_number_start integer not null default 1
    check (player_number_start between 1 and 9999),
  add column if not exists evaluations_enabled boolean not null default false,
  add column if not exists decision_cta jsonb not null default '{}'::jsonb
    check (jsonb_typeof(decision_cta) = 'object'),
  add column if not exists roster_needs jsonb not null default '{}'::jsonb
    check (jsonb_typeof(roster_needs) = 'object');

create table if not exists public.sd_registration_prospects (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  identity_key text not null,
  display_name text not null check (char_length(btrim(display_name)) between 1 and 160),
  first_name text,
  last_name text,
  birth_year integer check (birth_year is null or birth_year between 1980 and 2100),
  graduation_year integer check (graduation_year is null or graduation_year between 1990 and 2120),
  email text,
  phone text,
  positions text[] not null default '{}'::text[],
  linked_player_id uuid references auth.users(id) on delete set null,
  match_status text not null default 'unique'
    check (match_status in ('unique', 'ambiguous', 'merged')),
  merged_into_id uuid references public.sd_registration_prospects(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, identity_key)
);

create table if not exists public.sd_registration_participants (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  offering_id uuid not null references public.sd_registration_offerings(id) on delete cascade,
  prospect_id uuid references public.sd_registration_prospects(id) on delete restrict,
  application_id uuid references public.sd_registration_applications(id) on delete cascade,
  public_registration_submission_id uuid,
  player_user_id uuid references auth.users(id) on delete set null,
  guardian_user_id uuid references auth.users(id) on delete set null,
  source_kind text not null default 'authenticated_application'
    check (source_kind in ('authenticated_application', 'public_website', 'direct_public')),
  public_access_token_hash text,
  display_name text not null check (char_length(btrim(display_name)) between 1 and 160),
  contact_email text,
  contact_phone text,
  age_group text,
  graduation_year integer check (graduation_year is null or graduation_year between 1990 and 2120),
  positions text[] not null default '{}'::text[],
  public_answers jsonb not null default '{}'::jsonb check (jsonb_typeof(public_answers) = 'object'),
  participant_number integer check (participant_number is null or participant_number between 1 and 9999),
  registration_status text not null default 'submitted'
    check (registration_status in ('draft', 'submitted', 'awaiting_payment', 'paid', 'waitlisted', 'withdrawn', 'cancelled', 'completed')),
  payment_status text not null default 'not_due'
    check (payment_status in ('not_due', 'due', 'partial', 'paid', 'waived', 'refunded', 'overdue')),
  waiver_status text not null default 'missing'
    check (waiver_status in ('missing', 'in_progress', 'complete', 'expired')),
  decision_state text not null default 'unreviewed'
    check (decision_state in ('unreviewed', 'watchlist', 'undecided', 'offer_roster_spot', 'decline')),
  decision_released_at timestamptz,
  decision_message text,
  staff_comments text,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, organization_id),
  unique (offering_id, application_id),
  unique (offering_id, public_registration_submission_id)
);

create unique index if not exists sd_registration_participant_number
  on public.sd_registration_participants(offering_id, participant_number)
  where participant_number is not null;
create unique index if not exists sd_registration_participant_access_token
  on public.sd_registration_participants(public_access_token_hash)
  where public_access_token_hash is not null;
create index if not exists sd_registration_participants_dashboard
  on public.sd_registration_participants(organization_id, offering_id, decision_state, registration_status, created_at);

create table if not exists public.sd_registration_offering_staff (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  offering_id uuid not null references public.sd_registration_offerings(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  staff_role text not null check (staff_role in ('manager', 'evaluator', 'camp_staff')),
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (offering_id, user_id, staff_role)
);

create table if not exists public.sd_registration_sessions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  offering_id uuid not null references public.sd_registration_offerings(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 160),
  session_type text not null default 'group' check (session_type in ('group', 'individual', 'camp_day')),
  start_at timestamptz not null,
  end_at timestamptz not null,
  location_id uuid references public.sd_facility_locations(id) on delete set null,
  capacity integer check (capacity is null or capacity > 0),
  checkin_opens_at timestamptz,
  checkin_closes_at timestamptz,
  status text not null default 'scheduled' check (status in ('draft', 'scheduled', 'cancelled', 'completed')),
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_at > start_at)
);

create index if not exists sd_registration_sessions_schedule
  on public.sd_registration_sessions(organization_id, offering_id, start_at);

create table if not exists public.sd_registration_session_resources (
  session_id uuid not null references public.sd_registration_sessions(id) on delete cascade,
  resource_id uuid not null references public.sd_facilities(id) on delete restrict,
  primary key (session_id, resource_id)
);

create table if not exists public.sd_registration_session_participants (
  session_id uuid not null references public.sd_registration_sessions(id) on delete cascade,
  participant_id uuid not null references public.sd_registration_participants(id) on delete cascade,
  appointment_start_at timestamptz,
  appointment_end_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (session_id, participant_id),
  check (
    (appointment_start_at is null and appointment_end_at is null)
    or (appointment_start_at is not null and appointment_end_at > appointment_start_at)
  )
);

create table if not exists public.sd_registration_checkins (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  session_id uuid not null references public.sd_registration_sessions(id) on delete cascade,
  participant_id uuid not null references public.sd_registration_participants(id) on delete cascade,
  status text not null default 'present' check (status in ('present', 'late', 'left', 'absent')),
  checked_in_at timestamptz not null default now(),
  checked_in_by uuid references auth.users(id) on delete set null,
  source text not null default 'staff' check (source in ('staff', 'qr')),
  request_id uuid not null,
  notes text,
  created_at timestamptz not null default now(),
  unique (session_id, participant_id),
  unique (organization_id, request_id)
);

create table if not exists public.sd_registration_evaluation_templates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  offering_id uuid references public.sd_registration_offerings(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 120),
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.sd_registration_evaluation_criteria (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.sd_registration_evaluation_templates(id) on delete cascade,
  label text not null check (char_length(btrim(label)) between 1 and 120),
  input_type text not null check (input_type in ('letter_grade', 'twenty_eighty', 'one_hundred', 'comment_only')),
  help_text text,
  sort_order integer not null default 0
);

create table if not exists public.sd_registration_evaluations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  offering_id uuid not null references public.sd_registration_offerings(id) on delete cascade,
  participant_id uuid not null references public.sd_registration_participants(id) on delete cascade,
  session_id uuid references public.sd_registration_sessions(id) on delete set null,
  template_id uuid not null references public.sd_registration_evaluation_templates(id) on delete restrict,
  evaluator_user_id uuid not null references auth.users(id) on delete restrict,
  private_comments text,
  submitted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (participant_id, session_id, template_id, evaluator_user_id)
);

create table if not exists public.sd_registration_evaluation_values (
  evaluation_id uuid not null references public.sd_registration_evaluations(id) on delete cascade,
  criterion_id uuid not null references public.sd_registration_evaluation_criteria(id) on delete cascade,
  value_text text,
  value_number numeric,
  comment text,
  primary key (evaluation_id, criterion_id)
);

create table if not exists public.sd_registration_decision_releases (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  offering_id uuid not null references public.sd_registration_offerings(id) on delete cascade,
  request_id uuid not null,
  release_scope text not null check (release_scope in ('selected', 'all')),
  message text,
  decision_cta jsonb not null default '{}'::jsonb check (jsonb_typeof(decision_cta) = 'object'),
  released_by uuid not null references auth.users(id) on delete restrict,
  released_at timestamptz not null default now(),
  unique (organization_id, request_id)
);

create table if not exists public.sd_registration_decision_recipients (
  release_id uuid not null references public.sd_registration_decision_releases(id) on delete cascade,
  participant_id uuid not null references public.sd_registration_participants(id) on delete cascade,
  decision_state text not null check (decision_state in ('offer_roster_spot', 'decline')),
  recipient_email text not null,
  delivery_status text not null default 'queued' check (delivery_status in ('queued', 'sent', 'failed', 'cancelled')),
  provider_message_id text,
  sent_at timestamptz,
  error_code text,
  primary key (release_id, participant_id)
);

create table if not exists public.sd_camp_tracking_configs (
  offering_id uuid primary key references public.sd_registration_offerings(id) on delete cascade,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  testing_enabled boolean not null default true,
  final_evaluation_enabled boolean not null default true,
  final_evaluation_delivery text not null default 'internal'
    check (final_evaluation_delivery in ('internal', 'email_family')),
  daily_attendance_enabled boolean not null default false,
  daily_notes_enabled boolean not null default false,
  media_enabled boolean not null default false,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

-- Allocate one stable number per tryout offering. The advisory lock protects
-- concurrent public and authenticated registrations.
create or replace function public.sd_allocate_registration_participant_number()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_start integer;
begin
  if new.participant_number is not null then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(new.offering_id::text, 0));
  select player_number_start into v_start
  from public.sd_registration_offerings
  where id = new.offering_id and organization_id = new.organization_id;
  if v_start is null then
    raise exception 'registration_offering_not_found';
  end if;
  select greatest(
    v_start,
    coalesce(max(participant_number) + 1, v_start)
  ) into new.participant_number
  from public.sd_registration_participants
  where offering_id = new.offering_id;
  return new;
end;
$$;

drop trigger if exists trg_sd_registration_participant_number on public.sd_registration_participants;
create trigger trg_sd_registration_participant_number
before insert on public.sd_registration_participants
for each row execute function public.sd_allocate_registration_participant_number();

-- Backfill authenticated applications. Prospective details are kept in the
-- application; this participant projection exposes only operational fields.
insert into public.sd_registration_participants(
  organization_id, offering_id, application_id, player_user_id, guardian_user_id,
  source_kind, display_name, contact_email, contact_phone, age_group, graduation_year,
  positions, registration_status, payment_status, waiver_status, created_at, updated_at
)
select
  application.organization_id,
  application.offering_id,
  application.id,
  application.player_user_id,
  application.guardian_user_id,
  'authenticated_application',
  coalesce(
    nullif(application.prospective_player ->> 'display_name', ''),
    nullif(profile.full_name, ''),
    'Registered Player'
  ),
  nullif(application.prospective_player ->> 'email', ''),
  nullif(application.prospective_player ->> 'phone', ''),
  nullif(application.prospective_player ->> 'age_group', ''),
  case
    when application.prospective_player ->> 'graduation_year' ~ '^[0-9]{4}$'
      then (application.prospective_player ->> 'graduation_year')::integer
    else null
  end,
  case
    when nullif(application.position_preference, '') is null then '{}'::text[]
    else array[application.position_preference]
  end,
  case application.state
    when 'draft' then 'draft'
    when 'waitlisted' then 'waitlisted'
    when 'withdrawn' then 'withdrawn'
    when 'cancelled' then 'cancelled'
    when 'completed' then 'completed'
    else 'submitted'
  end,
  application.fee_status,
  case
    when exists (
      select 1 from public.sd_registration_requirement_responses response
      join public.sd_registration_requirement_templates template
        on template.id = response.requirement_template_id
      where response.application_id = application.id
        and template.requirement_type in ('waiver', 'consent')
        and response.status = 'accepted'
    ) then 'complete'
    else 'missing'
  end,
  application.created_at,
  application.updated_at
from public.sd_registration_applications application
left join public.profiles profile on profile.id = application.player_user_id
on conflict (offering_id, application_id) do nothing;

-- Website registration forms predate the canonical participant layer. When
-- those tables are installed, keep future form submissions synchronized
-- without changing their historical IDs or requiring a browser-side second write.
create or replace function public.sd_sync_public_registration_participant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_submission record;
  v_name text;
  v_email text;
  v_phone text;
begin
  select submission.payload, submission.submitter_name, submission.submitter_email,
         submission.payment_status
  into v_submission
  from public.sd_public_form_submissions submission
  where submission.id = new.submission_id and submission.org_id = new.org_id;

  v_name := coalesce(
    nullif(btrim(v_submission.submitter_name), ''),
    nullif(btrim(v_submission.payload->>'player_name'), ''),
    nullif(btrim(v_submission.payload->>'name'), ''),
    'Registrant'
  );
  v_email := nullif(lower(btrim(v_submission.submitter_email)), '');
  v_phone := nullif(btrim(coalesce(
    v_submission.payload->>'phone',
    v_submission.payload->>'parent_phone',
    v_submission.payload->>'guardian_phone'
  )), '');

  if new.offering_id is not null then
    insert into public.sd_registration_participants(
      organization_id, offering_id, public_registration_submission_id,
      source_kind, display_name, contact_email, contact_phone,
      age_group, graduation_year, positions, public_answers,
      registration_status, payment_status
    ) values (
      new.org_id, new.offering_id, new.id,
      'public_website', v_name, v_email, v_phone,
      nullif(btrim(v_submission.payload->>'age_group'), ''),
      case when coalesce(v_submission.payload->>'graduation_year', '') ~ '^[0-9]{4}$'
        then (v_submission.payload->>'graduation_year')::integer else null end,
      case when jsonb_typeof(v_submission.payload->'positions') = 'array'
        then array(select jsonb_array_elements_text(v_submission.payload->'positions'))
        else '{}'::text[] end,
      coalesce(v_submission.payload, '{}'::jsonb),
      case when coalesce(v_submission.payment_status, 'not_required') in ('pending', 'processing')
        then 'awaiting_payment' else 'submitted' end,
      case when v_submission.payment_status = 'paid' then 'paid'
        when coalesce(v_submission.payment_status, 'not_required') = 'not_required' then 'not_due'
        else 'due' end
    )
    on conflict (offering_id, public_registration_submission_id) do update
    set display_name = excluded.display_name,
        contact_email = excluded.contact_email,
        contact_phone = excluded.contact_phone,
        public_answers = excluded.public_answers,
        registration_status = excluded.registration_status,
        payment_status = excluded.payment_status,
        updated_at = now();
  end if;
  return new;
end;
$$;

do $$
begin
  if to_regclass('public.sd_public_registration_submissions') is not null
     and to_regclass('public.sd_public_form_submissions') is not null then
    execute 'drop trigger if exists trg_sd_sync_public_registration_participant on public.sd_public_registration_submissions';
    execute 'create trigger trg_sd_sync_public_registration_participant
      after insert or update of offering_id, status on public.sd_public_registration_submissions
      for each row execute function public.sd_sync_public_registration_participant()';
    -- Re-fire the new trigger for historical rows. The upsert in the trigger
    -- function makes this safe to repeat and preserves every source row ID.
    execute 'update public.sd_public_registration_submissions
      set offering_id = offering_id
      where offering_id is not null';
  end if;
end $$;

-- RLS helpers deliberately do not grant platform admins implicit organization
-- access. Organization membership or an explicit offering assignment is required.
create or replace function public.sd_can_manage_registration_offering(
  p_organization_id uuid,
  p_offering_id uuid,
  p_actor_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.sd_org_memberships membership
    where membership.org_id = p_organization_id
      and membership.user_id = p_actor_id
      and membership.status = 'active'
      and membership.role in ('owner', 'admin')
  ) or exists (
    select 1 from public.sd_registration_offering_staff assignment
    where assignment.organization_id = p_organization_id
      and assignment.offering_id = p_offering_id
      and assignment.user_id = p_actor_id
      and assignment.is_active
      and assignment.staff_role = 'manager'
  );
$$;

create or replace function public.sd_can_work_registration_offering(
  p_organization_id uuid,
  p_offering_id uuid,
  p_actor_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.sd_can_manage_registration_offering(p_organization_id, p_offering_id, p_actor_id)
    or exists (
      select 1 from public.sd_registration_offering_staff assignment
      where assignment.organization_id = p_organization_id
        and assignment.offering_id = p_offering_id
        and assignment.user_id = p_actor_id
        and assignment.is_active
        and assignment.staff_role in ('evaluator', 'camp_staff')
    );
$$;

-- Staff check-in is idempotent and validates participant/session scope in one
-- transaction. Public QR check-in uses a separate Edge Function and service role.
create or replace function public.sd_staff_check_in_registration_participant(
  p_organization_id uuid,
  p_actor_id uuid,
  p_session_id uuid,
  p_participant_id uuid,
  p_request_id uuid,
  p_status text default 'present',
  p_notes text default null
)
returns public.sd_registration_checkins
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session public.sd_registration_sessions%rowtype;
  v_result public.sd_registration_checkins%rowtype;
begin
  select * into v_result
  from public.sd_registration_checkins
  where organization_id = p_organization_id and request_id = p_request_id;
  if v_result.id is not null then return v_result; end if;

  select * into v_session
  from public.sd_registration_sessions
  where id = p_session_id and organization_id = p_organization_id;
  if v_session.id is null then raise exception 'registration_session_not_found'; end if;
  if not public.sd_can_work_registration_offering(
    p_organization_id, v_session.offering_id, p_actor_id
  ) then raise exception 'registration_staff_required'; end if;
  if p_status not in ('present', 'late', 'left', 'absent') then
    raise exception 'invalid_checkin_status';
  end if;
  if not exists (
    select 1 from public.sd_registration_participants participant
    where participant.id = p_participant_id
      and participant.organization_id = p_organization_id
      and participant.offering_id = v_session.offering_id
  ) then raise exception 'registration_participant_not_found'; end if;

  insert into public.sd_registration_session_participants(session_id, participant_id)
  values (p_session_id, p_participant_id)
  on conflict do nothing;

  insert into public.sd_registration_checkins(
    organization_id, session_id, participant_id, status, checked_in_by,
    source, request_id, notes
  ) values (
    p_organization_id, p_session_id, p_participant_id, p_status, p_actor_id,
    'staff', p_request_id, nullif(btrim(p_notes), '')
  )
  on conflict (session_id, participant_id) do update
  set status = excluded.status,
      checked_in_at = now(),
      checked_in_by = excluded.checked_in_by,
      source = 'staff',
      request_id = excluded.request_id,
      notes = excluded.notes
  returning * into v_result;
  return v_result;
end;
$$;

create or replace function public.sd_release_registration_decisions(
  p_organization_id uuid,
  p_actor_id uuid,
  p_offering_id uuid,
  p_participant_ids uuid[],
  p_release_all boolean,
  p_request_id uuid,
  p_message text,
  p_decision_cta jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_release_id uuid;
  v_recipient_count integer;
begin
  select release.id into v_release_id
  from public.sd_registration_decision_releases release
  where release.organization_id = p_organization_id
    and release.request_id = p_request_id;
  if v_release_id is not null then
    select count(*) into v_recipient_count
    from public.sd_registration_decision_recipients recipient
    where recipient.release_id = v_release_id;
    return jsonb_build_object(
      'release_id', v_release_id,
      'recipient_count', v_recipient_count,
      'replayed', true
    );
  end if;

  if not public.sd_can_manage_registration_offering(
    p_organization_id, p_offering_id, p_actor_id
  ) then raise exception 'registration_manager_required'; end if;

  if p_release_all and exists (
    select 1 from public.sd_registration_participants participant
    where participant.organization_id = p_organization_id
      and participant.offering_id = p_offering_id
      and participant.registration_status not in ('withdrawn', 'cancelled')
      and participant.decision_state not in ('offer_roster_spot', 'decline')
  ) then raise exception 'decision_release_unresolved_participants'; end if;

  if not exists (
    select 1 from public.sd_registration_participants participant
    where participant.organization_id = p_organization_id
      and participant.offering_id = p_offering_id
      and participant.decision_state in ('offer_roster_spot', 'decline')
      and (p_release_all or participant.id = any(coalesce(p_participant_ids, '{}'::uuid[])))
  ) then raise exception 'decision_release_empty'; end if;

  if exists (
    select 1 from public.sd_registration_participants participant
    where participant.organization_id = p_organization_id
      and participant.offering_id = p_offering_id
      and participant.decision_state in ('offer_roster_spot', 'decline')
      and (p_release_all or participant.id = any(coalesce(p_participant_ids, '{}'::uuid[])))
      and nullif(btrim(participant.contact_email), '') is null
  ) then raise exception 'decision_release_recipient_email_required'; end if;

  insert into public.sd_registration_decision_releases(
    organization_id, offering_id, request_id, release_scope, message,
    decision_cta, released_by
  ) values (
    p_organization_id, p_offering_id, p_request_id,
    case when p_release_all then 'all' else 'selected' end,
    nullif(btrim(p_message), ''), coalesce(p_decision_cta, '{}'::jsonb), p_actor_id
  ) returning id into v_release_id;

  insert into public.sd_registration_decision_recipients(
    release_id, participant_id, decision_state, recipient_email
  )
  select v_release_id, participant.id, participant.decision_state, participant.contact_email
  from public.sd_registration_participants participant
  where participant.organization_id = p_organization_id
    and participant.offering_id = p_offering_id
    and participant.decision_state in ('offer_roster_spot', 'decline')
    and (p_release_all or participant.id = any(coalesce(p_participant_ids, '{}'::uuid[])));

  update public.sd_registration_participants participant
  set decision_released_at = now(),
      decision_message = nullif(btrim(p_message), ''),
      version = participant.version + 1,
      updated_at = now()
  where participant.organization_id = p_organization_id
    and participant.offering_id = p_offering_id
    and participant.decision_state in ('offer_roster_spot', 'decline')
    and (p_release_all or participant.id = any(coalesce(p_participant_ids, '{}'::uuid[])));

  select count(*) into v_recipient_count
  from public.sd_registration_decision_recipients recipient
  where recipient.release_id = v_release_id;

  insert into public.sd_registration_audit_logs(
    organization_id, actor_id, action, target_type, target_id,
    request_id, new_state, details
  ) values (
    p_organization_id, p_actor_id, 'release_tryout_decisions', 'registration_offering',
    p_offering_id, p_request_id, 'released',
    jsonb_build_object('release_id', v_release_id, 'recipient_count', v_recipient_count)
  );

  return jsonb_build_object(
    'release_id', v_release_id,
    'recipient_count', v_recipient_count,
    'replayed', false
  );
end;
$$;

-- Updated-at triggers use the established helper.
drop trigger if exists trg_sd_facility_locations_updated_at on public.sd_facility_locations;
create trigger trg_sd_facility_locations_updated_at before update on public.sd_facility_locations
for each row execute function public.sd_set_updated_at();
drop trigger if exists trg_sd_facility_packages_updated_at on public.sd_facility_packages;
create trigger trg_sd_facility_packages_updated_at before update on public.sd_facility_packages
for each row execute function public.sd_set_updated_at();
drop trigger if exists trg_sd_resource_reservations_updated_at on public.sd_resource_reservations;
create trigger trg_sd_resource_reservations_updated_at before update on public.sd_resource_reservations
for each row execute function public.sd_set_updated_at();
drop trigger if exists trg_sd_registration_prospects_updated_at on public.sd_registration_prospects;
create trigger trg_sd_registration_prospects_updated_at before update on public.sd_registration_prospects
for each row execute function public.sd_set_updated_at();
drop trigger if exists trg_sd_registration_participants_updated_at on public.sd_registration_participants;
create trigger trg_sd_registration_participants_updated_at before update on public.sd_registration_participants
for each row execute function public.sd_set_updated_at();
drop trigger if exists trg_sd_registration_sessions_updated_at on public.sd_registration_sessions;
create trigger trg_sd_registration_sessions_updated_at before update on public.sd_registration_sessions
for each row execute function public.sd_set_updated_at();
drop trigger if exists trg_sd_registration_evaluation_templates_updated_at on public.sd_registration_evaluation_templates;
create trigger trg_sd_registration_evaluation_templates_updated_at before update on public.sd_registration_evaluation_templates
for each row execute function public.sd_set_updated_at();
drop trigger if exists trg_sd_registration_evaluations_updated_at on public.sd_registration_evaluations;
create trigger trg_sd_registration_evaluations_updated_at before update on public.sd_registration_evaluations
for each row execute function public.sd_set_updated_at();

-- Enable RLS on every additive table.
alter table public.sd_facility_locations enable row level security;
alter table public.sd_facility_packages enable row level security;
alter table public.sd_facility_package_resources enable row level security;
alter table public.sd_facility_location_permissions enable row level security;
alter table public.sd_resource_reservations enable row level security;
alter table public.sd_registration_prospects enable row level security;
alter table public.sd_registration_participants enable row level security;
alter table public.sd_registration_offering_staff enable row level security;
alter table public.sd_registration_sessions enable row level security;
alter table public.sd_registration_session_resources enable row level security;
alter table public.sd_registration_session_participants enable row level security;
alter table public.sd_registration_checkins enable row level security;
alter table public.sd_registration_evaluation_templates enable row level security;
alter table public.sd_registration_evaluation_criteria enable row level security;
alter table public.sd_registration_evaluations enable row level security;
alter table public.sd_registration_evaluation_values enable row level security;
alter table public.sd_registration_decision_releases enable row level security;
alter table public.sd_registration_decision_recipients enable row level security;
alter table public.sd_camp_tracking_configs enable row level security;

create policy sd_facility_locations_member_read on public.sd_facility_locations
for select to authenticated using (public.sd_is_org_member(org_id));
create policy sd_facility_locations_admin_write on public.sd_facility_locations
for all to authenticated using (public.sd_is_org_admin(org_id)) with check (public.sd_is_org_admin(org_id));
create policy sd_facility_packages_member_read on public.sd_facility_packages
for select to authenticated using (public.sd_is_org_member(org_id));
create policy sd_facility_packages_admin_write on public.sd_facility_packages
for all to authenticated using (public.sd_is_org_admin(org_id)) with check (public.sd_is_org_admin(org_id));
create policy sd_facility_package_resources_member_read on public.sd_facility_package_resources
for select to authenticated using (exists (
  select 1 from public.sd_facility_packages package
  where package.id = package_id and public.sd_is_org_member(package.org_id)
));
create policy sd_facility_location_permissions_subject_read on public.sd_facility_location_permissions
for select to authenticated using (user_id = auth.uid() or public.sd_is_org_admin(org_id));
create policy sd_facility_location_permissions_admin_write on public.sd_facility_location_permissions
for all to authenticated using (public.sd_is_org_admin(org_id)) with check (public.sd_is_org_admin(org_id));
create policy sd_resource_reservations_member_read on public.sd_resource_reservations
for select to authenticated using (public.sd_is_org_member(org_id));

create policy sd_registration_prospects_staff_read on public.sd_registration_prospects
for select to authenticated using (exists (
  select 1 from public.sd_registration_participants participant
  where participant.prospect_id = sd_registration_prospects.id
    and public.sd_can_work_registration_offering(organization_id, participant.offering_id)
));
create policy sd_registration_participants_authorized_read on public.sd_registration_participants
for select to authenticated using (
  public.sd_can_work_registration_offering(organization_id, offering_id)
  or player_user_id = auth.uid()
  or guardian_user_id = auth.uid()
  or exists (
    select 1 from public.sd_parent_child_links link
    where link.org_id = organization_id
      and link.parent_id = auth.uid()
      and link.child_id = player_user_id
  )
);
create policy sd_registration_offering_staff_subject_read on public.sd_registration_offering_staff
for select to authenticated using (
  user_id = auth.uid() or public.sd_can_manage_registration_offering(organization_id, offering_id)
);
create policy sd_registration_sessions_authorized_read on public.sd_registration_sessions
for select to authenticated using (
  public.sd_can_work_registration_offering(organization_id, offering_id)
  or exists (
    select 1 from public.sd_registration_session_participants session_participant
    join public.sd_registration_participants participant on participant.id = session_participant.participant_id
    where session_participant.session_id = id
      and (participant.player_user_id = auth.uid() or participant.guardian_user_id = auth.uid())
  )
);
create policy sd_registration_session_participants_authorized_read on public.sd_registration_session_participants
for select to authenticated using (exists (
  select 1 from public.sd_registration_sessions session
  join public.sd_registration_participants participant on participant.id = participant_id
  where session.id = session_id
    and (
      public.sd_can_work_registration_offering(session.organization_id, session.offering_id)
      or participant.player_user_id = auth.uid()
      or participant.guardian_user_id = auth.uid()
    )
));
create policy sd_registration_checkins_authorized_read on public.sd_registration_checkins
for select to authenticated using (exists (
  select 1 from public.sd_registration_participants participant
  where participant.id = participant_id
    and (
      public.sd_can_work_registration_offering(organization_id, participant.offering_id)
      or participant.player_user_id = auth.uid()
      or participant.guardian_user_id = auth.uid()
    )
));
create policy sd_registration_evaluation_templates_staff_read on public.sd_registration_evaluation_templates
for select to authenticated using (
  (offering_id is not null and public.sd_can_work_registration_offering(organization_id, offering_id))
  or (offering_id is null and public.sd_is_org_admin(organization_id))
);
create policy sd_registration_evaluation_criteria_staff_read on public.sd_registration_evaluation_criteria
for select to authenticated using (exists (
  select 1 from public.sd_registration_evaluation_templates template
  where template.id = template_id
    and (
      (template.offering_id is not null and public.sd_can_work_registration_offering(template.organization_id, template.offering_id))
      or (template.offering_id is null and public.sd_is_org_admin(template.organization_id))
    )
));
create policy sd_registration_evaluations_staff_read on public.sd_registration_evaluations
for select to authenticated using (public.sd_can_work_registration_offering(organization_id, offering_id));
create policy sd_registration_evaluation_values_staff_read on public.sd_registration_evaluation_values
for select to authenticated using (exists (
  select 1 from public.sd_registration_evaluations evaluation
  where evaluation.id = evaluation_id
    and public.sd_can_work_registration_offering(evaluation.organization_id, evaluation.offering_id)
));
create policy sd_registration_decision_releases_staff_read on public.sd_registration_decision_releases
for select to authenticated using (public.sd_can_manage_registration_offering(organization_id, offering_id));
create policy sd_registration_decision_recipients_staff_read on public.sd_registration_decision_recipients
for select to authenticated using (exists (
  select 1 from public.sd_registration_decision_releases release
  where release.id = release_id
    and public.sd_can_manage_registration_offering(release.organization_id, release.offering_id)
));
create policy sd_camp_tracking_configs_staff_read on public.sd_camp_tracking_configs
for select to authenticated using (public.sd_can_work_registration_offering(organization_id, offering_id));

-- Browser clients read through RLS; all writes remain in authenticated Edge
-- Functions so authorization, idempotency, and audit behavior stay consistent.
grant select on public.sd_facility_locations, public.sd_facility_packages,
  public.sd_facility_package_resources, public.sd_facility_location_permissions,
  public.sd_resource_reservations, public.sd_registration_prospects,
  public.sd_registration_participants, public.sd_registration_offering_staff,
  public.sd_registration_sessions, public.sd_registration_session_resources,
  public.sd_registration_session_participants, public.sd_registration_checkins,
  public.sd_registration_evaluation_templates, public.sd_registration_evaluation_criteria,
  public.sd_registration_evaluations, public.sd_registration_evaluation_values,
  public.sd_registration_decision_releases, public.sd_registration_decision_recipients,
  public.sd_camp_tracking_configs to authenticated;

grant select, insert, update, delete on public.sd_facility_locations,
  public.sd_facility_packages, public.sd_facility_package_resources,
  public.sd_facility_location_permissions, public.sd_resource_reservations,
  public.sd_registration_prospects, public.sd_registration_participants,
  public.sd_registration_offering_staff, public.sd_registration_sessions,
  public.sd_registration_session_resources, public.sd_registration_session_participants,
  public.sd_registration_checkins, public.sd_registration_evaluation_templates,
  public.sd_registration_evaluation_criteria, public.sd_registration_evaluations,
  public.sd_registration_evaluation_values, public.sd_registration_decision_releases,
  public.sd_registration_decision_recipients, public.sd_camp_tracking_configs to service_role;

revoke all on function public.sd_staff_check_in_registration_participant(
  uuid, uuid, uuid, uuid, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.sd_staff_check_in_registration_participant(
  uuid, uuid, uuid, uuid, uuid, text, text
) to service_role;

revoke all on function public.sd_release_registration_decisions(
  uuid, uuid, uuid, uuid[], boolean, uuid, text, jsonb
) from public, anon, authenticated;
grant execute on function public.sd_release_registration_decisions(
  uuid, uuid, uuid, uuid[], boolean, uuid, text, jsonb
) to service_role;

commit;
