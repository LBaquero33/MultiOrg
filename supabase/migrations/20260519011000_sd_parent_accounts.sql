-- Parent accounts: view-only child access + bookings + manual pay-on-behalf.

create extension if not exists pgcrypto;

-- Helpers
create or replace function public.sd_is_parent(uid uuid)
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = uid and p.role = 'parent'
  );
$$;

-- Parent invites (coach -> email; parent accepts in-app)
create table if not exists public.sd_parent_invites (
  id uuid primary key default gen_random_uuid(),
  email_norm text not null,
  child_id uuid not null references auth.users(id) on delete cascade,
  invited_by uuid references auth.users(id) on delete set null,
  relationship text,
  accepted_at timestamptz,
  parent_id uuid references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists idx_sd_parent_invites_email on public.sd_parent_invites(email_norm);
create index if not exists idx_sd_parent_invites_child on public.sd_parent_invites(child_id, created_at desc);

alter table public.sd_parent_invites enable row level security;

drop policy if exists "sd_parent_invites_coach_select" on public.sd_parent_invites;
create policy "sd_parent_invites_coach_select"
on public.sd_parent_invites
for select
using (public.sd_is_coach(auth.uid()));

drop policy if exists "sd_parent_invites_coach_insert" on public.sd_parent_invites;
create policy "sd_parent_invites_coach_insert"
on public.sd_parent_invites
for insert
with check (public.sd_is_coach(auth.uid()) and invited_by = auth.uid());

drop policy if exists "sd_parent_invites_coach_update" on public.sd_parent_invites;
create policy "sd_parent_invites_coach_update"
on public.sd_parent_invites
for update
using (public.sd_is_coach(auth.uid()))
with check (public.sd_is_coach(auth.uid()));

drop policy if exists "sd_parent_invites_coach_delete" on public.sd_parent_invites;
create policy "sd_parent_invites_coach_delete"
on public.sd_parent_invites
for delete
using (public.sd_is_coach(auth.uid()));

-- Parent can view + accept invites addressed to their email.
drop policy if exists "sd_parent_invites_parent_select" on public.sd_parent_invites;
create policy "sd_parent_invites_parent_select"
on public.sd_parent_invites
for select
to authenticated
using (
  lower(coalesce((auth.jwt() ->> 'email'), '')) = email_norm
);

drop policy if exists "sd_parent_invites_parent_accept" on public.sd_parent_invites;
create policy "sd_parent_invites_parent_accept"
on public.sd_parent_invites
for update
to authenticated
using (
  lower(coalesce((auth.jwt() ->> 'email'), '')) = email_norm
  and parent_id is null
  and accepted_at is null
)
with check (
  lower(coalesce((auth.jwt() ->> 'email'), '')) = email_norm
  and parent_id = auth.uid()
  and accepted_at is not null
);

-- Parent-child links
create table if not exists public.sd_parent_child_links (
  parent_id uuid not null references auth.users(id) on delete cascade,
  child_id uuid not null references auth.users(id) on delete cascade,
  relationship text,
  can_book boolean not null default true,
  can_pay boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  primary key (parent_id, child_id)
);

create index if not exists idx_sd_parent_child_links_parent on public.sd_parent_child_links(parent_id, child_id);
create index if not exists idx_sd_parent_child_links_child on public.sd_parent_child_links(child_id, parent_id);

alter table public.sd_parent_child_links enable row level security;

-- Helper (depends on sd_parent_child_links)
create or replace function public.sd_is_linked_parent(parent_uid uuid, child_uid uuid)
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from public.sd_parent_child_links l
    where l.parent_id = parent_uid and l.child_id = child_uid
  );
$$;

drop policy if exists "sd_parent_child_links_parent_select" on public.sd_parent_child_links;
create policy "sd_parent_child_links_parent_select"
on public.sd_parent_child_links
for select
using (parent_id = auth.uid());

drop policy if exists "sd_parent_child_links_child_select" on public.sd_parent_child_links;
create policy "sd_parent_child_links_child_select"
on public.sd_parent_child_links
for select
using (child_id = auth.uid());

drop policy if exists "sd_parent_child_links_coach_all" on public.sd_parent_child_links;
create policy "sd_parent_child_links_coach_all"
on public.sd_parent_child_links
for all
using (public.sd_is_coach(auth.uid()))
with check (public.sd_is_coach(auth.uid()));

-- Accepting an invite creates/updates the link row.
create or replace function public.sd_on_parent_invite_accept()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if new.accepted_at is not null and new.parent_id is not null then
    insert into public.sd_parent_child_links(parent_id, child_id, relationship, created_by)
    values (new.parent_id, new.child_id, new.relationship, new.invited_by)
    on conflict (parent_id, child_id) do update
      set relationship = excluded.relationship;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sd_parent_invites_accept on public.sd_parent_invites;
create trigger trg_sd_parent_invites_accept
after update of accepted_at, parent_id
on public.sd_parent_invites
for each row
when (new.accepted_at is not null and new.parent_id is not null)
execute function public.sd_on_parent_invite_accept();

-- Allow parents to read child profiles (without breaking coach select).
drop policy if exists "profiles_select_parent_children" on public.profiles;
create policy "profiles_select_parent_children"
on public.profiles
for select
using (
  exists (
    select 1 from public.sd_parent_child_links l
    where l.parent_id = auth.uid()
      and l.child_id = profiles.id
  )
);

-- Manual pay-on-behalf requests (parents create; coaches mark paid).
create table if not exists public.sd_payment_requests (
  id uuid primary key default gen_random_uuid(),
  payer_id uuid not null references auth.users(id) on delete cascade,
  child_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'requested',
  plan_name text,
  amount_cents int,
  currency text not null default 'usd',
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_sd_payment_requests_child on public.sd_payment_requests(child_id, created_at desc);
create index if not exists idx_sd_payment_requests_payer on public.sd_payment_requests(payer_id, created_at desc);

drop trigger if exists sd_payment_requests_touch on public.sd_payment_requests;
create trigger sd_payment_requests_touch
before update on public.sd_payment_requests
for each row execute function public.sd_touch_updated_at();

alter table public.sd_payment_requests enable row level security;

drop policy if exists "sd_payment_requests_parent_select" on public.sd_payment_requests;
create policy "sd_payment_requests_parent_select"
on public.sd_payment_requests
for select
using (
  payer_id = auth.uid()
  and exists (
    select 1 from public.sd_parent_child_links l
    where l.parent_id = auth.uid()
      and l.child_id = sd_payment_requests.child_id
      and l.can_pay = true
  )
);

drop policy if exists "sd_payment_requests_parent_insert" on public.sd_payment_requests;
create policy "sd_payment_requests_parent_insert"
on public.sd_payment_requests
for insert
with check (
  payer_id = auth.uid()
  and exists (
    select 1 from public.sd_parent_child_links l
    where l.parent_id = auth.uid()
      and l.child_id = sd_payment_requests.child_id
      and l.can_pay = true
  )
);

drop policy if exists "sd_payment_requests_coach_select" on public.sd_payment_requests;
create policy "sd_payment_requests_coach_select"
on public.sd_payment_requests
for select
using (public.sd_is_coach(auth.uid()));

drop policy if exists "sd_payment_requests_coach_update" on public.sd_payment_requests;
create policy "sd_payment_requests_coach_update"
on public.sd_payment_requests
for update
using (public.sd_is_coach(auth.uid()))
with check (public.sd_is_coach(auth.uid()));

-- When a coach marks a request as paid, unlock the child by upserting access entitlement.
create or replace function public.sd_on_payment_request_paid()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if new.status = 'paid' and (old.status is distinct from new.status) then
    insert into public.sd_access_entitlements(user_id, is_active, source)
    values (new.child_id, true, 'manual_parent')
    on conflict (user_id) do update
      set is_active = true,
          source = 'manual_parent',
          updated_at = now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sd_payment_requests_paid on public.sd_payment_requests;
create trigger trg_sd_payment_requests_paid
after update of status
on public.sd_payment_requests
for each row
when (new.status = 'paid')
execute function public.sd_on_payment_request_paid();

-- Parent read-only access to child data
drop policy if exists "sd_daily_logs_select" on public.sd_daily_logs;
create policy "sd_daily_logs_select"
on public.sd_daily_logs
for select
using (
  player_id = auth.uid()
  or public.sd_is_coach(auth.uid())
  or public.sd_is_linked_parent(auth.uid(), player_id)
);

drop policy if exists "sd_strength_logs_select" on public.sd_strength_logs;
create policy "sd_strength_logs_select"
on public.sd_strength_logs
for select
using (
  player_id = auth.uid()
  or public.sd_is_coach(auth.uid())
  or public.sd_is_linked_parent(auth.uid(), player_id)
);

drop policy if exists "sd_testing_select" on public.sd_testing_entries;
create policy "sd_testing_select"
on public.sd_testing_entries
for select
using (
  player_id = auth.uid()
  or public.sd_is_coach(auth.uid())
  or public.sd_is_linked_parent(auth.uid(), player_id)
);

drop policy if exists "sd_bp_sessions_select" on public.sd_bp_sessions;
create policy "sd_bp_sessions_select"
on public.sd_bp_sessions
for select
using (
  player_id = auth.uid()
  or public.sd_is_coach(auth.uid())
  or public.sd_is_linked_parent(auth.uid(), player_id)
);

drop policy if exists "sd_bp_events_select" on public.sd_bp_events;
create policy "sd_bp_events_select"
on public.sd_bp_events
for select
using (
  exists (
    select 1 from public.sd_bp_sessions s
    where s.id = sd_bp_events.session_id
      and (
        s.player_id = auth.uid()
        or public.sd_is_coach(auth.uid())
        or public.sd_is_linked_parent(auth.uid(), s.player_id)
      )
  )
);

-- Facilities: parent can request/manage bookings on behalf of linked child
drop policy if exists "sd_facility_bookings_select" on public.sd_facility_bookings;
create policy "sd_facility_bookings_select"
on public.sd_facility_bookings
for select
using (
  public.sd_is_coach(auth.uid())
  or status = 'approved'
  or created_by = auth.uid()
  or (player_id = auth.uid())
  or (player_id is not null and public.sd_is_linked_parent(auth.uid(), player_id))
);

drop policy if exists "sd_facility_bookings_insert" on public.sd_facility_bookings;
create policy "sd_facility_bookings_insert"
on public.sd_facility_bookings
for insert
with check (
  (
    public.sd_is_coach(auth.uid())
    and created_by = auth.uid()
    and (is_block or (player_id is not null))
  )
  or (
    created_by = auth.uid()
    and is_block = false
    and status = 'pending'
    and approved_by is null
    and approved_at is null
    and (
      player_id = auth.uid()
      or (player_id is not null and public.sd_is_linked_parent(auth.uid(), player_id))
    )
  )
);

drop policy if exists "sd_facility_bookings_update" on public.sd_facility_bookings;
create policy "sd_facility_bookings_update"
on public.sd_facility_bookings
for update
using (
  public.sd_is_coach(auth.uid())
  or (
    created_by = auth.uid()
    and is_block = false
    and status = 'pending'
  )
)
with check (
  public.sd_is_coach(auth.uid())
  or (
    created_by = auth.uid()
    and is_block = false
    and status in ('pending', 'cancelled')
  )
);
