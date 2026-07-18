-- Phase 12F: contextual organization communication and notification delivery.
-- Reuses sd_chat_*, sd_notifications, sd_push_devices, sd_notification_deliveries,
-- and sd_team_event_notification_intents. No provider is invoked by this migration.
-- Rollback: stop new writers, retain notification/recipient history, drop the
-- Phase 12F RPCs and tables, then remove only the additive columns below.

alter table public.sd_chat_channels
  add column if not exists season_id uuid references public.sd_seasons(id) on delete set null,
  add column if not exists team_id uuid references public.sd_teams(id) on delete set null,
  add column if not exists event_id uuid references public.sd_team_events(id) on delete set null,
  add column if not exists household_id uuid,
  add column if not exists conversation_kind text not null default 'direct',
  add column if not exists minor_visibility text not null default 'standard',
  add column if not exists archived_at timestamptz;

alter table public.sd_chat_messages
  add column if not exists reply_to_message_id uuid references public.sd_chat_messages(id) on delete set null,
  add column if not exists redacted_at timestamptz,
  add column if not exists redaction_reason text,
  add column if not exists version integer not null default 1;

create table if not exists public.sd_communication_policies (
  organization_id uuid primary key references public.sd_orgs(id) on delete cascade,
  player_to_coach_allowed boolean not null default true,
  parent_to_coach_allowed boolean not null default true,
  minor_parent_visibility_required boolean not null default true,
  message_edit_window_minutes integer not null default 15 check (message_edit_window_minutes between 0 and 1440),
  retention_days integer check (retention_days is null or retention_days between 30 and 3650),
  attachments_enabled boolean not null default false,
  version integer not null default 1,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default pg_catalog.now()
);

create table if not exists public.sd_announcements (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  season_id uuid references public.sd_seasons(id) on delete restrict,
  team_id uuid references public.sd_teams(id) on delete restrict,
  event_id uuid references public.sd_team_events(id) on delete restrict,
  title text not null check (pg_catalog.char_length(pg_catalog.btrim(title)) between 1 and 120),
  body text not null check (pg_catalog.char_length(pg_catalog.btrim(body)) between 1 and 2000),
  audience_type text not null check (audience_type in ('organization','season','team','team_staff','players','parents','households','individual','event_participants','unavailable_players','missing_availability','missing_attendance','registrants','waitlisted','unpaid_balances','missing_requirements')),
  audience_filter jsonb not null default '{}'::jsonb check (pg_catalog.jsonb_typeof(audience_filter)='object'),
  priority text not null default 'normal' check (priority in ('normal','important','urgent')),
  visibility text not null default 'audience' check (visibility in ('audience','staff_only')),
  acknowledgment_required boolean not null default false,
  publish_at timestamptz not null default pg_catalog.now(),
  expires_at timestamptz,
  status text not null default 'draft' check (status in ('draft','scheduled','published','expired','cancelled','archived')),
  attachment_refs jsonb not null default '[]'::jsonb check (pg_catalog.jsonb_typeof(attachment_refs)='array'),
  version integer not null default 1,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  archived_at timestamptz,
  check (expires_at is null or expires_at>publish_at)
);

create table if not exists public.sd_announcement_recipients (
  announcement_id uuid not null references public.sd_announcements(id) on delete cascade,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  recipient_user_id uuid not null references auth.users(id) on delete restrict,
  subject_player_id uuid references auth.users(id) on delete set null,
  recipient_reason text not null,
  notification_id uuid references public.sd_notifications(id) on delete set null,
  read_at timestamptz,
  acknowledged_at timestamptz,
  archived_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  primary key (announcement_id,recipient_user_id)
);

create table if not exists public.sd_notification_preferences (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  organization_id uuid references public.sd_orgs(id) on delete cascade,
  team_id uuid references public.sd_teams(id) on delete cascade,
  subject_player_id uuid references auth.users(id) on delete cascade,
  category text not null,
  in_app_enabled boolean not null default true,
  push_enabled boolean not null default true,
  email_ready_enabled boolean not null default false,
  sms_ready_enabled boolean not null default false,
  quiet_hours_start time,
  quiet_hours_end time,
  timezone text not null default 'UTC',
  version integer not null default 1,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  unique nulls not distinct(user_id,organization_id,team_id,subject_player_id,category),
  check (category in ('all','schedule_changes','event_reminders','attendance','availability','practice_plans','game_plans','lineup_assignment','team_announcements','direct_messages','registration','payments','results_recaps','organization_notices','system_notices')),
  check ((quiet_hours_start is null)=(quiet_hours_end is null))
);

create table if not exists public.sd_notification_intent_receipts (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  source_type text not null,
  source_id uuid not null,
  recipient_user_id uuid not null references auth.users(id) on delete restrict,
  category text not null,
  delivery_state text not null check (delivery_state in ('pending','processing','delivered','failed','suppressed','expired','cancelled')),
  preference_decision text not null,
  notification_id uuid references public.sd_notifications(id) on delete set null,
  deep_link jsonb not null default '{}'::jsonb check (pg_catalog.jsonb_typeof(deep_link)='object'),
  failure_reason text,
  attempt_count integer not null default 0 check (attempt_count between 0 and 20),
  next_attempt_at timestamptz,
  delivered_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  unique(organization_id,source_type,source_id,recipient_user_id,category)
);

create table if not exists public.sd_communication_audit_logs (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  target_type text not null,
  target_id uuid,
  request_id uuid,
  details jsonb not null default '{}'::jsonb check (pg_catalog.jsonb_typeof(details)='object'),
  created_at timestamptz not null default pg_catalog.now(),
  unique(organization_id,request_id,action)
);

create table if not exists public.sd_chat_message_history (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  message_id uuid not null references public.sd_chat_messages(id) on delete cascade,
  version integer not null,
  prior_body text,
  action text not null check (action in ('edited','redacted')),
  reason text,
  actor_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  unique(message_id,version)
);

create index if not exists idx_sd_announcements_scope on public.sd_announcements(organization_id,season_id,team_id,status,publish_at desc);
create index if not exists idx_sd_announcement_recipients_user on public.sd_announcement_recipients(organization_id,recipient_user_id,created_at desc);
create index if not exists idx_sd_notification_preferences_resolve on public.sd_notification_preferences(user_id,organization_id,team_id,category);
create index if not exists idx_sd_notification_intent_receipts_queue on public.sd_notification_intent_receipts(delivery_state,next_attempt_at,created_at) where delivery_state in ('pending','failed');
create index if not exists idx_sd_communication_audit_scope on public.sd_communication_audit_logs(organization_id,created_at desc);
create index if not exists idx_sd_chat_channels_context on public.sd_chat_channels(org_id,team_id,event_id,updated_at desc);

alter table public.sd_communication_policies enable row level security;
alter table public.sd_announcements enable row level security;
alter table public.sd_announcement_recipients enable row level security;
alter table public.sd_notification_preferences enable row level security;
alter table public.sd_notification_intent_receipts enable row level security;
alter table public.sd_communication_audit_logs enable row level security;
alter table public.sd_chat_message_history enable row level security;

revoke all on table public.sd_communication_policies,public.sd_announcements,public.sd_announcement_recipients,public.sd_notification_preferences,public.sd_notification_intent_receipts,public.sd_communication_audit_logs,public.sd_chat_message_history from public,anon,authenticated;
grant select on table public.sd_notification_preferences to authenticated;
grant select on table public.sd_announcements,public.sd_announcement_recipients to authenticated;
grant select,insert,update,delete on table public.sd_communication_policies,public.sd_announcements,public.sd_announcement_recipients,public.sd_notification_preferences,public.sd_notification_intent_receipts,public.sd_communication_audit_logs,public.sd_chat_message_history to service_role;

create policy sd_notification_preferences_own_select on public.sd_notification_preferences for select to authenticated using(user_id=(select auth.uid()));
create policy sd_announcements_recipient_select on public.sd_announcements for select to authenticated using(exists(select 1 from public.sd_announcement_recipients r where r.announcement_id=id and r.recipient_user_id=(select auth.uid())) or exists(select 1 from public.sd_org_memberships m where m.org_id=organization_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin')));
create policy sd_announcement_recipients_own_select on public.sd_announcement_recipients for select to authenticated using(recipient_user_id=(select auth.uid()) or exists(select 1 from public.sd_org_memberships m where m.org_id=organization_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin')));

alter table public.sd_notifications drop constraint if exists sd_notifications_category_check;
alter table public.sd_notifications add constraint sd_notifications_category_check check(category in ('payment_request_created','payment_received','booking_created','booking_updated','program_assigned','program_updated','message_received','testing_result_added','organization_announcement','team_announcement','event_announcement','schedule_change','event_reminder','attendance','availability','practice_plan','game_plan','lineup_assignment','registration','payment_notice','result_recap','system'));
alter table public.sd_notifications drop constraint if exists sd_notifications_source_check;
alter table public.sd_notifications add constraint sd_notifications_source_check check(source in ('payment_request','payment_webhook','announcement','chat','schedule','event_operation','practice_plan','game_plan','registration','organization_finance','system'));

create or replace function public.sd_effective_notification_preference(p_user_id uuid,p_organization_id uuid,p_team_id uuid,p_subject_player_id uuid,p_category text,p_required boolean default false)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare pref public.sd_notification_preferences%rowtype; local_time time;
begin
  select * into pref from public.sd_notification_preferences p where p.user_id=p_user_id and (p.organization_id=p_organization_id or p.organization_id is null) and (p.team_id=p_team_id or p.team_id is null) and (p.subject_player_id=p_subject_player_id or p.subject_player_id is null) and p.category in (p_category,'all') order by (p.subject_player_id is not null) desc,(p.team_id is not null) desc,(p.organization_id is not null) desc,(p.category=p_category) desc limit 1;
  local_time:=(pg_catalog.now() at time zone coalesce(pref.timezone,'UTC'))::time;
  return pg_catalog.jsonb_build_object('in_app',case when p_required then true else coalesce(pref.in_app_enabled,true) end,'push',coalesce(pref.push_enabled,true) and not(case when pref.quiet_hours_start is null then false when pref.quiet_hours_start<pref.quiet_hours_end then local_time>=pref.quiet_hours_start and local_time<pref.quiet_hours_end else local_time>=pref.quiet_hours_start or local_time<pref.quiet_hours_end end),'email_ready',coalesce(pref.email_ready_enabled,false),'sms_ready',coalesce(pref.sms_ready_enabled,false),'required',p_required,'timezone',coalesce(pref.timezone,'UTC'));
end; $$;

create or replace function public.sd_expand_communication_recipients(p_organization_id uuid,p_audience_type text,p_filter jsonb)
returns table(user_id uuid,subject_player_id uuid,reason text) language sql stable security definer set search_path='' as $$
  select distinct expanded.user_id,expanded.subject_player_id,expanded.reason from (
    select m.user_id as user_id,null::uuid as subject_player_id,'organization_member'::text as reason from public.sd_org_memberships m where m.org_id=p_organization_id and m.status='active' and p_audience_type='organization'
    union all select m.user_id as user_id,null::uuid as subject_player_id,'season_member'::text as reason from public.sd_org_memberships m where m.org_id=p_organization_id and m.status='active' and p_audience_type='season'
    union all select pm.player_id as user_id,pm.player_id as subject_player_id,'team_player'::text as reason from public.sd_player_team_memberships pm where pm.organization_id=p_organization_id and pm.team_id=nullif(p_filter->>'team_id','')::uuid and pm.active and pm.ended_at is null and p_audience_type in ('team','players')
    union all select ca.coach_id as user_id,null::uuid as subject_player_id,'team_staff'::text as reason from public.sd_coach_team_assignments ca where ca.organization_id=p_organization_id and ca.team_id=nullif(p_filter->>'team_id','')::uuid and ca.active and ca.ended_at is null and p_audience_type in ('team','team_staff')
    union all select link.parent_id as user_id,pm.player_id as subject_player_id,'linked_parent'::text as reason from public.sd_player_team_memberships pm join public.sd_parent_child_links link on link.org_id=pm.organization_id and link.child_id=pm.player_id where pm.organization_id=p_organization_id and pm.team_id=nullif(p_filter->>'team_id','')::uuid and pm.active and pm.ended_at is null and p_audience_type in ('team','parents','households')
    union all select nullif(p_filter->>'user_id','')::uuid as user_id,nullif(p_filter->>'subject_player_id','')::uuid as subject_player_id,'individual'::text as reason where p_audience_type='individual'
    union all select ep.user_id as user_id,case when ep.participant_type='player' then ep.user_id else null::uuid end as subject_player_id,'event_participant'::text as reason from public.sd_event_operation_participants ep join public.sd_event_operations eo on eo.id=ep.event_operation_id where eo.organization_id=p_organization_id and eo.event_id=nullif(p_filter->>'event_id','')::uuid and ep.expected and p_audience_type='event_participants'
  ) as expanded(user_id,subject_player_id,reason) where expanded.user_id is not null;
$$;

create or replace function public.sd_publish_announcement(p_organization_id uuid,p_actor_id uuid,p_request_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare announcement public.sd_announcements%rowtype; recipients uuid[]; created_count integer:=0; replay_target uuid; filter jsonb:=coalesce(p_payload->'audience_filter','{}'::jsonb);
begin
  if not exists(select 1 from public.sd_org_memberships where org_id=p_organization_id and user_id=p_actor_id and status='active' and role in ('owner','admin')) and not exists(select 1 from public.sd_coach_team_assignments a join public.sd_coach_team_responsibilities r on r.assignment_id=a.id where a.organization_id=p_organization_id and a.coach_id=p_actor_id and a.active and a.ended_at is null and r.responsibility in ('head_coach','team_manager') and a.team_id=nullif(filter->>'team_id','')::uuid) then raise exception using errcode='42501',message='announcement_capability_required'; end if;
  select target_id into replay_target from public.sd_communication_audit_logs where organization_id=p_organization_id and request_id=p_request_id and action='publish_announcement';
  if replay_target is not null then select * into announcement from public.sd_announcements where id=replay_target; return pg_catalog.jsonb_build_object('announcement',pg_catalog.to_jsonb(announcement),'replayed',true); end if;
  insert into public.sd_announcements(organization_id,season_id,team_id,event_id,title,body,audience_type,audience_filter,priority,visibility,acknowledgment_required,publish_at,expires_at,status,created_by,updated_by)
    values(p_organization_id,nullif(p_payload->>'season_id','')::uuid,nullif(p_payload->>'team_id','')::uuid,nullif(p_payload->>'event_id','')::uuid,pg_catalog.btrim(p_payload->>'title'),pg_catalog.btrim(p_payload->>'body'),p_payload->>'audience_type',filter,coalesce(nullif(p_payload->>'priority',''),'normal'),coalesce(nullif(p_payload->>'visibility',''),'audience'),coalesce((p_payload->>'acknowledgment_required')::boolean,false),coalesce((p_payload->>'publish_at')::timestamptz,pg_catalog.now()),(p_payload->>'expires_at')::timestamptz,'published',p_actor_id,p_actor_id) returning * into announcement;
  insert into public.sd_announcement_recipients(announcement_id,organization_id,recipient_user_id,subject_player_id,recipient_reason)
    select announcement.id,p_organization_id,user_id,subject_player_id,reason from public.sd_expand_communication_recipients(p_organization_id,announcement.audience_type,filter) on conflict do nothing;
  select coalesce(pg_catalog.array_agg(recipient_user_id),'{}'::uuid[]) into recipients from public.sd_announcement_recipients where announcement_id=announcement.id;
  if pg_catalog.cardinality(recipients)=0 then raise exception using errcode='P0001',message='announcement_audience_empty'; end if;
  insert into public.sd_notifications(org_id,recipient_user_id,category,title,body,related_entity_type,related_entity_id,action_route,action_payload,deduplication_key,created_by,source,metadata,archived_at)
    select p_organization_id,recipient,case when announcement.event_id is not null then 'event_announcement' when announcement.team_id is not null then 'team_announcement' else 'organization_announcement' end,announcement.title,announcement.body,'announcement',announcement.id::text,'organization_announcement',pg_catalog.jsonb_build_object('announcement_id',announcement.id,'organization_id',p_organization_id),announcement.id::text,p_actor_id,'announcement',pg_catalog.jsonb_build_object('priority',announcement.priority,'acknowledgment_required',announcement.acknowledgment_required,'push_suppressed',not((decision.value->>'push')::boolean),'in_app_suppressed',not((decision.value->>'in_app')::boolean)),case when (decision.value->>'in_app')::boolean then null else pg_catalog.now() end
    from pg_catalog.unnest(recipients) recipient
    cross join lateral public.sd_effective_notification_preference(recipient,p_organization_id,announcement.team_id,null,case when announcement.team_id is null then 'organization_notices' else 'team_announcements' end,announcement.acknowledgment_required) decision(value)
    on conflict(org_id,recipient_user_id,category,deduplication_key) do nothing;
  get diagnostics created_count=row_count;
  update public.sd_announcement_recipients r set notification_id=n.id from public.sd_notifications n where r.announcement_id=announcement.id and n.recipient_user_id=r.recipient_user_id and n.related_entity_id=announcement.id::text;
  insert into public.sd_communication_audit_logs(organization_id,actor_id,action,target_type,target_id,request_id,details) values(p_organization_id,p_actor_id,'publish_announcement','announcement',announcement.id,p_request_id,pg_catalog.jsonb_build_object('recipient_snapshot',recipients,'created_notifications',created_count));
  return pg_catalog.jsonb_build_object('announcement',pg_catalog.to_jsonb(announcement),'recipient_count',pg_catalog.cardinality(recipients),'created_notifications',created_count);
end; $$;

create or replace function public.sd_set_notification_preference(p_actor_id uuid,p_organization_id uuid,p_team_id uuid,p_subject_player_id uuid,p_category text,p_payload jsonb,p_expected_version integer)
returns jsonb language plpgsql security definer set search_path='' as $$ declare pref public.sd_notification_preferences%rowtype;
begin
  if p_actor_id<>(select auth.uid()) then raise exception using errcode='42501',message='actor_mismatch'; end if;
  if p_subject_player_id is not null and p_subject_player_id<>p_actor_id and not exists(select 1 from public.sd_parent_child_links where org_id=p_organization_id and parent_id=p_actor_id and child_id=p_subject_player_id) then raise exception using errcode='42501',message='parent_child_link_required'; end if;
  select * into pref from public.sd_notification_preferences where user_id=p_actor_id and organization_id is not distinct from p_organization_id and team_id is not distinct from p_team_id and subject_player_id is not distinct from p_subject_player_id and category=p_category for update;
  if pref.id is null then insert into public.sd_notification_preferences(user_id,organization_id,team_id,subject_player_id,category,in_app_enabled,push_enabled,email_ready_enabled,sms_ready_enabled,quiet_hours_start,quiet_hours_end,timezone) values(p_actor_id,p_organization_id,p_team_id,p_subject_player_id,p_category,coalesce((p_payload->>'in_app_enabled')::boolean,true),coalesce((p_payload->>'push_enabled')::boolean,true),coalesce((p_payload->>'email_ready_enabled')::boolean,false),coalesce((p_payload->>'sms_ready_enabled')::boolean,false),(p_payload->>'quiet_hours_start')::time,(p_payload->>'quiet_hours_end')::time,coalesce(nullif(p_payload->>'timezone',''),'UTC')) returning * into pref;
  else if p_expected_version is null or pref.version<>p_expected_version then raise exception using errcode='P0001',message='stale_notification_preference'; end if; update public.sd_notification_preferences set in_app_enabled=coalesce((p_payload->>'in_app_enabled')::boolean,in_app_enabled),push_enabled=coalesce((p_payload->>'push_enabled')::boolean,push_enabled),email_ready_enabled=coalesce((p_payload->>'email_ready_enabled')::boolean,email_ready_enabled),sms_ready_enabled=coalesce((p_payload->>'sms_ready_enabled')::boolean,sms_ready_enabled),quiet_hours_start=case when p_payload?'quiet_hours_start' then (p_payload->>'quiet_hours_start')::time else quiet_hours_start end,quiet_hours_end=case when p_payload?'quiet_hours_end' then (p_payload->>'quiet_hours_end')::time else quiet_hours_end end,timezone=coalesce(nullif(p_payload->>'timezone',''),timezone),version=version+1,updated_at=pg_catalog.now() where id=pref.id returning * into pref; end if;
  return pg_catalog.to_jsonb(pref);
end; $$;

revoke all on function public.sd_effective_notification_preference(uuid,uuid,uuid,uuid,text,boolean),public.sd_expand_communication_recipients(uuid,text,jsonb),public.sd_publish_announcement(uuid,uuid,uuid,jsonb),public.sd_set_notification_preference(uuid,uuid,uuid,uuid,text,jsonb,integer) from public,anon,authenticated;
grant execute on function public.sd_effective_notification_preference(uuid,uuid,uuid,uuid,text,boolean),public.sd_expand_communication_recipients(uuid,text,jsonb),public.sd_publish_announcement(uuid,uuid,uuid,jsonb) to service_role;
grant execute on function public.sd_set_notification_preference(uuid,uuid,uuid,uuid,text,jsonb,integer) to authenticated,service_role;

-- Extend the existing APNs queue without calling the provider. The worker
-- wakeup remains opt-in through a database setting and can be enabled only by
-- an authorized release configuration after credentials are verified.
create or replace function public.sd_queue_apns_deliveries() returns trigger language plpgsql security definer set search_path='' as $$
declare created_count integer:=0;
begin
  insert into public.sd_notification_deliveries(notification_id,device_id,channel,status,next_attempt_at)
    select n.id,d.id,'apns','pending',pg_catalog.now() from notification_rows n join public.sd_push_devices d on d.user_id=n.recipient_user_id and d.notifications_authorized and d.disabled_at is null
    where coalesce((n.metadata->>'push_suppressed')::boolean,false)=false on conflict(notification_id,device_id,channel) do nothing;
  get diagnostics created_count=row_count;
  if created_count>0 and coalesce(pg_catalog.current_setting('app.notification_delivery_enabled',true),'false')='true' then perform public.sd_request_notification_delivery_worker(); end if;
  return null;
end $$;
revoke all on function public.sd_queue_apns_deliveries() from public,anon,authenticated,service_role;

create or replace function public.sd_consume_team_event_notification_intent(p_intent_id uuid,p_actor_id uuid,p_dry_run boolean default true) returns jsonb language plpgsql security definer set search_path='' as $$
declare intent public.sd_team_event_notification_intents%rowtype; recipient record; preference jsonb; created_notification_id uuid; recipient_count integer:=0; delivered_count integer:=0; suppressed_count integer:=0; resolved_category text; title text; body text; required boolean:=false;
begin
  select * into intent from public.sd_team_event_notification_intents where id=p_intent_id for update;
  if intent.id is null then raise exception using errcode='P0002',message='notification_intent_not_found'; end if;
  if not exists(select 1 from public.sd_org_memberships where org_id=intent.organization_id and user_id=p_actor_id and status='active' and role in ('owner','admin')) then raise exception using errcode='42501',message='manage_notification_delivery_required'; end if;
  if intent.consumed_at is not null then return pg_catalog.jsonb_build_object('intent_id',intent.id,'replayed',true); end if;
  resolved_category:=case when intent.intent_type in ('new_event','time_change','location_change','cancellation','postponement','late_schedule_change') then 'schedule_change' when intent.intent_type like 'practice_%' then 'practice_plan' when intent.intent_type in ('game_plan_published','game_lineup_major_change','game_player_added','game_player_removed','game_assignment_changed') then 'game_plan' when intent.intent_type like 'game_result%' or intent.intent_type in ('game_completed','game_recap_published','recap_published','event_completed') then 'result_recap' when intent.intent_type like '%availability%' or intent.intent_type='player_unavailable' then 'availability' when intent.intent_type like '%attendance%' then 'attendance' else 'event_reminder' end;
  required:=intent.intent_type in ('cancellation','postponement','late_schedule_change');
  title:=coalesce(nullif(intent.payload->>'title',''),pg_catalog.initcap(pg_catalog.replace(intent.intent_type,'_',' ')));
  body:=coalesce(nullif(intent.payload->>'body',''),'Open Home Plate for the latest event details.');
  for recipient in
    select distinct targets.user_id,targets.subject_player_id from (
      select pm.player_id user_id,pm.player_id subject_player_id from public.sd_player_team_memberships pm where pm.organization_id=intent.organization_id and pm.team_id=intent.team_id and pm.active and pm.ended_at is null
      union all select l.parent_id,pm.player_id from public.sd_player_team_memberships pm join public.sd_parent_child_links l on l.org_id=pm.organization_id and l.child_id=pm.player_id where pm.organization_id=intent.organization_id and pm.team_id=intent.team_id and pm.active and pm.ended_at is null
      union all select ca.coach_id,null::uuid from public.sd_coach_team_assignments ca where ca.organization_id=intent.organization_id and ca.team_id=intent.team_id and ca.active and ca.ended_at is null
    ) targets
  loop
    recipient_count:=recipient_count+1;
    preference:=public.sd_effective_notification_preference(recipient.user_id,intent.organization_id,intent.team_id,recipient.subject_player_id,case resolved_category when 'schedule_change' then 'schedule_changes' when 'practice_plan' then 'practice_plans' when 'game_plan' then 'game_plans' when 'result_recap' then 'results_recaps' else resolved_category end,required);
    if not p_dry_run then
      insert into public.sd_notification_intent_receipts(organization_id,source_type,source_id,recipient_user_id,category,delivery_state,preference_decision,deep_link)
        values(intent.organization_id,'team_event_intent',intent.id,recipient.user_id,resolved_category,case when (preference->>'in_app')::boolean or (preference->>'push')::boolean then 'delivered' else 'suppressed' end,case when (preference->>'in_app')::boolean or (preference->>'push')::boolean then 'deliver' else 'preference_suppressed' end,pg_catalog.jsonb_build_object('route','team_event','event_id',intent.event_id,'team_id',intent.team_id)) on conflict do nothing;
      if (preference->>'in_app')::boolean or (preference->>'push')::boolean then
        insert into public.sd_notifications(org_id,recipient_user_id,category,title,body,related_entity_type,related_entity_id,action_route,action_payload,deduplication_key,created_by,source,metadata,archived_at)
          values(intent.organization_id,recipient.user_id,resolved_category,title,body,'team_event',intent.event_id::text,'team_event',pg_catalog.jsonb_build_object('event_id',intent.event_id,'team_id',intent.team_id),intent.deduplication_key,p_actor_id,'event_operation',pg_catalog.jsonb_build_object('intent_id',intent.id,'push_suppressed',not((preference->>'push')::boolean)),case when (preference->>'in_app')::boolean then null else pg_catalog.now() end)
          on conflict(org_id,recipient_user_id,category,deduplication_key) do update set metadata=excluded.metadata returning id into created_notification_id;
        update public.sd_notification_intent_receipts receipt set notification_id=created_notification_id,delivered_at=pg_catalog.now() where receipt.organization_id=intent.organization_id and receipt.source_type='team_event_intent' and receipt.source_id=intent.id and receipt.recipient_user_id=recipient.user_id and receipt.category=resolved_category;
        delivered_count:=delivered_count+1;
      else suppressed_count:=suppressed_count+1; end if;
    end if;
  end loop;
  if not p_dry_run then update public.sd_team_event_notification_intents set consumed_at=pg_catalog.now() where id=intent.id; end if;
  return pg_catalog.jsonb_build_object('intent_id',intent.id,'dry_run',p_dry_run,'recipient_count',recipient_count,'delivered_count',delivered_count,'suppressed_count',suppressed_count);
end $$;
revoke all on function public.sd_consume_team_event_notification_intent(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.sd_consume_team_event_notification_intent(uuid,uuid,boolean) to service_role;

create or replace function public.sd_edit_chat_message(p_organization_id uuid,p_actor_id uuid,p_message_id uuid,p_body text,p_expected_version integer,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare message public.sd_chat_messages%rowtype; edit_window integer;
begin
  select * into message from public.sd_chat_messages where id=p_message_id and org_id=p_organization_id for update;
  if message.id is null then raise exception using errcode='P0002',message='message_not_found'; end if;
  select coalesce(message_edit_window_minutes,15) into edit_window from public.sd_communication_policies where organization_id=p_organization_id;
  edit_window:=coalesce(edit_window,15);
  if message.sender_id<>p_actor_id or message.created_at+pg_catalog.make_interval(mins=>edit_window)<pg_catalog.now() then raise exception using errcode='42501',message='message_edit_not_allowed'; end if;
  if message.version<>p_expected_version or message.deleted_at is not null or message.redacted_at is not null then raise exception using errcode='P0001',message='stale_message'; end if;
  if pg_catalog.char_length(pg_catalog.btrim(p_body)) not between 1 and 4000 then raise exception using errcode='22023',message='invalid_message_body'; end if;
  insert into public.sd_chat_message_history(organization_id,message_id,version,prior_body,action,actor_id) values(p_organization_id,message.id,message.version,message.body,'edited',p_actor_id);
  update public.sd_chat_messages set body=pg_catalog.btrim(p_body),edited_at=pg_catalog.now(),version=version+1 where id=message.id returning * into message;
  insert into public.sd_communication_audit_logs(organization_id,actor_id,action,target_type,target_id,request_id,details) values(p_organization_id,p_actor_id,'edit_message','chat_message',message.id,p_request_id,pg_catalog.jsonb_build_object('version',message.version));
  return pg_catalog.to_jsonb(message);
end $$;

create or replace function public.sd_redact_chat_message(p_organization_id uuid,p_actor_id uuid,p_message_id uuid,p_expected_version integer,p_request_id uuid,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare message public.sd_chat_messages%rowtype; is_admin boolean;
begin
  select * into message from public.sd_chat_messages where id=p_message_id and org_id=p_organization_id for update;
  if message.id is null then raise exception using errcode='P0002',message='message_not_found'; end if;
  select exists(select 1 from public.sd_org_memberships where org_id=p_organization_id and user_id=p_actor_id and status='active' and role in ('owner','admin')) into is_admin;
  if message.sender_id<>p_actor_id and not is_admin then raise exception using errcode='42501',message='moderate_communication_required'; end if;
  if message.version<>p_expected_version then raise exception using errcode='P0001',message='stale_message'; end if;
  if is_admin and message.sender_id<>p_actor_id and pg_catalog.btrim(coalesce(p_reason,''))='' then raise exception using errcode='22023',message='moderation_reason_required'; end if;
  insert into public.sd_chat_message_history(organization_id,message_id,version,prior_body,action,reason,actor_id) values(p_organization_id,message.id,message.version,message.body,'redacted',p_reason,p_actor_id);
  update public.sd_chat_messages set body='Message removed',deleted_at=pg_catalog.now(),redacted_at=pg_catalog.now(),redaction_reason=case when is_admin then p_reason else 'sender_removed' end,version=version+1 where id=message.id returning * into message;
  insert into public.sd_communication_audit_logs(organization_id,actor_id,action,target_type,target_id,request_id,details) values(p_organization_id,p_actor_id,'redact_message','chat_message',message.id,p_request_id,pg_catalog.jsonb_build_object('moderated',is_admin and message.sender_id<>p_actor_id,'reason',p_reason));
  return pg_catalog.to_jsonb(message)-'redaction_reason';
end $$;
revoke all on function public.sd_edit_chat_message(uuid,uuid,uuid,text,integer,uuid),public.sd_redact_chat_message(uuid,uuid,uuid,integer,uuid,text) from public,anon,authenticated;
grant execute on function public.sd_edit_chat_message(uuid,uuid,uuid,text,integer,uuid),public.sd_redact_chat_message(uuid,uuid,uuid,integer,uuid,text) to service_role;

create or replace function public.sd_enforce_communication_policy() returns trigger language plpgsql security definer set search_path='' as $$
declare channel public.sd_chat_channels%rowtype; sender_role text; policy public.sd_communication_policies%rowtype; has_staff boolean;
begin
  select * into channel from public.sd_chat_channels where id=new.channel_id;
  select role into sender_role from public.sd_org_memberships where org_id=channel.org_id and user_id=new.sender_id and status='active';
  select * into policy from public.sd_communication_policies where organization_id=channel.org_id;
  select exists(select 1 from public.sd_chat_memberships cm join public.sd_org_memberships om on om.org_id=channel.org_id and om.user_id=cm.user_id and om.status='active' where cm.channel_id=channel.id and om.role in ('owner','admin','coach')) into has_staff;
  if sender_role='player' and has_staff and not coalesce(policy.player_to_coach_allowed,true) then raise exception using errcode='42501',message='player_to_coach_messaging_disabled'; end if;
  if sender_role='parent' and has_staff and not coalesce(policy.parent_to_coach_allowed,true) then raise exception using errcode='42501',message='parent_to_coach_messaging_disabled'; end if;
  if sender_role='player' and has_staff and channel.minor_visibility='parent_visible' and not exists(select 1 from public.sd_parent_child_links l join public.sd_chat_memberships cm on cm.channel_id=channel.id and cm.user_id=l.parent_id where l.org_id=channel.org_id and l.child_id=new.sender_id) then raise exception using errcode='42501',message='linked_parent_visibility_required'; end if;
  return new;
end $$;
drop trigger if exists trg_sd_enforce_communication_policy on public.sd_chat_messages;
create trigger trg_sd_enforce_communication_policy before insert on public.sd_chat_messages for each row execute function public.sd_enforce_communication_policy();
revoke all on function public.sd_enforce_communication_policy() from public,anon,authenticated;
