-- Preserve the remotely applied reminder behavior while removing an ambiguous
-- PL/pgSQL variable/column reference detected by plpgsql_check.
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
  v_deduplication_key text;
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
    v_deduplication_key := event.id::text || ':event_reminder_24h:' ||
      extract(epoch from event.start_at)::bigint::text;
    if p_dry_run then
      continue;
    end if;
    intent_id := null;
    insert into public.sd_team_event_notification_intents(
      organization_id,team_id,event_id,intent_type,deduplication_key,payload,created_by
    ) values (
      event.organization_id,event.team_id,event.id,'event_reminder_24h',v_deduplication_key,
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
