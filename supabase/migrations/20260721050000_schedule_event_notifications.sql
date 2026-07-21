-- Phase 14B: deliver schedule intents through the existing notification/APNs
-- pipeline and create idempotent per-user reminders about 24 hours before an
-- event. This migration does not contact APNs and does not touch finance data.

alter table public.sd_team_event_notification_intents
  drop constraint if exists sd_team_event_notification_intents_intent_type_check;
alter table public.sd_team_event_notification_intents
  add constraint sd_team_event_notification_intents_intent_type_check check (intent_type in (
    'new_event','time_change','location_change','cancellation','postponement','availability_changed','player_unavailable','operation_started','arrival_reminder','event_completed','recap_published','late_schedule_change','attendance_correction',
    'practice_plan_published','practice_plan_major_change','practice_group_changed','practice_coach_assignment_changed','practice_equipment_reminder','practice_plan_ready','practice_completed','practice_recap_published',
    'game_plan_published','game_lineup_major_change','game_player_added','game_player_removed','game_assignment_changed','game_uniform_reminder','game_day_started','game_completed','game_result_published','game_recap_published',
    'event_reminder_24h'
  ));

create or replace function public.sd_deliver_team_event_notification_intent(
  p_intent_id uuid,
  p_dry_run boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  intent record;
  recipient record;
  preference jsonb;
  created_notification_id uuid;
  recipient_count integer := 0;
  delivered_count integer := 0;
  suppressed_count integer := 0;
  resolved_category text;
  preference_category text;
  notification_title text;
  notification_body text;
  required boolean := false;
begin
  select
    source_intent.*,
    event.status as event_status,
    event.start_at as event_start_at,
    event.title as event_title,
    event.timezone as event_timezone
  into intent
  from public.sd_team_event_notification_intents source_intent
  join public.sd_team_events event on event.id = source_intent.event_id
  where source_intent.id = p_intent_id
  for update of source_intent;

  if intent.id is null then
    raise exception using errcode = 'P0002', message = 'notification_intent_not_found';
  end if;
  if intent.consumed_at is not null then
    return pg_catalog.jsonb_build_object('intent_id', intent.id, 'replayed', true);
  end if;

  if intent.intent_type = 'event_reminder_24h' and (
    intent.event_status not in ('scheduled', 'confirmed')
    or nullif(intent.payload->>'event_start_at', '')::timestamptz is distinct from intent.event_start_at
  ) then
    if not p_dry_run then
      update public.sd_team_event_notification_intents
      set consumed_at = pg_catalog.now(),
          payload = payload || pg_catalog.jsonb_build_object('suppressed_reason', 'event_no_longer_eligible')
      where id = intent.id;
    end if;
    return pg_catalog.jsonb_build_object(
      'intent_id', intent.id,
      'dry_run', p_dry_run,
      'recipient_count', 0,
      'delivered_count', 0,
      'suppressed_count', 0,
      'skipped', 'event_no_longer_eligible'
    );
  end if;

  resolved_category := case
    when intent.intent_type in ('new_event','time_change','location_change','cancellation','postponement','late_schedule_change') then 'schedule_change'
    when intent.intent_type = 'event_reminder_24h' then 'event_reminder'
    when intent.intent_type like 'practice_%' then 'practice_plan'
    when intent.intent_type in ('game_plan_published','game_lineup_major_change','game_player_added','game_player_removed','game_assignment_changed') then 'game_plan'
    when intent.intent_type like 'game_result%' or intent.intent_type in ('game_completed','game_recap_published','recap_published','event_completed') then 'result_recap'
    when intent.intent_type like '%availability%' or intent.intent_type = 'player_unavailable' then 'availability'
    when intent.intent_type like '%attendance%' then 'attendance'
    else 'event_reminder'
  end;
  preference_category := case resolved_category
    when 'schedule_change' then 'schedule_changes'
    when 'event_reminder' then 'event_reminders'
    when 'practice_plan' then 'practice_plans'
    when 'game_plan' then 'game_plans'
    when 'result_recap' then 'results_recaps'
    else resolved_category
  end;
  required := intent.intent_type in ('cancellation','postponement','late_schedule_change');
  notification_title := coalesce(
    nullif(intent.payload->>'title', ''),
    case when intent.intent_type = 'event_reminder_24h' then 'Event Tomorrow'
         when intent.intent_type = 'new_event' then 'New Event'
         else pg_catalog.initcap(pg_catalog.replace(intent.intent_type, '_', ' ')) end
  );
  notification_body := coalesce(
    nullif(intent.payload->>'body', ''),
    case when intent.intent_type = 'event_reminder_24h'
      then intent.event_title || ' starts tomorrow at ' ||
        pg_catalog.to_char(intent.event_start_at at time zone coalesce(nullif(intent.event_timezone, ''), 'UTC'), 'FMHH12:MI AM') || '.'
      else 'Open Home Plate for the latest event details.' end
  );

  for recipient in
    select targets.user_id, pg_catalog.max(targets.subject_player_id::text)::uuid as subject_player_id
    from (
      select membership.player_id as user_id, membership.player_id as subject_player_id
      from public.sd_player_team_memberships membership
      where membership.organization_id = intent.organization_id
        and membership.team_id = intent.team_id
        and membership.active and membership.ended_at is null
      union all
      select link.parent_id, membership.player_id
      from public.sd_player_team_memberships membership
      join public.sd_parent_child_links link
        on link.org_id = membership.organization_id and link.child_id = membership.player_id
      where membership.organization_id = intent.organization_id
        and membership.team_id = intent.team_id
        and membership.active and membership.ended_at is null
      union all
      select assignment.coach_id, null::uuid
      from public.sd_coach_team_assignments assignment
      where assignment.organization_id = intent.organization_id
        and assignment.team_id = intent.team_id
        and assignment.active and assignment.ended_at is null
    ) targets
    where targets.user_id is not null
      and (intent.created_by is null or targets.user_id <> intent.created_by)
      and exists (
        select 1 from public.sd_org_memberships organization_membership
        where organization_membership.org_id = intent.organization_id
          and organization_membership.user_id = targets.user_id
          and organization_membership.status = 'active'
      )
    group by targets.user_id
  loop
    recipient_count := recipient_count + 1;
    preference := public.sd_effective_notification_preference(
      recipient.user_id,
      intent.organization_id,
      intent.team_id,
      recipient.subject_player_id,
      preference_category,
      required
    );
    if not p_dry_run then
      insert into public.sd_notification_intent_receipts(
        organization_id,source_type,source_id,recipient_user_id,category,
        delivery_state,preference_decision,deep_link
      ) values (
        intent.organization_id,'team_event_intent',intent.id,recipient.user_id,
        resolved_category,
        case when (preference->>'in_app')::boolean or (preference->>'push')::boolean then 'delivered' else 'suppressed' end,
        case when (preference->>'in_app')::boolean or (preference->>'push')::boolean then 'deliver' else 'preference_suppressed' end,
        pg_catalog.jsonb_build_object('route','team_event','event_id',intent.event_id,'team_id',intent.team_id)
      ) on conflict do nothing;

      if (preference->>'in_app')::boolean or (preference->>'push')::boolean then
        insert into public.sd_notifications(
          org_id,recipient_user_id,category,title,body,related_entity_type,
          related_entity_id,action_route,action_payload,deduplication_key,
          created_by,source,metadata,archived_at
        ) values (
          intent.organization_id,recipient.user_id,resolved_category,
          notification_title,notification_body,'team_event',intent.event_id::text,
          'team_event',pg_catalog.jsonb_build_object('event_id',intent.event_id,'team_id',intent.team_id),
          intent.deduplication_key,intent.created_by,'event_operation',
          pg_catalog.jsonb_build_object(
            'intent_id',intent.id,
            'push_suppressed',not((preference->>'push')::boolean)
          ),
          case when (preference->>'in_app')::boolean then null else pg_catalog.now() end
        ) on conflict(org_id,recipient_user_id,category,deduplication_key)
          do update set metadata = excluded.metadata
        returning id into created_notification_id;
        update public.sd_notification_intent_receipts receipt
        set notification_id = created_notification_id, delivered_at = pg_catalog.now()
        where receipt.organization_id = intent.organization_id
          and receipt.source_type = 'team_event_intent'
          and receipt.source_id = intent.id
          and receipt.recipient_user_id = recipient.user_id
          and receipt.category = resolved_category;
        delivered_count := delivered_count + 1;
      else
        suppressed_count := suppressed_count + 1;
      end if;
    end if;
  end loop;

  if not p_dry_run then
    update public.sd_team_event_notification_intents
    set consumed_at = pg_catalog.now()
    where id = intent.id;
  end if;
  return pg_catalog.jsonb_build_object(
    'intent_id', intent.id,
    'dry_run', p_dry_run,
    'recipient_count', recipient_count,
    'delivered_count', delivered_count,
    'suppressed_count', suppressed_count
  );
end;
$$;

revoke all on function public.sd_deliver_team_event_notification_intent(uuid,boolean)
from public, anon, authenticated;
grant execute on function public.sd_deliver_team_event_notification_intent(uuid,boolean)
to service_role;

create or replace function public.sd_process_event_reminders(
  p_now timestamptz default pg_catalog.now(),
  p_dry_run boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  event record;
  intent_id uuid;
  eligible_count integer := 0;
  created_count integer := 0;
  delivered_count integer := 0;
  delivery jsonb;
  deduplication_key text;
begin
  if not p_dry_run then
    update public.sd_team_event_notification_intents pending
    set consumed_at = pg_catalog.now(),
        payload = pending.payload || pg_catalog.jsonb_build_object('suppressed_reason', 'event_no_longer_eligible')
    where pending.intent_type = 'event_reminder_24h'
      and pending.consumed_at is null
      and not exists (
        select 1 from public.sd_team_events current_event
        where current_event.id = pending.event_id
          and current_event.status in ('scheduled','confirmed')
          and nullif(pending.payload->>'event_start_at', '')::timestamptz = current_event.start_at
      );
  end if;

  for event in
    select scheduled_event.id,scheduled_event.organization_id,scheduled_event.team_id,
      scheduled_event.title,scheduled_event.start_at,scheduled_event.timezone,team.name as team_name
    from public.sd_team_events scheduled_event
    join public.sd_teams team on team.id = scheduled_event.team_id
    where scheduled_event.status in ('scheduled','confirmed')
      and scheduled_event.start_at >= p_now + interval '23 hours'
      and scheduled_event.start_at < p_now + interval '25 hours'
      and scheduled_event.cancelled_at is null
    order by scheduled_event.start_at, scheduled_event.id
  loop
    eligible_count := eligible_count + 1;
    deduplication_key := event.id::text || ':event_reminder_24h:' ||
      extract(epoch from event.start_at)::bigint::text;
    if p_dry_run then
      continue;
    end if;
    intent_id := null;
    insert into public.sd_team_event_notification_intents(
      organization_id,team_id,event_id,intent_type,deduplication_key,payload,created_by
    ) values (
      event.organization_id,event.team_id,event.id,'event_reminder_24h',deduplication_key,
      pg_catalog.jsonb_build_object(
        'title','Event Tomorrow',
        'body',event.title || ' starts tomorrow at ' ||
          pg_catalog.to_char(event.start_at at time zone coalesce(nullif(event.timezone, ''), 'UTC'), 'FMHH12:MI AM') || '.',
        'event_start_at',event.start_at,
        'team_name',event.team_name
      ),
      null
    ) on conflict(organization_id,deduplication_key) do nothing
    returning id into intent_id;
    if intent_id is not null then
      created_count := created_count + 1;
      delivery := public.sd_deliver_team_event_notification_intent(intent_id, false);
      delivered_count := delivered_count + coalesce((delivery->>'delivered_count')::integer, 0);
    end if;
  end loop;

  return pg_catalog.jsonb_build_object(
    'dry_run', p_dry_run,
    'window_start', p_now + interval '23 hours',
    'window_end', p_now + interval '25 hours',
    'eligible_count', eligible_count,
    'created_count', created_count,
    'delivered_count', delivered_count
  );
end;
$$;

revoke all on function public.sd_process_event_reminders(timestamptz,boolean)
from public, anon, authenticated;
grant execute on function public.sd_process_event_reminders(timestamptz,boolean)
to service_role;

do $$
declare
  job_id bigint;
begin
  for job_id in
    select job.jobid from cron.job job
    where job.jobname = 'home-plate-event-reminders-24h'
  loop
    perform cron.unschedule(job_id);
  end loop;
  perform cron.schedule(
    'home-plate-event-reminders-24h',
    '*/30 * * * *',
    'select public.sd_process_event_reminders(pg_catalog.now(), false);'
  );
end;
$$;
