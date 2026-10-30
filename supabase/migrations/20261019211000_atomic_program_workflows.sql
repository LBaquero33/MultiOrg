-- Requires 20261019210000_homeplate_auth_hardening.sql.
-- Local candidate only: apply to the verified production project with approval.
begin;

create or replace function public.sd_reorder_testing_fields(
  p_org_id uuid,
  p_field_id uuid,
  p_direction integer
) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_position integer;
  v_count integer;
begin
  if auth.uid() is null or not coalesce(
    public.sd_can_manage_player_development(p_org_id, auth.uid()), false
  ) then
    raise exception using errcode = '42501', message = 'development_management_required';
  end if;
  if p_direction is null or p_direction not in (-1, 1) then
    raise exception using errcode = '22023', message = 'invalid_reorder_direction';
  end if;

  -- All reorders in this organization serialize, including equal sort positions.
  perform pg_advisory_xact_lock(hashtextextended('hp-testing-order:' || p_org_id::text, 0));
  perform id from public.sd_testing_field_definitions
    where org_id = p_org_id and is_active order by id for update;

  select ordered.position, ordered.total into v_position, v_count
  from (
    select id, row_number() over (order by sort_order, label, id)::integer as position,
      count(*) over ()::integer as total
    from public.sd_testing_field_definitions
    where org_id = p_org_id and is_active
  ) ordered where ordered.id = p_field_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'testing_field_not_found';
  end if;
  if v_position + p_direction < 1 or v_position + p_direction > v_count then
    return false;
  end if;

  -- One statement in one transaction: a failed update cannot leave half a swap.
  with ordered as (
    select id, row_number() over (order by sort_order, label, id)::integer as position
    from public.sd_testing_field_definitions
    where org_id = p_org_id and is_active
  )
  update public.sd_testing_field_definitions f
  set sort_order = (case
    when o.position = v_position then v_position + p_direction
    when o.position = v_position + p_direction then v_position
    else o.position
  end) - 1
  from ordered o where f.id = o.id and f.org_id = p_org_id;
  return true;
end;
$$;

create or replace function public.sd_copy_program_template(
  p_org_id uuid,
  p_template_id uuid
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_source public.sd_program_templates%rowtype;
  v_copy_id uuid;
begin
  if auth.uid() is null or not coalesce(
    public.sd_can_manage_player_development(p_org_id, auth.uid()), false
  ) then
    raise exception using errcode = '42501', message = 'development_management_required';
  end if;

  select * into v_source from public.sd_program_templates
    where id = p_template_id and org_id = p_org_id and archived_at is null
    for share;
  if not found then
    raise exception using errcode = 'P0002', message = 'program_template_not_found';
  end if;
  -- Lock the source days for a consistent copy while their exercises are read.
  perform id from public.sd_program_days
    where template_id = v_source.id order by id for share;

  insert into public.sd_program_templates (
    org_id, coach_id, name, program_kind, weeks, lift_weekdays
  ) values (
    p_org_id, auth.uid(), v_source.name || ' Copy', v_source.program_kind,
    v_source.weeks, v_source.lift_weekdays
  ) returning id into v_copy_id;

  insert into public.sd_program_days (template_id, week, day_index, exercises)
    select v_copy_id, week, day_index, exercises
    from public.sd_program_days where template_id = v_source.id;
  -- Any day/trigger/constraint failure rolls back the header as well.
  return v_copy_id;
end;
$$;

revoke all on function public.sd_reorder_testing_fields(uuid, uuid, integer) from public, anon;
revoke all on function public.sd_copy_program_template(uuid, uuid) from public, anon;
grant execute on function public.sd_reorder_testing_fields(uuid, uuid, integer) to authenticated;
grant execute on function public.sd_copy_program_template(uuid, uuid) to authenticated;

commit;
