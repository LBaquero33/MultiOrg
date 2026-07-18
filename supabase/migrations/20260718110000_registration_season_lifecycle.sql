-- Phase 12G: registration and controlled season lifecycle.
-- Reuses sd_seasons, sd_teams, sd_player_team_memberships, and notification intents.
-- Rollback: stop writers and retain applications/history; drop Phase 12G RPCs/tables.

create table public.sd_registration_requirement_templates (
  id uuid primary key default pg_catalog.gen_random_uuid(), organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  season_id uuid references public.sd_seasons(id) on delete restrict, name text not null, requirement_type text not null check(requirement_type in ('waiver','consent','emergency_contact','code_of_conduct','media_release','medical_acknowledgment','custom_form','document_upload','signature')),
  version integer not null default 1, content jsonb not null default '{}'::jsonb, expires_after_days integer, active boolean not null default true,
  created_by uuid references auth.users(id), updated_by uuid references auth.users(id), created_at timestamptz not null default pg_catalog.now(), updated_at timestamptz not null default pg_catalog.now(),
  unique(organization_id,id), unique(organization_id,name,version)
);

create table public.sd_registration_offerings (
  id uuid primary key default pg_catalog.gen_random_uuid(), organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  season_id uuid not null references public.sd_seasons(id) on delete restrict, team_id uuid references public.sd_teams(id) on delete restrict,
  offering_type text not null check(offering_type in ('season','team','tryout','camp','clinic','program','membership','custom')),
  name text not null check(pg_catalog.char_length(pg_catalog.btrim(name)) between 1 and 120), description text,
  opens_at timestamptz not null, closes_at timestamptz not null, capacity integer check(capacity is null or capacity>0), waitlist_capacity integer check(waitlist_capacity is null or waitlist_capacity>=0),
  age_guidance text, graduation_year_guidance text, eligibility_notes text, fee_cents integer not null default 0 check(fee_cents>=0), deposit_cents integer not null default 0 check(deposit_cents between 0 and fee_cents),
  installment_configuration jsonb not null default '{}'::jsonb, refund_policy text, custom_questions jsonb not null default '[]'::jsonb,
  state text not null default 'draft' check(state in ('draft','active','paused','closed','archived')), visibility text not null default 'organization' check(visibility in ('public','organization','invite_only','staff_only')),
  auto_assign_team boolean not null default false, version integer not null default 1, created_by uuid references auth.users(id), updated_by uuid references auth.users(id), created_at timestamptz not null default pg_catalog.now(), updated_at timestamptz not null default pg_catalog.now(),
  unique(organization_id,id), check(closes_at>opens_at), check(pg_catalog.jsonb_typeof(installment_configuration)='object'), check(pg_catalog.jsonb_typeof(custom_questions)='array')
);

create table public.sd_registration_offering_requirements (
  offering_id uuid not null references public.sd_registration_offerings(id) on delete cascade, requirement_template_id uuid not null references public.sd_registration_requirement_templates(id) on delete restrict,
  required boolean not null default true, sort_order integer not null default 0, primary key(offering_id,requirement_template_id)
);

create table public.sd_registration_applications (
  id uuid primary key default pg_catalog.gen_random_uuid(), organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  season_id uuid not null references public.sd_seasons(id) on delete restrict, offering_id uuid not null references public.sd_registration_offerings(id) on delete restrict,
  applicant_user_id uuid not null references auth.users(id) on delete restrict, player_user_id uuid references auth.users(id) on delete restrict,
  guardian_user_id uuid references auth.users(id) on delete restrict, assisted_by uuid references auth.users(id), team_preference_id uuid references public.sd_teams(id) on delete set null,
  state text not null default 'draft' check(state in ('draft','submitted','under_review','action_required','approved','waitlisted','declined','withdrawn','cancelled','assigned','completed')),
  answers jsonb not null default '{}'::jsonb, sensitive_answers jsonb not null default '{}'::jsonb, prospective_player jsonb not null default '{}'::jsonb, consent_metadata jsonb not null default '{}'::jsonb,
  payment_responsible_user_id uuid references auth.users(id), fee_cents integer not null default 0, balance_cents integer not null default 0 check(balance_cents>=0), fee_status text not null default 'not_due' check(fee_status in ('not_due','due','partial','paid','waived','refunded','overdue')),
  jersey_number_request text, position_preference text, reviewer_notes text, team_assignment_id uuid references public.sd_player_team_memberships(id),
  submitted_at timestamptz, reviewed_at timestamptz, assigned_at timestamptz, version integer not null default 1,
  created_at timestamptz not null default pg_catalog.now(), updated_at timestamptz not null default pg_catalog.now(), unique(organization_id,id),
  check(pg_catalog.jsonb_typeof(answers)='object'), check(pg_catalog.jsonb_typeof(sensitive_answers)='object'), check(pg_catalog.jsonb_typeof(prospective_player)='object'), check(pg_catalog.jsonb_typeof(consent_metadata)='object')
);

create table public.sd_registration_requirement_responses (
  id uuid primary key default pg_catalog.gen_random_uuid(), organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  application_id uuid not null references public.sd_registration_applications(id) on delete cascade, requirement_template_id uuid not null references public.sd_registration_requirement_templates(id) on delete restrict,
  required_version integer not null, accepted_version integer, response jsonb not null default '{}'::jsonb, document_path text,
  status text not null default 'missing' check(status in ('missing','in_progress','accepted','rejected','expired','resign_required')),
  accepted_by uuid references auth.users(id), accepted_at timestamptz, expires_at timestamptz, consent_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default pg_catalog.now(), updated_at timestamptz not null default pg_catalog.now(), unique(application_id,requirement_template_id)
);

create table public.sd_registration_waitlist (
  id uuid primary key default pg_catalog.gen_random_uuid(), organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  offering_id uuid not null references public.sd_registration_offerings(id) on delete cascade, application_id uuid not null unique references public.sd_registration_applications(id) on delete cascade,
  position bigint generated always as identity, manual_priority integer not null default 0, status text not null default 'waiting' check(status in ('waiting','offered','accepted','declined','expired','promoted','removed')),
  offered_at timestamptz, offer_expires_at timestamptz, responded_at timestamptz, created_at timestamptz not null default pg_catalog.now()
);

create table public.sd_registration_audit_logs (
  id uuid primary key default pg_catalog.gen_random_uuid(), organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  actor_id uuid references auth.users(id), action text not null, target_type text not null, target_id uuid, request_id uuid not null,
  previous_state text, new_state text, details jsonb not null default '{}'::jsonb, created_at timestamptz not null default pg_catalog.now(), unique(organization_id,request_id,action)
);

create table public.sd_registration_notification_intents (
  id uuid primary key default pg_catalog.gen_random_uuid(), organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  application_id uuid references public.sd_registration_applications(id) on delete cascade, season_id uuid references public.sd_seasons(id) on delete cascade,
  intent_type text not null check(intent_type in ('registration_opened','registration_submitted','registration_approved','registration_waitlisted','registration_declined','registration_balance_due','season_assignment','team_assignment','required_form_missing','waiver_missing')),
  deduplication_key text not null, payload jsonb not null default '{}'::jsonb, created_by uuid references auth.users(id), created_at timestamptz not null default pg_catalog.now(), consumed_at timestamptz,
  unique(organization_id,deduplication_key)
);

create table public.sd_season_rollover_plans (
  id uuid primary key default pg_catalog.gen_random_uuid(), organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  source_season_id uuid not null references public.sd_seasons(id) on delete restrict, target_name text not null, target_start_date date, target_end_date date,
  copy_options jsonb not null default '{}'::jsonb, preview jsonb not null default '{}'::jsonb, state text not null default 'preview' check(state in ('preview','confirmed','executed','cancelled')),
  target_season_id uuid references public.sd_seasons(id), created_by uuid not null references auth.users(id), confirmed_by uuid references auth.users(id), executed_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(), updated_at timestamptz not null default pg_catalog.now()
);

create index idx_sd_registration_offerings_scope on public.sd_registration_offerings(organization_id,season_id,state,opens_at,closes_at);
create index idx_sd_registration_applications_review on public.sd_registration_applications(organization_id,season_id,offering_id,state,created_at);
create index idx_sd_registration_applications_people on public.sd_registration_applications(organization_id,applicant_user_id,player_user_id);
create index idx_sd_registration_requirements_missing on public.sd_registration_requirement_responses(organization_id,status,application_id);
create index idx_sd_registration_waitlist_order on public.sd_registration_waitlist(offering_id,status,manual_priority desc,position);
create index idx_sd_registration_audit_scope on public.sd_registration_audit_logs(organization_id,created_at desc);
create index idx_sd_registration_intents_pending on public.sd_registration_notification_intents(organization_id,created_at) where consumed_at is null;

alter table public.sd_registration_requirement_templates enable row level security;
alter table public.sd_registration_offerings enable row level security;
alter table public.sd_registration_offering_requirements enable row level security;
alter table public.sd_registration_applications enable row level security;
alter table public.sd_registration_requirement_responses enable row level security;
alter table public.sd_registration_waitlist enable row level security;
alter table public.sd_registration_audit_logs enable row level security;
alter table public.sd_registration_notification_intents enable row level security;
alter table public.sd_season_rollover_plans enable row level security;

revoke all on table public.sd_registration_requirement_templates,public.sd_registration_offerings,public.sd_registration_offering_requirements,public.sd_registration_applications,public.sd_registration_requirement_responses,public.sd_registration_waitlist,public.sd_registration_audit_logs,public.sd_registration_notification_intents,public.sd_season_rollover_plans from public,anon,authenticated;
grant select on table public.sd_registration_offerings,public.sd_registration_offering_requirements,public.sd_registration_requirement_templates to authenticated;
grant select on table public.sd_registration_applications,public.sd_registration_requirement_responses,public.sd_registration_waitlist to authenticated;
grant select,insert,update,delete on table public.sd_registration_requirement_templates,public.sd_registration_offerings,public.sd_registration_offering_requirements,public.sd_registration_applications,public.sd_registration_requirement_responses,public.sd_registration_waitlist,public.sd_registration_audit_logs,public.sd_registration_notification_intents,public.sd_season_rollover_plans to service_role;

create policy sd_registration_offerings_member_read on public.sd_registration_offerings for select to authenticated using(visibility<>'staff_only' and exists(select 1 from public.sd_org_memberships m where m.org_id=organization_id and m.user_id=(select auth.uid()) and m.status='active') or exists(select 1 from public.sd_org_memberships m where m.org_id=organization_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin')));
create policy sd_registration_templates_member_read on public.sd_registration_requirement_templates for select to authenticated using(exists(select 1 from public.sd_org_memberships m where m.org_id=organization_id and m.user_id=(select auth.uid()) and m.status='active'));
create policy sd_registration_offering_requirements_read on public.sd_registration_offering_requirements for select to authenticated using(exists(select 1 from public.sd_registration_offerings o join public.sd_org_memberships m on m.org_id=o.organization_id where o.id=offering_id and m.user_id=(select auth.uid()) and m.status='active'));
create policy sd_registration_applications_party_read on public.sd_registration_applications for select to authenticated using(applicant_user_id=(select auth.uid()) or player_user_id=(select auth.uid()) or guardian_user_id=(select auth.uid()) or exists(select 1 from public.sd_parent_child_links l where l.org_id=organization_id and l.parent_id=(select auth.uid()) and l.child_id=player_user_id) or exists(select 1 from public.sd_org_memberships m where m.org_id=organization_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin')));
create policy sd_registration_responses_party_read on public.sd_registration_requirement_responses for select to authenticated using(exists(select 1 from public.sd_registration_applications a where a.id=application_id and (a.applicant_user_id=(select auth.uid()) or a.player_user_id=(select auth.uid()) or a.guardian_user_id=(select auth.uid()) or exists(select 1 from public.sd_parent_child_links l where l.org_id=a.organization_id and l.parent_id=(select auth.uid()) and l.child_id=a.player_user_id) or exists(select 1 from public.sd_org_memberships m where m.org_id=a.organization_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin')))));
create policy sd_registration_waitlist_party_read on public.sd_registration_waitlist for select to authenticated using(exists(select 1 from public.sd_registration_applications a where a.id=application_id and (a.applicant_user_id=(select auth.uid()) or a.player_user_id=(select auth.uid()) or a.guardian_user_id=(select auth.uid()) or exists(select 1 from public.sd_org_memberships m where m.org_id=a.organization_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin')))));

create or replace function public.sd_season_transition_allowed(p_from text,p_to text) returns boolean language sql immutable as $$ select (p_from,p_to) in (('planning','registration_open'),('planning','archived'),('registration_open','roster_building'),('registration_open','planning'),('roster_building','active'),('roster_building','registration_open'),('active','playoffs'),('active','completed'),('playoffs','completed'),('completed','archived')) $$;

create or replace function public.sd_transition_season(p_organization_id uuid,p_actor_id uuid,p_season_id uuid,p_to text,p_expected_status text,p_request_id uuid,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare season public.sd_seasons%rowtype;
begin
  if not exists(select 1 from public.sd_org_memberships where org_id=p_organization_id and user_id=p_actor_id and status='active' and role in ('owner','admin')) then raise exception using errcode='42501',message='manage_season_lifecycle_required'; end if;
  if exists(select 1 from public.sd_registration_audit_logs where organization_id=p_organization_id and request_id=p_request_id and action='transition_season') then select * into season from public.sd_seasons where id=p_season_id and organization_id=p_organization_id; return pg_catalog.jsonb_build_object('season',pg_catalog.to_jsonb(season),'replayed',true); end if;
  select * into season from public.sd_seasons where id=p_season_id and organization_id=p_organization_id for update;
  if season.id is null then raise exception using errcode='P0002',message='season_not_found'; end if;
  if season.status<>p_expected_status then raise exception using errcode='P0001',message='stale_season_status'; end if;
  if not public.sd_season_transition_allowed(season.status,p_to) then raise exception using errcode='P0001',message='invalid_season_transition'; end if;
  update public.sd_seasons set status=p_to,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=season.id returning * into season;
  insert into public.sd_registration_audit_logs(organization_id,actor_id,action,target_type,target_id,request_id,previous_state,new_state,details) values(p_organization_id,p_actor_id,'transition_season','season',season.id,p_request_id,p_expected_status,p_to,pg_catalog.jsonb_build_object('reason',p_reason));
  if p_to='registration_open' then insert into public.sd_registration_notification_intents(organization_id,season_id,intent_type,deduplication_key,payload,created_by) values(p_organization_id,season.id,'registration_opened',p_request_id::text||':registration_opened',pg_catalog.jsonb_build_object('season_id',season.id,'season_name',season.name),p_actor_id); end if;
  return pg_catalog.jsonb_build_object('season',pg_catalog.to_jsonb(season),'replayed',false);
end $$;

create or replace function public.sd_submit_registration(p_organization_id uuid,p_actor_id uuid,p_application_id uuid,p_expected_version integer,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare application public.sd_registration_applications%rowtype; offering public.sd_registration_offerings%rowtype; missing_count integer; approved_count integer; waiting_count integer; next_state text:='submitted';
begin
  if exists(select 1 from public.sd_registration_audit_logs where organization_id=p_organization_id and request_id=p_request_id and action='submit_registration') then select * into application from public.sd_registration_applications where id=p_application_id; return pg_catalog.jsonb_build_object('application',pg_catalog.to_jsonb(application),'replayed',true); end if;
  select * into application from public.sd_registration_applications where id=p_application_id and organization_id=p_organization_id for update;
  if application.id is null then raise exception using errcode='P0002',message='registration_not_found'; end if;
  if application.applicant_user_id<>p_actor_id and application.guardian_user_id is distinct from p_actor_id and not exists(select 1 from public.sd_parent_child_links where org_id=p_organization_id and parent_id=p_actor_id and child_id=application.player_user_id) then raise exception using errcode='42501',message='registration_party_required'; end if;
  if application.state<>'draft' or application.version<>p_expected_version then raise exception using errcode='P0001',message='stale_registration'; end if;
  select * into offering from public.sd_registration_offerings where id=application.offering_id and organization_id=p_organization_id for update;
  if offering.state<>'active' or pg_catalog.now() not between offering.opens_at and offering.closes_at then raise exception using errcode='P0001',message='registration_closed'; end if;
  select pg_catalog.count(*) into missing_count from public.sd_registration_offering_requirements x left join public.sd_registration_requirement_responses r on r.application_id=application.id and r.requirement_template_id=x.requirement_template_id where x.offering_id=offering.id and x.required and pg_catalog.coalesce(r.status,'missing')<>'accepted';
  if missing_count>0 then raise exception using errcode='P0001',message='registration_requirements_missing'; end if;
  select pg_catalog.count(*) into approved_count from public.sd_registration_applications where offering_id=offering.id and state in ('approved','assigned','completed');
  if offering.capacity is not null and approved_count>=offering.capacity then
    select pg_catalog.count(*) into waiting_count from public.sd_registration_waitlist where offering_id=offering.id and status in ('waiting','offered','accepted');
    if offering.waitlist_capacity is not null and waiting_count>=offering.waitlist_capacity then raise exception using errcode='P0001',message='registration_full'; end if;
    next_state:='waitlisted';
  end if;
  update public.sd_registration_applications set state=next_state,submitted_at=pg_catalog.now(),fee_cents=offering.fee_cents,fee_status=case when offering.fee_cents>0 then 'due' else 'not_due' end,balance_cents=offering.fee_cents,version=version+1,updated_at=pg_catalog.now() where id=application.id returning * into application;
  if next_state='waitlisted' then insert into public.sd_registration_waitlist(organization_id,offering_id,application_id) values(p_organization_id,offering.id,application.id) on conflict(application_id) do nothing; end if;
  insert into public.sd_registration_audit_logs(organization_id,actor_id,action,target_type,target_id,request_id,previous_state,new_state) values(p_organization_id,p_actor_id,'submit_registration','application',application.id,p_request_id,'draft',next_state);
  insert into public.sd_registration_notification_intents(organization_id,application_id,season_id,intent_type,deduplication_key,payload,created_by) values(p_organization_id,application.id,application.season_id,case when next_state='waitlisted' then 'registration_waitlisted' else 'registration_submitted' end,p_request_id::text||':'||next_state,pg_catalog.jsonb_build_object('application_id',application.id,'balance_cents',application.balance_cents),p_actor_id);
  if application.balance_cents>0 then insert into public.sd_registration_notification_intents(organization_id,application_id,season_id,intent_type,deduplication_key,payload,created_by) values(p_organization_id,application.id,application.season_id,'registration_balance_due',p_request_id::text||':balance_due',pg_catalog.jsonb_build_object('application_id',application.id,'balance_cents',application.balance_cents),p_actor_id); end if;
  return pg_catalog.jsonb_build_object('application',pg_catalog.to_jsonb(application),'replayed',false);
end $$;

create or replace function public.sd_review_registration(p_organization_id uuid,p_actor_id uuid,p_application_id uuid,p_action text,p_expected_version integer,p_request_id uuid,p_notes text) returns jsonb language plpgsql security definer set search_path='' as $$
declare application public.sd_registration_applications%rowtype; next_state text; prior_state text;
begin
  if not exists(select 1 from public.sd_org_memberships where org_id=p_organization_id and user_id=p_actor_id and status='active' and role in ('owner','admin')) then raise exception using errcode='42501',message='review_registrations_required'; end if;
  next_state:=case p_action when 'start_review' then 'under_review' when 'request_action' then 'action_required' when 'approve' then 'approved' when 'waitlist' then 'waitlisted' when 'decline' then 'declined' else null end;
  if next_state is null then raise exception using errcode='22023',message='invalid_review_action'; end if;
  if exists(select 1 from public.sd_registration_audit_logs where organization_id=p_organization_id and request_id=p_request_id and action='review_registration') then select * into application from public.sd_registration_applications where id=p_application_id; return pg_catalog.jsonb_build_object('application',pg_catalog.to_jsonb(application),'replayed',true); end if;
  select * into application from public.sd_registration_applications where id=p_application_id and organization_id=p_organization_id for update;
  if application.id is null or application.version<>p_expected_version then raise exception using errcode='P0001',message='stale_registration'; end if;
  if application.state not in ('submitted','under_review','action_required','waitlisted') then raise exception using errcode='P0001',message='invalid_registration_transition'; end if;
  if next_state='approved' and exists(select 1 from public.sd_registration_offering_requirements x left join public.sd_registration_requirement_responses r on r.application_id=application.id and r.requirement_template_id=x.requirement_template_id where x.offering_id=application.offering_id and x.required and pg_catalog.coalesce(r.status,'missing')<>'accepted') then raise exception using errcode='P0001',message='registration_requirements_missing'; end if;
  prior_state:=application.state;
  update public.sd_registration_applications set state=next_state,reviewer_notes=p_notes,reviewed_at=pg_catalog.now(),version=version+1,updated_at=pg_catalog.now() where id=application.id returning * into application;
  if next_state='waitlisted' then insert into public.sd_registration_waitlist(organization_id,offering_id,application_id) values(p_organization_id,application.offering_id,application.id) on conflict(application_id) do update set status='waiting'; end if;
  if prior_state='waitlisted' and next_state='approved' then update public.sd_registration_waitlist set status='promoted',responded_at=pg_catalog.now() where application_id=application.id and status in ('waiting','accepted'); end if;
  insert into public.sd_registration_audit_logs(organization_id,actor_id,action,target_type,target_id,request_id,previous_state,new_state,details) values(p_organization_id,p_actor_id,'review_registration','application',application.id,p_request_id,prior_state,next_state,pg_catalog.jsonb_build_object('review_action',p_action));
  if next_state in ('approved','waitlisted','declined') then insert into public.sd_registration_notification_intents(organization_id,application_id,season_id,intent_type,deduplication_key,payload,created_by) values(p_organization_id,application.id,application.season_id,case next_state when 'approved' then 'registration_approved' when 'waitlisted' then 'registration_waitlisted' else 'registration_declined' end,p_request_id::text||':'||next_state,pg_catalog.jsonb_build_object('application_id',application.id,'notes',p_notes),p_actor_id); end if;
  return pg_catalog.jsonb_build_object('application',pg_catalog.to_jsonb(application),'replayed',false);
end $$;

create or replace function public.sd_assign_registered_player(p_organization_id uuid,p_actor_id uuid,p_application_id uuid,p_team_id uuid,p_expected_version integer,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare application public.sd_registration_applications%rowtype; membership public.sd_player_team_memberships%rowtype; team_season uuid;
begin
  if not exists(select 1 from public.sd_org_memberships where org_id=p_organization_id and user_id=p_actor_id and status='active' and role in ('owner','admin')) then raise exception using errcode='42501',message='assign_registered_player_required'; end if;
  if exists(select 1 from public.sd_registration_audit_logs where organization_id=p_organization_id and request_id=p_request_id and action='assign_registration') then select * into application from public.sd_registration_applications where id=p_application_id; select * into membership from public.sd_player_team_memberships where id=application.team_assignment_id; return pg_catalog.jsonb_build_object('application',pg_catalog.to_jsonb(application),'membership',pg_catalog.to_jsonb(membership),'replayed',true); end if;
  select * into application from public.sd_registration_applications where id=p_application_id and organization_id=p_organization_id for update;
  if application.id is null or application.version<>p_expected_version then raise exception using errcode='P0001',message='stale_registration'; end if;
  if application.state<>'approved' or application.player_user_id is null then raise exception using errcode='P0001',message='approved_linked_player_required'; end if;
  select season_id into team_season from public.sd_teams where id=p_team_id and org_id=p_organization_id;
  if team_season is distinct from application.season_id then raise exception using errcode='P0001',message='team_season_mismatch'; end if;
  if exists(select 1 from public.sd_player_team_memberships where organization_id=p_organization_id and player_id=application.player_user_id and active and ended_at is null) then raise exception using errcode='23505',message='player_active_team_exists'; end if;
  insert into public.sd_player_team_memberships(player_id,organization_id,season_id,team_id,assignment_reason,created_by,updated_by) values(application.player_user_id,p_organization_id,application.season_id,p_team_id,'registration_assignment',p_actor_id,p_actor_id) returning * into membership;
  update public.sd_registration_applications set state='assigned',team_assignment_id=membership.id,assigned_at=pg_catalog.now(),version=version+1,updated_at=pg_catalog.now() where id=application.id returning * into application;
  insert into public.sd_registration_audit_logs(organization_id,actor_id,action,target_type,target_id,request_id,previous_state,new_state,details) values(p_organization_id,p_actor_id,'assign_registration','application',application.id,p_request_id,'approved','assigned',pg_catalog.jsonb_build_object('team_id',p_team_id,'membership_id',membership.id));
  insert into public.sd_registration_notification_intents(organization_id,application_id,season_id,intent_type,deduplication_key,payload,created_by) values(p_organization_id,application.id,application.season_id,'team_assignment',p_request_id::text||':team_assignment',pg_catalog.jsonb_build_object('application_id',application.id,'team_id',p_team_id),p_actor_id);
  return pg_catalog.jsonb_build_object('application',pg_catalog.to_jsonb(application),'membership',pg_catalog.to_jsonb(membership));
end $$;

create or replace function public.sd_execute_season_rollover(p_organization_id uuid,p_actor_id uuid,p_plan_id uuid,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare plan public.sd_season_rollover_plans%rowtype; target public.sd_seasons%rowtype; team_count integer:=0; offering_count integer:=0; requirement_count integer:=0;
begin
  if not exists(select 1 from public.sd_org_memberships where org_id=p_organization_id and user_id=p_actor_id and status='active' and role in ('owner','admin')) then raise exception using errcode='42501',message='execute_season_rollover_required'; end if;
  if exists(select 1 from public.sd_registration_audit_logs where organization_id=p_organization_id and request_id=p_request_id and action='execute_season_rollover') then select * into plan from public.sd_season_rollover_plans where id=p_plan_id; select * into target from public.sd_seasons where id=plan.target_season_id; return pg_catalog.jsonb_build_object('season',pg_catalog.to_jsonb(target),'replayed',true); end if;
  select * into plan from public.sd_season_rollover_plans where id=p_plan_id and organization_id=p_organization_id for update;
  if plan.id is null or plan.state<>'confirmed' then raise exception using errcode='P0001',message='confirmed_rollover_plan_required'; end if;
  insert into public.sd_seasons(organization_id,name,start_date,end_date,status,is_default,created_by,updated_by) values(p_organization_id,plan.target_name,plan.target_start_date,plan.target_end_date,'planning',false,p_actor_id,p_actor_id) returning * into target;
  if pg_catalog.coalesce((plan.copy_options->>'teams')::boolean,false) then
    insert into public.sd_teams(org_id,season_id,name,color_hex,description,is_active,sort_order,created_by)
      select p_organization_id,target.id,pg_catalog.left(t.name||' · '||target.name,120),t.color_hex,t.description,true,t.sort_order,p_actor_id from public.sd_teams t where t.org_id=p_organization_id and t.season_id=plan.source_season_id;
    get diagnostics team_count=row_count;
  end if;
  if pg_catalog.coalesce((plan.copy_options->>'coach_assignments')::boolean,false) and team_count>0 then
    insert into public.sd_coach_team_assignments(coach_id,organization_id,season_id,team_id,is_primary,organization_wide_access,created_by,updated_by)
      select a.coach_id,p_organization_id,target.id,new_team.id,false,a.organization_wide_access,p_actor_id,p_actor_id from public.sd_coach_team_assignments a join public.sd_teams old_team on old_team.id=a.team_id join public.sd_teams new_team on new_team.org_id=p_organization_id and new_team.season_id=target.id and new_team.name=pg_catalog.left(old_team.name||' · '||target.name,120) where a.organization_id=p_organization_id and a.season_id=plan.source_season_id and a.active and a.ended_at is null;
    insert into public.sd_coach_team_responsibilities(assignment_id,responsibility,created_by)
      select new_assignment.id,r.responsibility,p_actor_id
      from public.sd_coach_team_assignments new_assignment
      join public.sd_teams new_team on new_team.id=new_assignment.team_id
      join public.sd_coach_team_assignments old_assignment on old_assignment.coach_id=new_assignment.coach_id and old_assignment.organization_id=p_organization_id and old_assignment.season_id=plan.source_season_id
      join public.sd_teams old_team on old_team.id=old_assignment.team_id and new_team.name=pg_catalog.left(old_team.name||' · '||target.name,120)
      join public.sd_coach_team_responsibilities r on r.assignment_id=old_assignment.id
      where new_assignment.season_id=target.id
      on conflict do nothing;
  end if;
  if pg_catalog.coalesce((plan.copy_options->>'offerings')::boolean,false) then
    insert into public.sd_registration_offerings(organization_id,season_id,team_id,offering_type,name,description,opens_at,closes_at,capacity,waitlist_capacity,age_guidance,graduation_year_guidance,eligibility_notes,fee_cents,deposit_cents,installment_configuration,refund_policy,custom_questions,state,visibility,auto_assign_team,created_by,updated_by)
      select p_organization_id,target.id,new_team.id,o.offering_type,o.name,o.description,pg_catalog.coalesce(target.start_date::timestamptz,pg_catalog.now()),pg_catalog.coalesce(target.end_date::timestamptz,pg_catalog.now()+interval '90 days'),o.capacity,o.waitlist_capacity,o.age_guidance,o.graduation_year_guidance,o.eligibility_notes,o.fee_cents,o.deposit_cents,o.installment_configuration,o.refund_policy,o.custom_questions,'draft',o.visibility,o.auto_assign_team,p_actor_id,p_actor_id from public.sd_registration_offerings o left join public.sd_teams old_team on old_team.id=o.team_id left join public.sd_teams new_team on new_team.org_id=p_organization_id and new_team.season_id=target.id and new_team.name=pg_catalog.left(old_team.name||' · '||target.name,120) where o.organization_id=p_organization_id and o.season_id=plan.source_season_id;
    get diagnostics offering_count=row_count;
  end if;
  if pg_catalog.coalesce((plan.copy_options->>'requirements')::boolean,false) then
    insert into public.sd_registration_requirement_templates(organization_id,season_id,name,requirement_type,version,content,expires_after_days,active,created_by,updated_by)
      select p_organization_id,target.id,pg_catalog.left(r.name||' · '||target.name,120),r.requirement_type,r.version,r.content,r.expires_after_days,true,p_actor_id,p_actor_id from public.sd_registration_requirement_templates r where r.organization_id=p_organization_id and (r.season_id=plan.source_season_id or r.season_id is null);
    get diagnostics requirement_count=row_count;
  end if;
  update public.sd_season_rollover_plans set state='executed',target_season_id=target.id,executed_at=pg_catalog.now(),updated_at=pg_catalog.now() where id=plan.id;
  insert into public.sd_registration_audit_logs(organization_id,actor_id,action,target_type,target_id,request_id,details) values(p_organization_id,p_actor_id,'execute_season_rollover','season',target.id,p_request_id,pg_catalog.jsonb_build_object('source_season_id',plan.source_season_id,'teams_copied',team_count,'offerings_copied',offering_count,'requirements_copied',requirement_count,'players_copied',0,'history_copied',false));
  return pg_catalog.jsonb_build_object('season',pg_catalog.to_jsonb(target),'teams_copied',team_count,'offerings_copied',offering_count,'requirements_copied',requirement_count,'players_copied',0,'replayed',false);
end $$;

revoke all on function public.sd_season_transition_allowed(text,text),public.sd_transition_season(uuid,uuid,uuid,text,text,uuid,text),public.sd_submit_registration(uuid,uuid,uuid,integer,uuid),public.sd_review_registration(uuid,uuid,uuid,text,integer,uuid,text),public.sd_assign_registered_player(uuid,uuid,uuid,uuid,integer,uuid),public.sd_execute_season_rollover(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.sd_season_transition_allowed(text,text),public.sd_transition_season(uuid,uuid,uuid,text,text,uuid,text),public.sd_submit_registration(uuid,uuid,uuid,integer,uuid),public.sd_review_registration(uuid,uuid,uuid,text,integer,uuid,text),public.sd_assign_registered_player(uuid,uuid,uuid,uuid,integer,uuid),public.sd_execute_season_rollover(uuid,uuid,uuid,uuid) to service_role;
