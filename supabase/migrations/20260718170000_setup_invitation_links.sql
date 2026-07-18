-- Phase 12ZA: signed setup invitation links and optional team setup metadata.
-- Raw invitation tokens are returned once by the Edge Function and are never
-- persisted. Only their SHA-256 digest is stored.

alter table public.sd_teams
  add column if not exists age_group text,
  add column if not exists competitive_level text,
  add column if not exists roster_capacity integer;

alter table public.sd_teams
  drop constraint if exists sd_teams_roster_capacity_check;
alter table public.sd_teams
  add constraint sd_teams_roster_capacity_check
  check (roster_capacity is null or roster_capacity between 1 and 1000);

create table if not exists public.sd_organization_invitation_links (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  invitation_context text not null check (invitation_context in ('family','staff')),
  intended_role text not null check (intended_role in ('parent','coach')),
  intended_team_id uuid references public.sd_teams(id) on delete restrict,
  intended_responsibilities text[] not null default '{}'::text[],
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  token_version integer not null default 1 check (token_version > 0),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  accepted_at timestamptz,
  last_rotated_at timestamptz,
  use_count integer not null default 0 check (use_count >= 0),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  check ((invitation_context = 'family' and intended_role = 'parent') or
         (invitation_context = 'staff' and intended_role = 'coach')),
  check (invitation_context = 'staff' or intended_team_id is null),
  check (expires_at > created_at)
);

create unique index if not exists uq_sd_org_invitation_active_context
  on public.sd_organization_invitation_links(organization_id, invitation_context)
  where revoked_at is null;
create index if not exists idx_sd_org_invitation_lookup
  on public.sd_organization_invitation_links(token_hash)
  where revoked_at is null;
create index if not exists idx_sd_org_invitation_org_created
  on public.sd_organization_invitation_links(organization_id, created_at desc);

create table if not exists public.sd_organization_invitation_acceptances (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  invitation_link_id uuid not null references public.sd_organization_invitation_links(id) on delete restrict,
  organization_id uuid not null references public.sd_orgs(id) on delete restrict,
  accepted_by uuid not null references auth.users(id) on delete restrict,
  accepted_role text not null check (accepted_role in ('parent','coach')),
  accepted_at timestamptz not null default pg_catalog.now(),
  details jsonb not null default '{}'::jsonb check (pg_catalog.jsonb_typeof(details) = 'object'),
  unique (invitation_link_id, accepted_by)
);

create index if not exists idx_sd_org_invitation_acceptance_audit
  on public.sd_organization_invitation_acceptances(organization_id, accepted_at desc);

alter table public.sd_organization_invitation_links enable row level security;
alter table public.sd_organization_invitation_acceptances enable row level security;

-- Invitation material is intentionally unavailable through PostgREST. All
-- reads and mutations go through the server-authorized invitation function.
revoke all on table public.sd_organization_invitation_links from public, anon, authenticated;
revoke all on table public.sd_organization_invitation_acceptances from public, anon, authenticated;
grant all on table public.sd_organization_invitation_links to service_role;
grant all on table public.sd_organization_invitation_acceptances to service_role;

-- Rollback: stop the invitation function, drop the two invitation tables, then
-- drop sd_teams.age_group, competitive_level, and roster_capacity. Existing
-- organizations, memberships, teams, financial records, and operations are not
-- rewritten by this migration.
