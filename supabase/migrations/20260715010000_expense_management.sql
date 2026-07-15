-- Home Plate Phase 8B expense management.
--
-- Expenses are archived instead of deleted. Direct authenticated mutations are
-- removed; the JWT-verifying finance-dashboard Edge Function invokes the three
-- service-role-only functions below. Each mutation and its minimal audit entry
-- commit in one PostgreSQL transaction.
--
-- Rollback: deploy a read-only finance-dashboard function first, drop the three
-- functions and active-expense index, restore the prior expense policies only
-- if broad direct access is intentionally desired, then drop archived_by and
-- archived_at. Preserve sd_platform_audit_logs rows as historical records.

alter table public.sd_expenses
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid references auth.users(id) on delete set null;

create index if not exists idx_sd_expenses_org_active_date
  on public.sd_expenses(org_id, expense_date desc)
  where archived_at is null;

-- The finance-dashboard service authorizes reads and support mode. Retain a
-- narrow owner/admin direct-read policy for compatibility, but remove all
-- direct authenticated writes, including coach/staff and implicit platform
-- administrator writes.
drop policy if exists "sd_expenses_select_staff" on public.sd_expenses;
drop policy if exists "sd_expenses_write_staff" on public.sd_expenses;
drop policy if exists "sd_expenses_select_owner_admin" on public.sd_expenses;
create policy "sd_expenses_select_owner_admin"
  on public.sd_expenses
  for select
  to authenticated
  using (public.sd_is_org_admin(org_id));

create or replace function public.sd_create_expense(
  p_org_id uuid,
  p_actor_id uuid,
  p_category text,
  p_description text,
  p_amount_cents integer,
  p_currency text,
  p_expense_date date,
  p_vendor text,
  p_notes text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expense public.sd_expenses%rowtype;
  v_currency text := pg_catalog.lower(pg_catalog.btrim(p_currency));
begin
  if p_org_id is null or p_actor_id is null then
    raise exception 'invalid_expense' using errcode = '22023';
  end if;
  if not exists (
    select 1
    from public.sd_orgs organization
    where organization.id = p_org_id
      and organization.status = 'active'
  ) then
    raise exception 'organization_inactive_or_missing' using errcode = 'P0001';
  end if;
  if not exists (
    select 1
    from public.sd_org_memberships actor
    where actor.org_id = p_org_id
      and actor.user_id = p_actor_id
      and actor.role in ('owner', 'admin')
      and actor.status = 'active'
  ) then
    raise exception 'organization_admin_required' using errcode = 'P0001';
  end if;
  if p_amount_cents is null or p_amount_cents <= 0 or p_amount_cents > 10000000 then
    raise exception 'invalid_expense_amount' using errcode = '22023';
  end if;
  if p_category is null or pg_catalog.length(pg_catalog.btrim(p_category)) not between 1 and 80 then
    raise exception 'invalid_expense_category' using errcode = '22023';
  end if;
  if p_description is null or pg_catalog.length(pg_catalog.btrim(p_description)) not between 1 and 200 then
    raise exception 'invalid_expense_description' using errcode = '22023';
  end if;
  if v_currency is null or v_currency !~ '^[a-z]{3}$' then
    raise exception 'invalid_expense_currency' using errcode = '22023';
  end if;
  if p_expense_date is null then
    raise exception 'invalid_expense_date' using errcode = '22023';
  end if;
  if p_vendor is not null and pg_catalog.length(pg_catalog.btrim(p_vendor)) > 120 then
    raise exception 'invalid_expense_vendor' using errcode = '22023';
  end if;
  if p_notes is not null and pg_catalog.length(pg_catalog.btrim(p_notes)) > 2000 then
    raise exception 'invalid_expense_notes' using errcode = '22023';
  end if;

  insert into public.sd_expenses (
    org_id, created_by, category, description, amount_cents, currency,
    expense_date, vendor, notes
  ) values (
    p_org_id,
    p_actor_id,
    pg_catalog.btrim(p_category),
    pg_catalog.btrim(p_description),
    p_amount_cents,
    v_currency,
    p_expense_date,
    nullif(pg_catalog.btrim(p_vendor), ''),
    nullif(pg_catalog.btrim(p_notes), '')
  ) returning * into v_expense;

  insert into public.sd_platform_audit_logs (
    actor_id, action, target_type, target_id, org_id, details
  ) values (
    p_actor_id,
    'expense_created',
    'expense',
    v_expense.id::text,
    p_org_id,
    pg_catalog.jsonb_build_object(
      'changed_fields', pg_catalog.to_jsonb(array[
        'category', 'description', 'amount_cents', 'currency',
        'expense_date', 'vendor', 'notes'
      ]::text[])
    )
  );

  return pg_catalog.jsonb_build_object(
    'expense', pg_catalog.jsonb_build_object(
      'id', v_expense.id,
      'org_id', v_expense.org_id,
      'category', v_expense.category,
      'description', v_expense.description,
      'amount_cents', v_expense.amount_cents,
      'currency', v_expense.currency,
      'expense_date', v_expense.expense_date,
      'vendor', v_expense.vendor,
      'notes', v_expense.notes,
      'created_at', v_expense.created_at,
      'updated_at', v_expense.updated_at,
      'archived_at', v_expense.archived_at,
      'archived_by', v_expense.archived_by
    )
  );
end;
$$;

create or replace function public.sd_update_expense(
  p_org_id uuid,
  p_actor_id uuid,
  p_expense_id uuid,
  p_category text,
  p_description text,
  p_amount_cents integer,
  p_currency text,
  p_expense_date date,
  p_vendor text,
  p_notes text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expense public.sd_expenses%rowtype;
  v_currency text := pg_catalog.lower(pg_catalog.btrim(p_currency));
  v_category text := pg_catalog.btrim(p_category);
  v_description text := pg_catalog.btrim(p_description);
  v_vendor text := nullif(pg_catalog.btrim(p_vendor), '');
  v_notes text := nullif(pg_catalog.btrim(p_notes), '');
  v_changed_fields text[] := '{}'::text[];
begin
  if p_org_id is null or p_actor_id is null or p_expense_id is null then
    raise exception 'invalid_expense' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.sd_orgs organization
    where organization.id = p_org_id and organization.status = 'active'
  ) then
    raise exception 'organization_inactive_or_missing' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.sd_org_memberships actor
    where actor.org_id = p_org_id
      and actor.user_id = p_actor_id
      and actor.role in ('owner', 'admin')
      and actor.status = 'active'
  ) then
    raise exception 'organization_admin_required' using errcode = 'P0001';
  end if;
  if p_amount_cents is null or p_amount_cents <= 0 or p_amount_cents > 10000000 then
    raise exception 'invalid_expense_amount' using errcode = '22023';
  end if;
  if p_category is null or pg_catalog.length(v_category) not between 1 and 80 then
    raise exception 'invalid_expense_category' using errcode = '22023';
  end if;
  if p_description is null or pg_catalog.length(v_description) not between 1 and 200 then
    raise exception 'invalid_expense_description' using errcode = '22023';
  end if;
  if v_currency is null or v_currency !~ '^[a-z]{3}$' then
    raise exception 'invalid_expense_currency' using errcode = '22023';
  end if;
  if p_expense_date is null then
    raise exception 'invalid_expense_date' using errcode = '22023';
  end if;
  if p_vendor is not null and pg_catalog.length(pg_catalog.btrim(p_vendor)) > 120 then
    raise exception 'invalid_expense_vendor' using errcode = '22023';
  end if;
  if p_notes is not null and pg_catalog.length(pg_catalog.btrim(p_notes)) > 2000 then
    raise exception 'invalid_expense_notes' using errcode = '22023';
  end if;

  select expense.* into v_expense
  from public.sd_expenses expense
  where expense.org_id = p_org_id and expense.id = p_expense_id
  for update;
  if v_expense.id is null then
    raise exception 'expense_not_found' using errcode = 'P0001';
  end if;
  if v_expense.archived_at is not null then
    raise exception 'expense_archived' using errcode = 'P0001';
  end if;

  if v_expense.category is distinct from v_category then v_changed_fields := pg_catalog.array_append(v_changed_fields, 'category'); end if;
  if v_expense.description is distinct from v_description then v_changed_fields := pg_catalog.array_append(v_changed_fields, 'description'); end if;
  if v_expense.amount_cents is distinct from p_amount_cents then v_changed_fields := pg_catalog.array_append(v_changed_fields, 'amount_cents'); end if;
  if v_expense.currency is distinct from v_currency then v_changed_fields := pg_catalog.array_append(v_changed_fields, 'currency'); end if;
  if v_expense.expense_date is distinct from p_expense_date then v_changed_fields := pg_catalog.array_append(v_changed_fields, 'expense_date'); end if;
  if v_expense.vendor is distinct from v_vendor then v_changed_fields := pg_catalog.array_append(v_changed_fields, 'vendor'); end if;
  if v_expense.notes is distinct from v_notes then v_changed_fields := pg_catalog.array_append(v_changed_fields, 'notes'); end if;

  if pg_catalog.cardinality(v_changed_fields) > 0 then
    update public.sd_expenses expense
    set category = v_category,
        description = v_description,
        amount_cents = p_amount_cents,
        currency = v_currency,
        expense_date = p_expense_date,
        vendor = v_vendor,
        notes = v_notes
    where expense.org_id = p_org_id and expense.id = p_expense_id
    returning * into v_expense;

    insert into public.sd_platform_audit_logs (
      actor_id, action, target_type, target_id, org_id, details
    ) values (
      p_actor_id,
      'expense_updated',
      'expense',
      v_expense.id::text,
      p_org_id,
      pg_catalog.jsonb_build_object(
        'changed_fields', pg_catalog.to_jsonb(v_changed_fields)
      )
    );
  end if;

  return pg_catalog.jsonb_build_object(
    'expense', pg_catalog.jsonb_build_object(
      'id', v_expense.id,
      'org_id', v_expense.org_id,
      'category', v_expense.category,
      'description', v_expense.description,
      'amount_cents', v_expense.amount_cents,
      'currency', v_expense.currency,
      'expense_date', v_expense.expense_date,
      'vendor', v_expense.vendor,
      'notes', v_expense.notes,
      'created_at', v_expense.created_at,
      'updated_at', v_expense.updated_at,
      'archived_at', v_expense.archived_at,
      'archived_by', v_expense.archived_by
    )
  );
end;
$$;

create or replace function public.sd_archive_expense(
  p_org_id uuid,
  p_actor_id uuid,
  p_expense_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expense public.sd_expenses%rowtype;
begin
  if p_org_id is null or p_actor_id is null or p_expense_id is null then
    raise exception 'invalid_expense' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.sd_orgs organization
    where organization.id = p_org_id and organization.status = 'active'
  ) then
    raise exception 'organization_inactive_or_missing' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.sd_org_memberships actor
    where actor.org_id = p_org_id
      and actor.user_id = p_actor_id
      and actor.role in ('owner', 'admin')
      and actor.status = 'active'
  ) then
    raise exception 'organization_admin_required' using errcode = 'P0001';
  end if;

  select expense.* into v_expense
  from public.sd_expenses expense
  where expense.org_id = p_org_id and expense.id = p_expense_id
  for update;
  if v_expense.id is null then
    raise exception 'expense_not_found' using errcode = 'P0001';
  end if;
  if v_expense.archived_at is not null then
    raise exception 'expense_already_archived' using errcode = 'P0001';
  end if;

  update public.sd_expenses expense
  set archived_at = pg_catalog.now(), archived_by = p_actor_id
  where expense.org_id = p_org_id and expense.id = p_expense_id
  returning * into v_expense;

  insert into public.sd_platform_audit_logs (
    actor_id, action, target_type, target_id, org_id, details
  ) values (
    p_actor_id,
    'expense_archived',
    'expense',
    v_expense.id::text,
    p_org_id,
    pg_catalog.jsonb_build_object(
      'changed_fields', pg_catalog.to_jsonb(array['archived_at', 'archived_by']::text[])
    )
  );

  return pg_catalog.jsonb_build_object(
    'expense', pg_catalog.jsonb_build_object(
      'id', v_expense.id,
      'org_id', v_expense.org_id,
      'category', v_expense.category,
      'description', v_expense.description,
      'amount_cents', v_expense.amount_cents,
      'currency', v_expense.currency,
      'expense_date', v_expense.expense_date,
      'vendor', v_expense.vendor,
      'notes', v_expense.notes,
      'created_at', v_expense.created_at,
      'updated_at', v_expense.updated_at,
      'archived_at', v_expense.archived_at,
      'archived_by', v_expense.archived_by
    )
  );
end;
$$;

revoke all on function public.sd_create_expense(
  uuid, uuid, text, text, integer, text, date, text, text
) from public, anon, authenticated;
grant execute on function public.sd_create_expense(
  uuid, uuid, text, text, integer, text, date, text, text
) to service_role;

revoke all on function public.sd_update_expense(
  uuid, uuid, uuid, text, text, integer, text, date, text, text
) from public, anon, authenticated;
grant execute on function public.sd_update_expense(
  uuid, uuid, uuid, text, text, integer, text, date, text, text
) to service_role;

revoke all on function public.sd_archive_expense(uuid, uuid, uuid)
from public, anon, authenticated;
grant execute on function public.sd_archive_expense(uuid, uuid, uuid)
to service_role;
