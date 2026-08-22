begin;

-- Retire the original single-organization public surface without deleting it.
-- Active Home Plate clients use the sd_* schema. Service-role maintenance keeps
-- working because service_role bypasses RLS.
do $legacy$
declare
  table_name text;
begin
  foreach table_name in array array[
    'attendance', 'conversation_participants', 'conversations', 'device_tokens',
    'event_participants', 'events', 'facilities', 'facility_bookings',
    'facility_resources', 'invitations', 'memberships', 'messages',
    'notifications', 'organizations', 'parent_child_links',
    'password_reset_tokens', 'player_profiles', 'program_assignments',
    'program_completions', 'program_days', 'program_exercises', 'programs',
    'seasons', 'team_members', 'teams', 'testing_categories',
    'testing_results', 'testing_sessions', 'users'
  ] loop
    if pg_catalog.to_regclass('public.' || table_name) is not null then
      execute pg_catalog.format('alter table public.%I enable row level security', table_name);
      execute pg_catalog.format('revoke all on table public.%I from anon, authenticated', table_name);
    end if;
  end loop;
end
$legacy$;

create table if not exists public.sd_expense_categories (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 80),
  normalized_name text generated always as (lower(btrim(name))) stored,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  unique (org_id, normalized_name)
);

create index if not exists idx_sd_expense_categories_org_active_sort
  on public.sd_expense_categories(org_id, is_active, sort_order, name);

alter table public.sd_expense_categories enable row level security;

drop policy if exists "expense categories owner admin read" on public.sd_expense_categories;
create policy "expense categories owner admin read"
  on public.sd_expense_categories for select to authenticated
  using (public.sd_is_org_admin(org_id));

-- Category writes are performed only by the JWT-verifying finance-dashboard
-- function or by an authenticated owner/admin protected by the policies below.
drop policy if exists "expense categories owner admin create" on public.sd_expense_categories;
create policy "expense categories owner admin create"
  on public.sd_expense_categories for insert to authenticated
  with check (
    public.sd_is_org_admin(org_id)
    and created_by = (select auth.uid())
  );

drop policy if exists "expense categories owner admin update" on public.sd_expense_categories;
create policy "expense categories owner admin update"
  on public.sd_expense_categories for update to authenticated
  using (public.sd_is_org_admin(org_id))
  with check (public.sd_is_org_admin(org_id));

revoke delete on public.sd_expense_categories from anon, authenticated;
grant select, insert, update on public.sd_expense_categories to authenticated;

alter table public.sd_expenses
  add column if not exists category_id uuid references public.sd_expense_categories(id) on delete set null;

create index if not exists idx_sd_expenses_category
  on public.sd_expenses(org_id, category_id, expense_date desc);

create or replace function public.sd_seed_expense_categories(p_org_id uuid, p_actor_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  category_name text;
  category_index integer := 0;
begin
  if p_org_id is null or not exists (select 1 from public.sd_orgs where id = p_org_id) then
    raise exception 'organization_not_found' using errcode = 'P0002';
  end if;
  foreach category_name in array array[
    'Facility Rent', 'League Fees', 'Umpire Fees', 'Equipment',
    'Tournament Fees', 'Travel', 'Insurance', 'Payroll/Contractors',
    'Utilities', 'Marketing', 'Other'
  ] loop
    insert into public.sd_expense_categories(org_id, name, sort_order, created_by)
    values (p_org_id, category_name, category_index * 10, p_actor_id)
    on conflict (org_id, normalized_name) do nothing;
    category_index := category_index + 1;
  end loop;
end;
$$;

revoke all on function public.sd_seed_expense_categories(uuid, uuid) from public, anon, authenticated;
grant execute on function public.sd_seed_expense_categories(uuid, uuid) to service_role;

create or replace function public.sd_seed_new_org_expense_categories()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.sd_seed_expense_categories(new.id, null);
  return new;
end;
$$;

revoke all on function public.sd_seed_new_org_expense_categories() from public, anon, authenticated;
grant execute on function public.sd_seed_new_org_expense_categories() to service_role;

drop trigger if exists trg_sd_org_seed_expense_categories on public.sd_orgs;
create trigger trg_sd_org_seed_expense_categories
after insert on public.sd_orgs
for each row execute function public.sd_seed_new_org_expense_categories();

do $seed$
declare
  organization_id uuid;
begin
  for organization_id in select id from public.sd_orgs loop
    perform public.sd_seed_expense_categories(organization_id, null);
  end loop;
end
$seed$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'organization-expense-receipts',
  'organization-expense-receipts',
  false,
  20971520,
  array['image/jpeg', 'image/png', 'image/heic', 'application/pdf']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "finance admins upload receipts" on storage.objects;
create policy "finance admins upload receipts"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'organization-expense-receipts'
  and owner_id = (select auth.uid()::text)
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and public.sd_is_org_admin(((storage.foldername(name))[1])::uuid)
);

drop policy if exists "finance admins read receipts" on storage.objects;
create policy "finance admins read receipts"
on storage.objects for select to authenticated
using (
  bucket_id = 'organization-expense-receipts'
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and public.sd_is_org_admin(((storage.foldername(name))[1])::uuid)
);

drop policy if exists "finance admins replace receipts" on storage.objects;
create policy "finance admins replace receipts"
on storage.objects for update to authenticated
using (
  bucket_id = 'organization-expense-receipts'
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and public.sd_is_org_admin(((storage.foldername(name))[1])::uuid)
)
with check (
  bucket_id = 'organization-expense-receipts'
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and public.sd_is_org_admin(((storage.foldername(name))[1])::uuid)
);

drop policy if exists "finance admins delete receipts" on storage.objects;
create policy "finance admins delete receipts"
on storage.objects for delete to authenticated
using (
  bucket_id = 'organization-expense-receipts'
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and public.sd_is_org_admin(((storage.foldername(name))[1])::uuid)
);

commit;
