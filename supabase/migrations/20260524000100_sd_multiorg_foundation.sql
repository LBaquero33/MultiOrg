-- Multi-organization foundation (shared Supabase project).
--
-- Design:
-- - `sd_orgs` is readable by all authenticated users (for an org dropdown).
-- - All tenant data should be scoped by `org_id`.
-- - Membership defines access + role in an org.
--
-- NOTE: This migration only introduces org tables + helpers. Converting existing feature tables
-- to include `org_id` and enforcing org-scoped RLS is a follow-up migration.

create extension if not exists pgcrypto;

-- 1) Organizations
create table if not exists public.sd_orgs (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  website_host text null,
  support_email text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Allow app to list orgs for the dropdown.
alter table public.sd_orgs enable row level security;
grant select on table public.sd_orgs to anon, authenticated;
drop policy if exists "sd_orgs_select_all" on public.sd_orgs;
create policy "sd_orgs_select_all" on public.sd_orgs
  for select
  to anon, authenticated
  using (true);

-- 2) Memberships (per org)
create table if not exists public.sd_org_memberships (
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','coach','player','parent')),
  status text not null default 'active' check (status in ('active','invited','disabled')),
  created_at timestamptz not null default now(),
  created_by uuid null references auth.users(id) on delete set null,
  primary key (org_id, user_id)
);

alter table public.sd_org_memberships enable row level security;
grant select on table public.sd_org_memberships to authenticated;
grant insert, update, delete on table public.sd_org_memberships to authenticated;

-- Helper: is the current user an active member of org?
create or replace function public.sd_is_org_member(org uuid)
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
  );
$$;

-- Helper: is current user a coach/owner in org?
create or replace function public.sd_is_org_coach(org uuid)
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

-- Members can see their own memberships.
drop policy if exists "sd_org_memberships_select_own" on public.sd_org_memberships;
create policy "sd_org_memberships_select_own" on public.sd_org_memberships
  for select
  to authenticated
  using (user_id = auth.uid());

-- Owners/coaches can manage memberships inside their org (v1).
drop policy if exists "sd_org_memberships_manage_by_coach" on public.sd_org_memberships;
create policy "sd_org_memberships_manage_by_coach" on public.sd_org_memberships
  for all
  to authenticated
  using (public.sd_is_org_coach(org_id))
  with check (public.sd_is_org_coach(org_id));

-- 3) Org-scoped usernames (maps org+username -> user)
create table if not exists public.sd_org_usernames (
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  username text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  created_by uuid null references auth.users(id) on delete set null,
  primary key (org_id, username)
);

create index if not exists sd_org_usernames_user_id_idx on public.sd_org_usernames(user_id);

alter table public.sd_org_usernames enable row level security;
-- NO direct client access. This table is intended to be used via a server-side Edge Function
-- (with a service role key) to resolve username->user_id during org-scoped login.
revoke all on table public.sd_org_usernames from anon, authenticated;

-- 4) Seed a starter org (optional)
-- Insert a placeholder org if none exist so developers can sign in and test.
do $$
begin
  if not exists (select 1 from public.sd_orgs) then
    insert into public.sd_orgs (slug, name)
    values ('demo', 'Demo Organization');
  end if;
end $$;
