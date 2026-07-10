-- Legacy auth bridge mapping table.
-- Links legacy Shiny `public.users` accounts to Supabase Auth users.

create table if not exists public.legacy_auth_links (
  legacy_username text primary key,
  legacy_user_id bigint,
  auth_user_id uuid,
  email text,
  role text,
  player_full_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_login_at timestamptz
);

create index if not exists idx_legacy_auth_links_auth_user_id on public.legacy_auth_links(auth_user_id);

alter table public.legacy_auth_links enable row level security;

-- No policies on purpose: this table should only be accessed by service-role (Edge Function).

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_legacy_auth_links_updated_at on public.legacy_auth_links;
create trigger trg_legacy_auth_links_updated_at
before update on public.legacy_auth_links
for each row
execute function public.set_updated_at();
