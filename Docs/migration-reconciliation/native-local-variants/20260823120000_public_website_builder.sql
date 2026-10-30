begin;
create table if not exists public.sd_public_sites (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null unique references public.sd_orgs(id) on delete cascade,
  slug text not null unique check (slug ~ '^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$'),
  name text not null check (char_length(name) between 1 and 120),
  status text not null default 'draft' check (status in ('draft', 'published', 'maintenance')),
  theme jsonb not null default '{}'::jsonb check (jsonb_typeof(theme) = 'object'),
  settings jsonb not null default '{}'::jsonb check (jsonb_typeof(settings) = 'object'),
  draft_revision integer not null default 1 check (draft_revision > 0),
  published_version_id uuid,
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.sd_public_site_pages (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sd_public_sites(id) on delete cascade,
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  slug text not null check (slug = '' or slug ~ '^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$'),
  page_type text not null default 'standard' check (page_type in ('standard', 'team', 'staff', 'schedule', 'facility', 'offering', 'contact', 'news', 'faq', 'gallery')),
  is_home boolean not null default false,
  navigation_location text not null default 'header' check (navigation_location in ('header', 'footer', 'utility', 'hidden')),
  navigation_parent_id uuid references public.sd_public_site_pages(id) on delete set null,
  sort_order integer not null default 0,
  status text not null default 'draft' check (status in ('draft', 'published', 'hidden')),
  blocks jsonb not null default '[]'::jsonb check (jsonb_typeof(blocks) = 'array'),
  seo jsonb not null default '{}'::jsonb check (jsonb_typeof(seo) = 'object'),
  revision integer not null default 1 check (revision > 0),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (site_id, slug),
  unique (id, org_id)
);
create unique index if not exists sd_public_site_pages_one_home
  on public.sd_public_site_pages(site_id) where is_home;
create index if not exists sd_public_site_pages_navigation
  on public.sd_public_site_pages(site_id, navigation_location, sort_order);
create table if not exists public.sd_public_site_versions (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sd_public_sites(id) on delete cascade,
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  version_number integer not null check (version_number > 0),
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  validation jsonb not null default '{}'::jsonb check (jsonb_typeof(validation) = 'object'),
  published_by uuid not null references auth.users(id),
  published_at timestamptz not null default now(),
  unique (site_id, version_number)
);
alter table public.sd_public_sites
  add constraint sd_public_sites_published_version_fk
  foreign key (published_version_id) references public.sd_public_site_versions(id) on delete set null;
create table if not exists public.sd_public_staff_profiles (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  is_published boolean not null default false,
  display_name text not null check (char_length(display_name) between 1 and 120),
  public_title text,
  biography text,
  photo_path text,
  specialties text,
  public_email text,
  show_contact_button boolean not null default false,
  social_links jsonb not null default '{}'::jsonb check (jsonb_typeof(social_links) = 'object'),
  team_ids uuid[] not null default '{}',
  is_featured boolean not null default false,
  sort_order integer not null default 0,
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, user_id)
);
create table if not exists public.sd_public_form_definitions (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sd_public_sites(id) on delete cascade,
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  form_type text not null default 'contact' check (form_type in ('contact', 'tryout', 'camp', 'facility', 'newsletter', 'custom')),
  fields jsonb not null default '[]'::jsonb check (jsonb_typeof(fields) = 'array'),
  routing jsonb not null default '{}'::jsonb check (jsonb_typeof(routing) = 'object'),
  is_active boolean not null default true,
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.sd_public_form_submissions (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sd_public_sites(id) on delete cascade,
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  form_id uuid not null references public.sd_public_form_definitions(id) on delete restrict,
  workflow_status text not null default 'new' check (workflow_status in ('new', 'in_progress', 'replied', 'completed', 'spam', 'archived')),
  submitter_name text,
  submitter_email text not null,
  assigned_to uuid references auth.users(id) on delete set null,
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
  internal_notes text,
  source_page_slug text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists sd_public_form_submissions_inbox
  on public.sd_public_form_submissions(org_id, workflow_status, created_at desc);
create table if not exists public.sd_public_facility_configs (
  facility_id uuid primary key references public.sd_facilities(id) on delete cascade,
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  is_published boolean not null default false,
  description text,
  gallery jsonb not null default '[]'::jsonb check (jsonb_typeof(gallery) = 'array'),
  amenities text[] not null default '{}',
  address text,
  public_hours jsonb not null default '{}'::jsonb check (jsonb_typeof(public_hours) = 'object'),
  availability_rules jsonb not null default '{}'::jsonb check (jsonb_typeof(availability_rules) = 'object'),
  rate_cents integer not null default 0 check (rate_cents >= 0),
  currency text not null default 'usd' check (currency ~ '^[a-z]{3}$'),
  minimum_minutes integer not null default 30 check (minimum_minutes between 15 and 720),
  increment_minutes integer not null default 30 check (increment_minutes between 5 and 240),
  lead_time_hours integer not null default 2 check (lead_time_hours between 0 and 8760),
  max_advance_days integer not null default 60 check (max_advance_days between 1 and 730),
  buffer_minutes integer not null default 0 check (buffer_minutes between 0 and 240),
  confirmation_mode text not null default 'instant' check (confirmation_mode in ('instant', 'staff_approval')),
  cancellation_policy text,
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, facility_id)
);
create table if not exists public.sd_public_booking_contacts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  email text not null,
  full_name text not null,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists sd_public_booking_contacts_org_email
  on public.sd_public_booking_contacts(org_id, lower(email));
create table if not exists public.sd_public_booking_requests (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sd_public_sites(id) on delete cascade,
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  facility_id uuid not null references public.sd_facilities(id) on delete restrict,
  contact_id uuid not null references public.sd_public_booking_contacts(id) on delete restrict,
  start_at timestamptz not null,
  end_at timestamptz not null,
  status text not null default 'holding' check (status in ('holding', 'pending_approval', 'awaiting_payment', 'paid', 'confirmed', 'denied', 'cancelled', 'expired', 'refunded')),
  amount_cents integer not null check (amount_cents >= 0),
  currency text not null default 'usd' check (currency ~ '^[a-z]{3}$'),
  checkout_session_id text,
  payment_intent_id text,
  provider_account_id text,
  canonical_booking_id uuid references public.sd_facility_bookings(id) on delete set null,
  notes text,
  policy_snapshot jsonb not null default '{}'::jsonb check (jsonb_typeof(policy_snapshot) = 'object'),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_at > start_at)
);
create index if not exists sd_public_booking_requests_queue
  on public.sd_public_booking_requests(org_id, status, start_at);
create unique index if not exists sd_public_booking_requests_checkout
  on public.sd_public_booking_requests(checkout_session_id) where checkout_session_id is not null;
alter table public.sd_facility_bookings alter column created_by drop not null;
alter table public.sd_facility_bookings
  add column if not exists source text not null default 'home_plate_app',
  add column if not exists public_request_id uuid references public.sd_public_booking_requests(id) on delete set null;
create unique index if not exists sd_facility_bookings_public_request
  on public.sd_facility_bookings(public_request_id);
create table if not exists public.sd_public_site_daily_metrics (
  site_id uuid not null references public.sd_public_sites(id) on delete cascade,
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  metric_date date not null,
  page_views bigint not null default 0 check (page_views >= 0),
  unique_visitors bigint not null default 0 check (unique_visitors >= 0),
  form_submissions bigint not null default 0 check (form_submissions >= 0),
  booking_starts bigint not null default 0 check (booking_starts >= 0),
  booking_conversions bigint not null default 0 check (booking_conversions >= 0),
  primary key (site_id, metric_date)
);
create table if not exists public.sd_public_site_media (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sd_public_sites(id) on delete cascade,
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  bucket_id text not null default 'organization-site-media' check (bucket_id = 'organization-site-media'),
  object_path text not null,
  file_name text not null,
  mime_type text not null,
  byte_size bigint not null check (byte_size > 0 and byte_size <= 26214400),
  alt_text text,
  tags text[] not null default '{}',
  uploaded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (bucket_id, object_path)
);
create table if not exists public.sd_public_site_audit_log (
  id bigint generated always as identity primary key,
  site_id uuid not null references public.sd_public_sites(id) on delete cascade,
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  target_type text not null,
  target_id text,
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  created_at timestamptz not null default now()
);
create or replace function public.sd_public_site_can_manage(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.sd_org_memberships membership
    where membership.org_id = p_org_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
      and membership.role in ('owner', 'admin')
  );
$$;
revoke all on function public.sd_public_site_can_manage(uuid) from public;
grant execute on function public.sd_public_site_can_manage(uuid) to authenticated;
create or replace function public.sd_publish_public_site(
  p_site_id uuid,
  p_expected_revision integer
)
returns table(version_id uuid, version_number integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_site public.sd_public_sites%rowtype;
  v_number integer;
  v_version_id uuid;
  v_snapshot jsonb;
begin
  select * into v_site
  from public.sd_public_sites
  where id = p_site_id
  for update;

  if v_site.id is null or not public.sd_public_site_can_manage(v_site.org_id) then
    raise exception 'website_admin_required';
  end if;
  if v_site.draft_revision <> p_expected_revision then
    raise exception 'website_revision_conflict';
  end if;
  if not exists (select 1 from public.sd_public_site_pages where site_id = p_site_id and is_home) then
    raise exception 'website_homepage_required';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_number
  from public.sd_public_site_versions
  where site_id = p_site_id;

  select jsonb_build_object(
    'schema_version', 1,
    'site', jsonb_build_object(
      'slug', v_site.slug,
      'name', v_site.name,
      'theme', v_site.theme,
      'settings', v_site.settings
    ),
    'pages', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', page_row.id,
        'title', page_row.title,
        'slug', page_row.slug,
        'page_type', page_row.page_type,
        'is_home', page_row.is_home,
        'navigation_location', page_row.navigation_location,
        'navigation_parent_id', page_row.navigation_parent_id,
        'sort_order', page_row.sort_order,
        'status', page_row.status,
        'blocks', page_row.blocks,
        'seo', page_row.seo,
        'revision', page_row.revision
      ) order by page_row.sort_order, page_row.created_at)
      from public.sd_public_site_pages page_row
      where page_row.site_id = p_site_id and page_row.status <> 'hidden'
    ), '[]'::jsonb),
    'published_at', now()
  ) into v_snapshot;

  insert into public.sd_public_site_versions (
    site_id, org_id, version_number, snapshot, validation, published_by
  ) values (
    p_site_id, v_site.org_id, v_number, v_snapshot,
    jsonb_build_object('status', 'passed', 'errors', '[]'::jsonb), auth.uid()
  ) returning id into v_version_id;

  update public.sd_public_sites
  set status = 'published', published_version_id = v_version_id,
      updated_by = auth.uid(), updated_at = now()
  where id = p_site_id;

  insert into public.sd_public_site_audit_log(site_id, org_id, actor_id, action, target_type, target_id, details)
  values (p_site_id, v_site.org_id, auth.uid(), 'publish', 'site', p_site_id::text, jsonb_build_object('version', v_number));

  return query select v_version_id, v_number;
end;
$$;
revoke all on function public.sd_publish_public_site(uuid, integer) from public;
grant execute on function public.sd_publish_public_site(uuid, integer) to authenticated;
create or replace function public.sd_restore_public_site_version(
  p_site_id uuid,
  p_version_id uuid,
  p_expected_revision integer
)
returns table(draft_revision integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_site public.sd_public_sites%rowtype;
  v_snapshot jsonb;
  v_snapshot_site jsonb;
  v_page jsonb;
  v_revision integer;
begin
  select * into v_site
  from public.sd_public_sites
  where id = p_site_id
  for update;

  if v_site.id is null or not public.sd_public_site_can_manage(v_site.org_id) then
    raise exception 'website_admin_required';
  end if;
  if v_site.draft_revision <> p_expected_revision then
    raise exception 'website_revision_conflict';
  end if;

  select snapshot into v_snapshot
  from public.sd_public_site_versions
  where id = p_version_id
    and site_id = p_site_id
    and org_id = v_site.org_id;

  if v_snapshot is null then
    raise exception 'website_version_not_found';
  end if;

  v_snapshot_site := coalesce(v_snapshot -> 'site', '{}'::jsonb);
  v_revision := v_site.draft_revision + 1;

  delete from public.sd_public_site_pages where site_id = p_site_id;

  for v_page in
    select value from jsonb_array_elements(coalesce(v_snapshot -> 'pages', '[]'::jsonb))
  loop
    insert into public.sd_public_site_pages (
      id, site_id, org_id, title, slug, page_type, is_home,
      navigation_location, navigation_parent_id, sort_order, status,
      blocks, seo, revision, created_by, updated_by
    ) values (
      (v_page ->> 'id')::uuid,
      p_site_id,
      v_site.org_id,
      left(coalesce(v_page ->> 'title', 'Page'), 120),
      left(coalesce(v_page ->> 'slug', ''), 63),
      coalesce(v_page ->> 'page_type', 'standard'),
      coalesce((v_page ->> 'is_home')::boolean, false),
      coalesce(v_page ->> 'navigation_location', 'header'),
      null,
      coalesce((v_page ->> 'sort_order')::integer, 0),
      'draft',
      coalesce(v_page -> 'blocks', '[]'::jsonb),
      coalesce(v_page -> 'seo', '{}'::jsonb),
      greatest(coalesce((v_page ->> 'revision')::integer, 0) + 1, 1),
      auth.uid(),
      auth.uid()
    );
  end loop;

  for v_page in
    select value from jsonb_array_elements(coalesce(v_snapshot -> 'pages', '[]'::jsonb))
  loop
    if nullif(v_page ->> 'navigation_parent_id', '') is not null then
      update public.sd_public_site_pages
      set navigation_parent_id = (v_page ->> 'navigation_parent_id')::uuid
      where id = (v_page ->> 'id')::uuid
        and site_id = p_site_id
        and exists (
          select 1 from public.sd_public_site_pages parent
          where parent.id = (v_page ->> 'navigation_parent_id')::uuid
            and parent.site_id = p_site_id
        );
    end if;
  end loop;

  if not exists (
    select 1 from public.sd_public_site_pages
    where site_id = p_site_id and is_home
  ) then
    raise exception 'website_homepage_required';
  end if;

  update public.sd_public_sites
  set name = left(coalesce(v_snapshot_site ->> 'name', name), 120),
      theme = coalesce(v_snapshot_site -> 'theme', theme),
      settings = coalesce(v_snapshot_site -> 'settings', settings),
      draft_revision = v_revision,
      updated_by = auth.uid(),
      updated_at = now()
  where id = p_site_id;

  insert into public.sd_public_site_audit_log(
    site_id, org_id, actor_id, action, target_type, target_id, details
  ) values (
    p_site_id, v_site.org_id, auth.uid(), 'restore_draft', 'version',
    p_version_id::text, jsonb_build_object('draft_revision', v_revision)
  );

  return query select v_revision;
end;
$$;
revoke all on function public.sd_restore_public_site_version(uuid, uuid, integer) from public;
grant execute on function public.sd_restore_public_site_version(uuid, uuid, integer) to authenticated;
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
begin
  if p_end_at <= p_start_at or p_start_at <= now() or p_amount_cents < 0 then
    raise exception 'invalid_booking_request';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_facility_id::text, 0));

  if not exists (
    select 1 from public.sd_public_facility_configs config
    where config.facility_id = p_facility_id
      and config.org_id = p_org_id
      and config.is_published
  ) then
    raise exception 'facility_not_public';
  end if;

  if exists (
    select 1 from public.sd_facility_bookings booking
    where booking.facility_id = p_facility_id
      and booking.status in ('pending', 'approved')
      and booking.start_at < p_end_at
      and booking.end_at > p_start_at
  ) or exists (
    select 1 from public.sd_public_booking_requests request
    where request.facility_id = p_facility_id
      and request.status in ('holding', 'awaiting_payment', 'paid', 'confirmed')
      and coalesce(request.expires_at, 'infinity'::timestamptz) > now()
      and request.start_at < p_end_at
      and request.end_at > p_start_at
  ) then
    raise exception 'booking_time_unavailable';
  end if;

  insert into public.sd_public_booking_requests (
    site_id, org_id, facility_id, contact_id, start_at, end_at, status,
    amount_cents, currency, notes, policy_snapshot, expires_at
  ) values (
    p_site_id, p_org_id, p_facility_id, p_contact_id, p_start_at, p_end_at,
    'holding', p_amount_cents, lower(p_currency), nullif(trim(p_notes), ''),
    coalesce(p_policy_snapshot, '{}'::jsonb), p_expires_at
  ) returning id into v_request_id;

  return v_request_id;
end;
$$;
revoke all on function public.sd_create_public_booking_hold(uuid, uuid, uuid, uuid, timestamptz, timestamptz, integer, text, text, jsonb, timestamptz) from public;
grant execute on function public.sd_create_public_booking_hold(uuid, uuid, uuid, uuid, timestamptz, timestamptz, integer, text, text, jsonb, timestamptz) to service_role;
create or replace function public.sd_record_public_site_view(p_site_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.sd_public_site_daily_metrics(site_id, org_id, metric_date, page_views)
  select site.id, site.org_id, current_date, 1
  from public.sd_public_sites site
  where site.id = p_site_id and site.status in ('published', 'maintenance')
  on conflict (site_id, metric_date)
  do update set page_views = public.sd_public_site_daily_metrics.page_views + 1;
$$;
revoke all on function public.sd_record_public_site_view(uuid) from public;
grant execute on function public.sd_record_public_site_view(uuid) to service_role;
alter table public.sd_public_sites enable row level security;
alter table public.sd_public_site_pages enable row level security;
alter table public.sd_public_site_versions enable row level security;
alter table public.sd_public_staff_profiles enable row level security;
alter table public.sd_public_form_definitions enable row level security;
alter table public.sd_public_form_submissions enable row level security;
alter table public.sd_public_facility_configs enable row level security;
alter table public.sd_public_booking_contacts enable row level security;
alter table public.sd_public_booking_requests enable row level security;
alter table public.sd_public_site_daily_metrics enable row level security;
alter table public.sd_public_site_audit_log enable row level security;
alter table public.sd_public_site_media enable row level security;
create policy sd_public_sites_manage on public.sd_public_sites
  for all to authenticated
  using (public.sd_public_site_can_manage(org_id))
  with check (public.sd_public_site_can_manage(org_id));
create policy sd_public_site_pages_manage on public.sd_public_site_pages
  for all to authenticated
  using (public.sd_public_site_can_manage(org_id))
  with check (public.sd_public_site_can_manage(org_id));
create policy sd_public_site_versions_read on public.sd_public_site_versions
  for select to authenticated using (public.sd_public_site_can_manage(org_id));
create policy sd_public_staff_profiles_manage on public.sd_public_staff_profiles
  for all to authenticated
  using (public.sd_public_site_can_manage(org_id))
  with check (public.sd_public_site_can_manage(org_id));
create policy sd_public_form_definitions_manage on public.sd_public_form_definitions
  for all to authenticated
  using (public.sd_public_site_can_manage(org_id))
  with check (public.sd_public_site_can_manage(org_id));
create policy sd_public_form_submissions_manage on public.sd_public_form_submissions
  for all to authenticated
  using (public.sd_public_site_can_manage(org_id))
  with check (public.sd_public_site_can_manage(org_id));
create policy sd_public_facility_configs_manage on public.sd_public_facility_configs
  for all to authenticated
  using (public.sd_public_site_can_manage(org_id))
  with check (public.sd_public_site_can_manage(org_id));
create policy sd_public_booking_contacts_manage on public.sd_public_booking_contacts
  for select to authenticated using (public.sd_public_site_can_manage(org_id));
create policy sd_public_booking_requests_manage on public.sd_public_booking_requests
  for all to authenticated
  using (public.sd_public_site_can_manage(org_id))
  with check (public.sd_public_site_can_manage(org_id));
create policy sd_public_site_daily_metrics_read on public.sd_public_site_daily_metrics
  for select to authenticated using (public.sd_public_site_can_manage(org_id));
create policy sd_public_site_audit_log_read on public.sd_public_site_audit_log
  for select to authenticated using (public.sd_public_site_can_manage(org_id));
create policy sd_public_site_media_manage on public.sd_public_site_media
  for all to authenticated
  using (public.sd_public_site_can_manage(org_id))
  with check (public.sd_public_site_can_manage(org_id));
grant select, insert, update, delete on public.sd_public_sites to authenticated;
grant select, insert, update, delete on public.sd_public_site_pages to authenticated;
grant select on public.sd_public_site_versions to authenticated;
grant select, insert, update, delete on public.sd_public_staff_profiles to authenticated;
grant select, insert, update, delete on public.sd_public_form_definitions to authenticated;
grant select, insert, update, delete on public.sd_public_form_submissions to authenticated;
grant select, insert, update, delete on public.sd_public_facility_configs to authenticated;
grant select on public.sd_public_booking_contacts to authenticated;
grant select, insert, update, delete on public.sd_public_booking_requests to authenticated;
grant select on public.sd_public_site_daily_metrics to authenticated;
grant select on public.sd_public_site_audit_log to authenticated;
grant select, insert, update, delete on public.sd_public_site_media to authenticated;
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values (
  'organization-site-media',
  'organization-site-media',
  false,
  26214400,
  array['image/jpeg', 'image/png', 'image/webp', 'image/avif', 'video/mp4']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
create policy sd_public_site_media_storage_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'organization-site-media'
    and exists (select 1 from public.sd_org_memberships m where m.org_id::text = (storage.foldername(name))[1] and m.user_id = auth.uid() and m.status = 'active' and m.role in ('owner', 'admin'))
  );
create policy sd_public_site_media_storage_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'organization-site-media'
    and exists (select 1 from public.sd_org_memberships m where m.org_id::text = (storage.foldername(name))[1] and m.user_id = auth.uid() and m.status = 'active' and m.role in ('owner', 'admin'))
  );
create policy sd_public_site_media_storage_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'organization-site-media'
    and exists (select 1 from public.sd_org_memberships m where m.org_id::text = (storage.foldername(name))[1] and m.user_id = auth.uid() and m.status = 'active' and m.role in ('owner', 'admin'))
  )
  with check (
    bucket_id = 'organization-site-media'
    and exists (select 1 from public.sd_org_memberships m where m.org_id::text = (storage.foldername(name))[1] and m.user_id = auth.uid() and m.status = 'active' and m.role in ('owner', 'admin'))
  );
create policy sd_public_site_media_storage_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'organization-site-media'
    and exists (select 1 from public.sd_org_memberships m where m.org_id::text = (storage.foldername(name))[1] and m.user_id = auth.uid() and m.status = 'active' and m.role in ('owner', 'admin'))
  );
commit;
