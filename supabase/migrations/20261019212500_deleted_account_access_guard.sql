-- Complements transactional Auth soft deletion in 20261019212000. Retaining
-- referenced UUIDs must not let an already-issued JWT keep database access.
-- Local candidate only. Inspect production hooks/publications/policies first.
-- An unknown existing API hook aborts this transaction instead of replacing it.
-- Rollback: restore a reviewed equivalent guard before removing these policies
-- or the hook. Do not restore access for deleted principals as a rollback.
begin;

do $$
declare
  v_setting text;
  v_table record;
begin
  -- Role catalogs cannot reveal environment/db-pre-config overrides. An
  -- operator must inspect the effective live PostgREST configuration first.
  if current_setting('app.homeplate_api_hook_preflight', true) is distinct from
      'verified_no_other_effective_hook' then
    raise exception 'effective_api_hook_preflight_required';
  end if;
  for v_setting in
    select option from pg_db_role_setting s
    join pg_roles r on r.oid = s.setrole
    cross join lateral unnest(s.setconfig) as options(option)
    where r.rolname = 'authenticator'
      and s.setdatabase in (0, (select oid from pg_database where datname = current_database()))
      and option like 'pgrst.db_pre_request=%'
  loop
    if btrim(substr(v_setting, strpos(v_setting, '=') + 1)) not in ('', 'public.sd_require_active_account') then
      raise exception 'existing_api_pre_request_requires_review';
    end if;
  end loop;
  -- Postgres Changes must evaluate the active-account guard through RLS.
  for v_table in
    select t.schemaname, t.tablename, c.relrowsecurity
    from pg_publication_tables t
    join pg_namespace n on n.nspname = t.schemaname
    join pg_class c on c.relnamespace = n.oid and c.relname = t.tablename
    where t.pubname = 'supabase_realtime' and t.schemaname = 'public'
  loop
    if not v_table.relrowsecurity then
      raise exception 'realtime_table_requires_rls: %.%', v_table.schemaname, v_table.tablename;
    end if;
  end loop;
  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'storage' and c.relname = 'objects' and c.relrowsecurity
  ) then raise exception 'storage_objects_rls_required'; end if;
  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'realtime' and c.relname = 'messages' and c.relrowsecurity
  ) then raise exception 'realtime_messages_rls_required'; end if;
end;
$$;

create or replace function public.sd_account_is_active()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from auth.users u
    where u.id = (select auth.uid()) and u.deleted_at is null
  );
$$;
revoke all on function public.sd_account_is_active() from public, anon;
grant execute on function public.sd_account_is_active() to authenticated, service_role;

create or replace function public.sd_require_active_account()
returns void language plpgsql stable security invoker set search_path = '' as $$
begin
  if auth.role() is distinct from 'authenticated' then return; end if;
  if not public.sd_account_is_active() then
    raise exception using errcode = '42501', message = 'account_not_active';
  end if;
end;
$$;
revoke all on function public.sd_require_active_account() from public;
grant execute on function public.sd_require_active_account() to anon, authenticated, service_role;

do $$
declare v_table record;
begin
  -- A restrictive policy adds an AND condition; it never grants new access.
  -- The scalar subquery permits one account lookup per statement, not per row.
  for v_table in
    select n.nspname, c.relname
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where c.relkind in ('r', 'p') and c.relrowsecurity
      and (n.nspname = 'public'
        or (n.nspname = 'storage' and c.relname = 'objects')
        or (n.nspname = 'realtime' and c.relname = 'messages'))
  loop
    execute format('drop policy if exists sd_active_account_required on %I.%I',
      v_table.nspname, v_table.relname);
    execute format(
      'create policy sd_active_account_required on %I.%I as restrictive for all to authenticated '
      'using ((select public.sd_account_is_active())) '
      'with check ((select public.sd_account_is_active()))',
      v_table.nspname, v_table.relname
    );
  end loop;
end;
$$;

-- Covers Data API SECURITY DEFINER RPCs/views, which bypass table RLS.
-- Anonymous catalog access and privileged service-role operations remain valid.
alter role authenticator set pgrst.db_pre_request = 'public.sd_require_active_account';
-- A database-specific empty setting would otherwise override the role default.
do $$
begin
  execute format(
    'alter role authenticator in database %I set pgrst.db_pre_request = %L',
    current_database(), 'public.sd_require_active_account'
  );
end;
$$;
notify pgrst, 'reload config';
commit;
