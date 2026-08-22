begin;

create table if not exists public.sd_testing_field_definitions (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  field_key text not null,
  label text not null,
  category text not null default 'General',
  unit text,
  value_type text not null default 'number',
  is_required boolean not null default false,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  config jsonb not null default '{}'::jsonb,
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sd_testing_field_definitions_key_format
    check (field_key ~ '^[a-z][a-z0-9_]{0,63}$'),
  constraint sd_testing_field_definitions_label_present
    check (length(btrim(label)) between 1 and 80),
  constraint sd_testing_field_definitions_category_present
    check (length(btrim(category)) between 1 and 60),
  constraint sd_testing_field_definitions_value_type
    check (value_type in ('number', 'text', 'time', 'boolean')),
  constraint sd_testing_field_definitions_config_object
    check (jsonb_typeof(config) = 'object'),
  unique (org_id, field_key)
);

create index if not exists idx_sd_testing_field_definitions_org_order
  on public.sd_testing_field_definitions(org_id, is_active desc, sort_order, label);

drop trigger if exists trg_sd_testing_field_definitions_updated_at
  on public.sd_testing_field_definitions;
create trigger trg_sd_testing_field_definitions_updated_at
before update on public.sd_testing_field_definitions
for each row execute function public.sd_set_updated_at();

alter table public.sd_testing_entries
  add column if not exists custom_values jsonb not null default '{}'::jsonb;

alter table public.sd_testing_entries
  drop constraint if exists sd_testing_entries_custom_values_object;
alter table public.sd_testing_entries
  add constraint sd_testing_entries_custom_values_object
  check (jsonb_typeof(custom_values) = 'object');

alter table public.sd_testing_field_definitions enable row level security;

revoke all on table public.sd_testing_field_definitions from public, anon;
grant select, insert, update, delete on table public.sd_testing_field_definitions to authenticated;
grant all on table public.sd_testing_field_definitions to service_role;

drop policy if exists "testing fields visible to organization members"
  on public.sd_testing_field_definitions;
create policy "testing fields visible to organization members"
on public.sd_testing_field_definitions for select to authenticated
using (public.sd_is_org_member(org_id));

drop policy if exists "testing fields managed by organization staff"
  on public.sd_testing_field_definitions;
create policy "testing fields managed by organization staff"
on public.sd_testing_field_definitions for all to authenticated
using (public.sd_is_org_staff(org_id))
with check (public.sd_is_org_staff(org_id));

insert into public.sd_testing_field_definitions (
  org_id, field_key, label, category, unit, value_type, sort_order, created_by
)
select
  org.id,
  seed.field_key,
  seed.label,
  seed.category,
  seed.unit,
  'number',
  seed.sort_order,
  creator.user_id
from public.sd_orgs org
join lateral (
  select membership.user_id
  from public.sd_org_memberships membership
  where membership.org_id = org.id
    and membership.status = 'active'
    and membership.role in ('owner', 'admin', 'coach')
  order by case membership.role when 'owner' then 0 when 'admin' then 1 else 2 end,
           membership.created_at
  limit 1
) creator on true
cross join (
  values
    ('height_in', 'Height', 'Body', 'in', 10),
    ('weight_lb', 'Body weight', 'Body', 'lb', 20),
    ('squat_1rm', 'Squat 1RM', 'Strength', 'lb', 30),
    ('bench_1rm', 'Bench 1RM', 'Strength', 'lb', 40),
    ('deadlift_1rm', 'Deadlift 1RM', 'Strength', 'lb', 50),
    ('max_exit_velo', 'Max exit velocity', 'Hitting', 'mph', 60),
    ('avg_exit_velo', 'Average exit velocity', 'Hitting', 'mph', 70),
    ('hip_er_diff', 'Hip ER difference', 'Mobility', 'deg', 80),
    ('hip_ir_diff', 'Hip IR difference', 'Mobility', 'deg', 90),
    ('shoulder_ir_diff', 'Shoulder IR difference', 'Mobility', 'deg', 100),
    ('shoulder_er_diff', 'Shoulder ER difference', 'Mobility', 'deg', 110)
) as seed(field_key, label, category, unit, sort_order)
on conflict (org_id, field_key) do nothing;

commit;
