-- Platform-wide administration, organization billing metadata, and coach-managed teams.

alter table public.sd_orgs
  add column if not exists status text not null default 'active'
    check (status in ('active', 'suspended', 'archived')),
  add column if not exists plan text not null default 'starter',
  add column if not exists billing_email text,
  add column if not exists max_members integer;

create table if not exists public.sd_platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  granted_at timestamptz not null default now(),
  granted_by uuid references auth.users(id) on delete set null,
  notes text
);

alter table public.sd_platform_admins enable row level security;

create table if not exists public.sd_platform_audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  target_type text not null,
  target_id text,
  org_id uuid references public.sd_orgs(id) on delete set null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.sd_platform_audit_logs enable row level security;
create index if not exists idx_sd_platform_audit_logs_created_at
  on public.sd_platform_audit_logs(created_at desc);

create table if not exists public.sd_teams (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  name text not null,
  color_hex text,
  description text,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, name)
);

create table if not exists public.sd_team_members (
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  team_id uuid not null references public.sd_teams(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  assigned_by uuid references auth.users(id) on delete set null,
  assigned_at timestamptz not null default now(),
  primary key (org_id, player_id)
);

create index if not exists idx_sd_teams_org on public.sd_teams(org_id, sort_order, name);
create index if not exists idx_sd_team_members_team on public.sd_team_members(team_id);

alter table public.sd_teams enable row level security;
alter table public.sd_team_members enable row level security;

-- The authenticated app uses the server-authorized org_admin function for mutations.
drop policy if exists "sd_teams_select_member" on public.sd_teams;
create policy "sd_teams_select_member" on public.sd_teams for select to authenticated
  using (exists (
    select 1 from public.sd_org_memberships m
    where m.org_id = sd_teams.org_id and m.user_id = auth.uid() and m.status = 'active'
  ));

drop policy if exists "sd_team_members_select_member" on public.sd_team_members;
create policy "sd_team_members_select_member" on public.sd_team_members for select to authenticated
  using (exists (
    select 1 from public.sd_org_memberships m
    where m.org_id = sd_team_members.org_id and m.user_id = auth.uid() and m.status = 'active'
  ));

-- Initial platform administrator for the MultiOrg owner account.
insert into public.sd_platform_admins (user_id, notes)
values ('6e34ac24-0a94-4dbb-9941-3f0248493fbb', 'Initial MultiOrg platform administrator')
on conflict (user_id) do nothing;
