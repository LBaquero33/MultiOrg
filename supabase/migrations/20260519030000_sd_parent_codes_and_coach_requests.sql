-- Parent codes: each player has a shareable code that a parent can use during signup
-- to link themselves to the child account (no email invite required).
--
-- Also adds a minimal "coach signup request" table so the app can show a "Coach" option
-- without letting anyone self-escalate to coach.

create extension if not exists pgcrypto;

-- Generate a short, human-friendly code (no I/O/1/0).
create or replace function public.sd_generate_parent_code(size int default 8)
returns text
language plpgsql
volatile
as $$
declare
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  bytes bytea := gen_random_bytes(size);
  out text := '';
  i int;
  idx int;
begin
  if size < 4 then
    size := 4;
  end if;

  for i in 0..(size - 1) loop
    idx := (get_byte(bytes, i) % length(alphabet)) + 1;
    out := out || substr(alphabet, idx, 1);
  end loop;
  return out;
end;
$$;

-- One code per child.
create table if not exists public.sd_parent_codes (
  child_id uuid primary key references auth.users(id) on delete cascade,
  parent_code text not null unique,
  created_at timestamptz not null default now(),
  rotated_at timestamptz
);

alter table public.sd_parent_codes enable row level security;

-- Child + coaches can view the code.
drop policy if exists "sd_parent_codes_select_child_or_coach" on public.sd_parent_codes;
create policy "sd_parent_codes_select_child_or_coach"
on public.sd_parent_codes
for select
to authenticated
using (
  child_id = auth.uid()
  or public.sd_is_coach(auth.uid())
);

-- Coaches can rotate codes if needed (service_role can do anything anyway).
drop policy if exists "sd_parent_codes_coach_write" on public.sd_parent_codes;
create policy "sd_parent_codes_coach_write"
on public.sd_parent_codes
for all
to authenticated
using (public.sd_is_coach(auth.uid()))
with check (public.sd_is_coach(auth.uid()));

-- Backfill codes for existing players.
insert into public.sd_parent_codes(child_id, parent_code)
select p.id, public.sd_generate_parent_code(8)
from public.profiles p
where p.role = 'player'
  and not exists (select 1 from public.sd_parent_codes c where c.child_id = p.id);

-- Coach signup requests (optional flow; coaches are still admin-controlled).
create table if not exists public.sd_coach_signup_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  email_norm text not null,
  full_name text,
  notes text,
  status text not null default 'requested', -- requested|approved|rejected
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_sd_coach_signup_requests_status on public.sd_coach_signup_requests(status, created_at desc);
create index if not exists idx_sd_coach_signup_requests_user on public.sd_coach_signup_requests(user_id);

alter table public.sd_coach_signup_requests enable row level security;

-- Requester can see their own request.
drop policy if exists "sd_coach_signup_requests_select_own" on public.sd_coach_signup_requests;
create policy "sd_coach_signup_requests_select_own"
on public.sd_coach_signup_requests
for select
to authenticated
using (user_id = auth.uid());

-- Requester can insert only once for themselves.
drop policy if exists "sd_coach_signup_requests_insert_own" on public.sd_coach_signup_requests;
create policy "sd_coach_signup_requests_insert_own"
on public.sd_coach_signup_requests
for insert
to authenticated
with check (user_id = auth.uid() and status = 'requested');

-- Coaches can review/manage requests.
drop policy if exists "sd_coach_signup_requests_coach_all" on public.sd_coach_signup_requests;
create policy "sd_coach_signup_requests_coach_all"
on public.sd_coach_signup_requests
for all
to authenticated
using (public.sd_is_coach(auth.uid()))
with check (public.sd_is_coach(auth.uid()));

drop trigger if exists sd_coach_signup_requests_touch on public.sd_coach_signup_requests;
create trigger sd_coach_signup_requests_touch
before update on public.sd_coach_signup_requests
for each row execute function public.sd_touch_updated_at();

