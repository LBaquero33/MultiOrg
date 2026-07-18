-- Phase 12I: explainable organization analytics and permissioned reports.
-- Aggregates authoritative operational tables at query time and returns an as_of timestamp.

create table public.sd_metric_definitions (
  key text primary key, domain text not null, name text not null, definition text not null, source_tables text[] not null,
  inclusion_rules text not null, exclusion_rules text not null, empty_behavior text not null default 'Return zero, never infer data', refresh_behavior text not null default 'Computed at request time', created_at timestamptz not null default pg_catalog.now()
);
insert into public.sd_metric_definitions(key,domain,name,definition,source_tables,inclusion_rules,exclusion_rules) values
('collected_revenue','financial','Collected revenue','Succeeded organization-customer payments received in range','{sd_payments}','financial_layer=organization_customer and status=succeeded','SaaS billing, Apple access, failed and reversed payments'),
('outstanding_receivables','financial','Outstanding receivables','Remaining balance on issued, partial, or overdue organization-customer invoices','{sd_invoices}','open organization-customer invoices','Draft, paid, void, cancelled, refunded, written-off invoices'),
('net_operating_result','financial','Net operating result','Collected revenue minus confirmed refunds and organization expenses','{sd_payments,sd_refunds,sd_expenses}','Authoritative collected, refunded, and expense rows','SaaS billing, Apple access, pending refunds'),
('registration_count','registration','Registration count','Applications created in the selected scope','{sd_registration_applications}','Applications in organization and filters','None'),
('capacity_utilization','registration','Capacity utilization','Approved, assigned, and completed applications divided by configured capacity','{sd_registration_offerings,sd_registration_applications}','Offerings with finite positive capacity','Unlimited offerings'),
('attendance_rate','operations','Attendance rate','Present, late, or partial attendance divided by finalized attendance outcomes','{sd_event_operation_participants,sd_event_operations}','Expected players on completed event operations with recorded attendance','Unknown or not-recorded outcomes'),
('availability_response_rate','operations','Availability response rate','Expected player responses divided by expected players','{sd_event_operation_participants}','Expected player participants','Staff and unknown responses'),
('communication_read_rate','communication','Communication read rate','Read announcement recipients divided by recipient snapshot size','{sd_announcement_recipients}','Published announcement recipient snapshots','Draft announcements'),
('notification_delivery_success','communication','Notification delivery success','Delivered push attempts divided by terminal push attempts','{sd_notification_deliveries,sd_notifications}','Sent or terminal attempts in scope','Pending and retryable attempts')
on conflict(key) do update set definition=excluded.definition,source_tables=excluded.source_tables,inclusion_rules=excluded.inclusion_rules,exclusion_rules=excluded.exclusion_rules;

create table public.sd_report_runs (
  id uuid primary key default pg_catalog.gen_random_uuid(), organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  requested_by uuid not null references auth.users(id), report_type text not null check(report_type in ('financial_summary','receivables_aging','revenue_detail','expense_detail','registration_status','team_roster','attendance','availability','schedule','practice_completion','game_completion','communication_delivery','missing_requirements','season_summary')),
  filters jsonb not null default '{}'::jsonb, format text not null check(format in ('json','csv','print')), status text not null default 'completed' check(status in ('pending','running','completed','failed','expired')),
  row_count integer not null default 0, redaction_profile text not null, as_of timestamptz not null default pg_catalog.now(), expires_at timestamptz, failure_reason text, created_at timestamptz not null default pg_catalog.now()
);
create index idx_sd_report_runs_scope on public.sd_report_runs(organization_id,requested_by,created_at desc);
alter table public.sd_metric_definitions enable row level security; alter table public.sd_report_runs enable row level security;
revoke all on table public.sd_metric_definitions,public.sd_report_runs from public,anon,authenticated;
grant select on table public.sd_metric_definitions to authenticated; grant select on table public.sd_report_runs to authenticated;
grant select,insert,update,delete on table public.sd_metric_definitions,public.sd_report_runs to service_role;
create policy sd_metric_definitions_read on public.sd_metric_definitions for select to authenticated using(true);
create policy sd_report_runs_owner_or_admin_read on public.sd_report_runs for select to authenticated using(requested_by=(select auth.uid()) or exists(select 1 from public.sd_org_memberships m where m.org_id=organization_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin')));

create or replace function public.sd_organization_analytics(p_organization_id uuid,p_actor_id uuid,p_filters jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare from_at timestamptz:=pg_catalog.coalesce((p_filters->>'from')::timestamptz,'-infinity'::timestamptz); to_at timestamptz:=pg_catalog.coalesce((p_filters->>'to')::timestamptz,pg_catalog.now()); season_filter uuid:=nullif(p_filters->>'season_id','')::uuid; team_filter uuid:=nullif(p_filters->>'team_id','')::uuid; result jsonb;
begin
  if not exists(select 1 from public.sd_org_memberships where org_id=p_organization_id and user_id=p_actor_id and status='active' and role in ('owner','admin')) then raise exception using errcode='42501',message='view_org_analytics_required'; end if;
  with financial as (
    select
      pg_catalog.coalesce((select sum(i.total_cents) from public.sd_invoices i where i.org_id=p_organization_id and i.financial_layer='organization_customer' and i.status<>'draft' and i.created_at between from_at and to_at and (season_filter is null or i.season_id=season_filter) and (team_filter is null or i.team_id=team_filter)),0) gross_invoiced,
      pg_catalog.coalesce((select sum(p.amount_cents) from public.sd_payments p where p.org_id=p_organization_id and p.financial_layer='organization_customer' and p.status in ('succeeded','paid') and pg_catalog.coalesce(p.received_at,p.paid_at,p.created_at) between from_at and to_at),0) collected,
      pg_catalog.coalesce((select sum(i.amount_remaining_cents) from public.sd_invoices i where i.org_id=p_organization_id and i.financial_layer='organization_customer' and i.status in ('issued','partially_paid','overdue')),0) receivable,
      pg_catalog.coalesce((select sum(i.amount_remaining_cents) from public.sd_invoices i where i.org_id=p_organization_id and i.financial_layer='organization_customer' and i.status in ('issued','partially_paid','overdue') and i.due_date<pg_catalog.current_date),0) overdue,
      pg_catalog.coalesce((select sum(r.amount_cents) from public.sd_refunds r where r.org_id=p_organization_id and r.financial_layer='organization_customer' and r.status in ('succeeded','confirmed') and pg_catalog.coalesce(r.confirmed_at,r.created_at) between from_at and to_at),0) refunds,
      pg_catalog.coalesce((select sum(e.amount_cents) from public.sd_expenses e where e.org_id=p_organization_id and e.financial_layer='organization_expense' and e.expense_date between from_at::date and to_at::date and (season_filter is null or e.season_id=season_filter) and (team_filter is null or e.team_id=team_filter)),0) expenses
  ), registration as (
    select pg_catalog.count(*) total,pg_catalog.count(*) filter(where a.state='draft') drafts,pg_catalog.count(*) filter(where a.state in ('submitted','under_review','action_required')) submitted,pg_catalog.count(*) filter(where a.state='approved') approved,pg_catalog.count(*) filter(where a.state='waitlisted') waitlisted,pg_catalog.count(*) filter(where a.state='declined') declined,pg_catalog.count(*) filter(where a.state in ('assigned','completed')) assigned,pg_catalog.coalesce(sum(a.balance_cents),0) balance
    from public.sd_registration_applications a where a.organization_id=p_organization_id and a.created_at between from_at and to_at and (season_filter is null or a.season_id=season_filter) and (team_filter is null or a.team_preference_id=team_filter)
  ), operations as (
    select pg_catalog.count(*) events,pg_catalog.count(*) filter(where e.status='completed') completed,pg_catalog.count(*) filter(where e.event_type='practice' and e.status='completed') practices_completed,pg_catalog.count(*) filter(where e.event_type='game' and e.status='completed') games_completed,pg_catalog.count(*) filter(where e.status='cancelled') cancelled
    from public.sd_team_events e where e.organization_id=p_organization_id and e.start_at between from_at and to_at and (season_filter is null or e.season_id=season_filter) and (team_filter is null or e.team_id=team_filter)
  ), participation as (
    select pg_catalog.count(*) filter(where p.participant_type='player' and p.expected and p.attendance_status<>'not_recorded') attendance_recorded,pg_catalog.count(*) filter(where p.participant_type='player' and p.expected and p.attendance_status in ('present','late','partial')) attendance_positive,pg_catalog.count(*) filter(where p.participant_type='player' and p.expected) availability_expected,pg_catalog.count(*) filter(where p.participant_type='player' and p.expected and p.availability_status<>'unknown') availability_answered
    from public.sd_event_operation_participants p where p.organization_id=p_organization_id and (season_filter is null or p.season_id=season_filter) and (team_filter is null or p.team_id=team_filter)
  ), communication as (
    select pg_catalog.count(distinct a.id) announcements,pg_catalog.count(r.*) recipients,pg_catalog.count(r.*) filter(where r.read_at is not null) reads,pg_catalog.count(r.*) filter(where r.acknowledged_at is not null) acknowledgments,pg_catalog.count(r.*) filter(where a.acknowledgment_required) required_acknowledgments
    from public.sd_announcements a left join public.sd_announcement_recipients r on r.announcement_id=a.id where a.organization_id=p_organization_id and a.status='published' and a.publish_at between from_at and to_at and (season_filter is null or a.season_id=season_filter) and (team_filter is null or a.team_id=team_filter)
  )
  select pg_catalog.jsonb_build_object('as_of',pg_catalog.now(),'filters',p_filters,
    'financial',pg_catalog.jsonb_build_object('gross_invoiced_cents',f.gross_invoiced,'collected_cents',f.collected,'outstanding_cents',f.receivable,'overdue_cents',f.overdue,'refunds_cents',f.refunds,'expenses_cents',f.expenses,'net_operating_result_cents',f.collected-f.refunds-f.expenses),
    'registration',pg_catalog.to_jsonb(r),
    'operations',pg_catalog.to_jsonb(o)||pg_catalog.jsonb_build_object('attendance_rate',case when p.attendance_recorded=0 then null else pg_catalog.round(p.attendance_positive::numeric/p.attendance_recorded,4) end,'availability_response_rate',case when p.availability_expected=0 then null else pg_catalog.round(p.availability_answered::numeric/p.availability_expected,4) end),
    'communication',pg_catalog.to_jsonb(c)||pg_catalog.jsonb_build_object('read_rate',case when c.recipients=0 then null else pg_catalog.round(c.reads::numeric/c.recipients,4) end,'acknowledgment_rate',case when c.required_acknowledgments=0 then null else pg_catalog.round(c.acknowledgments::numeric/c.required_acknowledgments,4) end)) into result
  from financial f,registration r,operations o,participation p,communication c;
  return result;
end $$;

create or replace function public.sd_team_analytics(p_organization_id uuid,p_actor_id uuid,p_team_id uuid,p_from timestamptz,p_to timestamptz) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare caps text[]; result jsonb;
begin
  caps:=public.sd_resolve_team_capabilities(p_organization_id,p_team_id,p_actor_id);
  if not ('view_team' = any(caps) or 'manage_roster' = any(caps) or exists(select 1 from public.sd_org_memberships where org_id=p_organization_id and user_id=p_actor_id and status='active' and role in ('owner','admin'))) then raise exception using errcode='42501',message='view_team_analytics_required'; end if;
  select pg_catalog.jsonb_build_object('as_of',pg_catalog.now(),'team_id',p_team_id,'roster_count',(select pg_catalog.count(*) from public.sd_player_team_memberships where organization_id=p_organization_id and team_id=p_team_id and active and ended_at is null),'event_count',(select pg_catalog.count(*) from public.sd_team_events where organization_id=p_organization_id and team_id=p_team_id and start_at between p_from and p_to),'completed_practices',(select pg_catalog.count(*) from public.sd_team_events where organization_id=p_organization_id and team_id=p_team_id and event_type='practice' and status='completed' and start_at between p_from and p_to),'completed_games',(select pg_catalog.count(*) from public.sd_team_events where organization_id=p_organization_id and team_id=p_team_id and event_type='game' and status='completed' and start_at between p_from and p_to)) into result;
  return result;
end $$;

revoke all on function public.sd_organization_analytics(uuid,uuid,jsonb),public.sd_team_analytics(uuid,uuid,uuid,timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function public.sd_organization_analytics(uuid,uuid,jsonb),public.sd_team_analytics(uuid,uuid,uuid,timestamptz,timestamptz) to service_role;

create or replace function public.sd_resolve_organization_capabilities(target_organization uuid,target_actor uuid default auth.uid()) returns text[] language sql stable security definer set search_path='' as $$
  with membership as (select role from public.sd_org_memberships where org_id=target_organization and user_id=target_actor and status='active'), capabilities(capability) as (
    select pg_catalog.unnest(array[
      'view_team_communication','send_team_message','send_player_message','send_parent_message','send_staff_message','create_team_announcement','create_org_announcement','manage_announcement','view_delivery_status','manage_communication_policy','moderate_communication','manage_notification_preferences','manage_notification_delivery',
      'view_registration_offerings','manage_registration_offerings','review_registrations','approve_registration','manage_waitlist','assign_registered_player','manage_requirements','view_registration_financial_status','manage_season_lifecycle','execute_season_rollover',
      'view_financial_overview','view_customer_accounts','create_invoice','edit_draft_invoice','issue_invoice','void_invoice','record_payment','apply_payment','issue_refund','issue_credit','write_off_balance','manage_expenses','approve_expense','view_registration_balances','view_payment_provider_state','manage_payment_provider_state','export_financial_data','view_financial_audit',
      'view_org_analytics','view_financial_analytics','view_registration_analytics','view_operations_analytics','view_team_analytics','view_communication_analytics','run_reports','export_reports','view_personal_summary','view_household_summary'
    ]) where exists(select 1 from membership where role in ('owner','admin'))
    union select pg_catalog.unnest(array['view_team_communication','send_team_message','send_player_message','send_parent_message','send_staff_message','create_team_announcement','view_registration_offerings','view_team_analytics','view_operations_analytics']) where exists(select 1 from membership where role='coach')
    union select pg_catalog.unnest(array['view_team_communication','send_player_message','manage_notification_preferences','view_registration_offerings','submit_registration','view_personal_summary']) where exists(select 1 from membership where role='player')
    union select pg_catalog.unnest(array['view_team_communication','send_parent_message','manage_notification_preferences','view_registration_offerings','submit_registration','manage_child_registration','view_registration_financial_status','view_customer_accounts','view_household_summary']) where exists(select 1 from membership where role='parent')
  ) select pg_catalog.coalesce(pg_catalog.array_agg(capability order by capability),'{}'::text[]) from capabilities;
$$;
revoke all on function public.sd_resolve_organization_capabilities(uuid,uuid) from public,anon,authenticated;
grant execute on function public.sd_resolve_organization_capabilities(uuid,uuid) to service_role;

-- Final recipient resolver is installed after registration and finance tables
-- exist so every Phase 12F audience remains deterministic and snapshottable.
create or replace function public.sd_expand_communication_recipients(p_organization_id uuid,p_audience_type text,p_filter jsonb)
returns table(user_id uuid,subject_player_id uuid,reason text) language sql stable security definer set search_path='' as $$
  select distinct expanded.user_id,expanded.subject_player_id,expanded.reason from (
    select m.user_id,null::uuid,'organization_member' from public.sd_org_memberships m where m.org_id=p_organization_id and m.status='active' and p_audience_type='organization'
    union all select m.user_id,null::uuid,'season_member' from public.sd_org_memberships m where m.org_id=p_organization_id and m.status='active' and p_audience_type='season'
    union all select pm.player_id,pm.player_id,'team_player' from public.sd_player_team_memberships pm where pm.organization_id=p_organization_id and (nullif(p_filter->>'team_id','') is null or pm.team_id=nullif(p_filter->>'team_id','')::uuid) and pm.active and pm.ended_at is null and p_audience_type in ('team','players')
    union all select ca.coach_id,null::uuid,'team_staff' from public.sd_coach_team_assignments ca where ca.organization_id=p_organization_id and (nullif(p_filter->>'team_id','') is null or ca.team_id=nullif(p_filter->>'team_id','')::uuid) and ca.active and ca.ended_at is null and p_audience_type in ('team','team_staff')
    union all select l.parent_id,pm.player_id,'linked_parent' from public.sd_player_team_memberships pm join public.sd_parent_child_links l on l.org_id=pm.organization_id and l.child_id=pm.player_id where pm.organization_id=p_organization_id and (nullif(p_filter->>'team_id','') is null or pm.team_id=nullif(p_filter->>'team_id','')::uuid) and pm.active and pm.ended_at is null and p_audience_type in ('team','parents','households')
    union all select nullif(p_filter->>'user_id','')::uuid,nullif(p_filter->>'subject_player_id','')::uuid,'individual' where p_audience_type='individual'
    union all select ep.user_id,case when ep.participant_type='player' then ep.user_id else null end,'event_participant' from public.sd_event_operation_participants ep join public.sd_event_operations eo on eo.id=ep.event_operation_id where eo.organization_id=p_organization_id and eo.event_id=nullif(p_filter->>'event_id','')::uuid and ep.expected and p_audience_type='event_participants'
    union all select ep.user_id,ep.user_id,'unavailable_player' from public.sd_event_operation_participants ep where ep.organization_id=p_organization_id and ep.event_id=nullif(p_filter->>'event_id','')::uuid and ep.participant_type='player' and ep.availability_status='unavailable' and p_audience_type='unavailable_players'
    union all select ep.user_id,ep.user_id,'missing_availability' from public.sd_event_operation_participants ep where ep.organization_id=p_organization_id and ep.event_id=nullif(p_filter->>'event_id','')::uuid and ep.participant_type='player' and ep.availability_status='unknown' and p_audience_type='missing_availability'
    union all select ep.user_id,ep.user_id,'missing_attendance' from public.sd_event_operation_participants ep where ep.organization_id=p_organization_id and ep.event_id=nullif(p_filter->>'event_id','')::uuid and ep.participant_type='player' and ep.attendance_status='not_recorded' and p_audience_type='missing_attendance'
    union all select a.applicant_user_id,a.player_user_id,'registrant' from public.sd_registration_applications a where a.organization_id=p_organization_id and (nullif(p_filter->>'offering_id','') is null or a.offering_id=nullif(p_filter->>'offering_id','')::uuid) and a.state not in ('draft','withdrawn','cancelled') and p_audience_type='registrants'
    union all select a.applicant_user_id,a.player_user_id,'waitlisted_registrant' from public.sd_registration_applications a where a.organization_id=p_organization_id and (nullif(p_filter->>'offering_id','') is null or a.offering_id=nullif(p_filter->>'offering_id','')::uuid) and a.state='waitlisted' and p_audience_type='waitlisted'
    union all select pg_catalog.coalesce(a.guardian_user_id,a.applicant_user_id),a.player_user_id,'missing_requirement' from public.sd_registration_applications a where a.organization_id=p_organization_id and exists(select 1 from public.sd_registration_requirement_responses r where r.application_id=a.id and r.status in ('missing','expired','resign_required','rejected')) and p_audience_type='missing_requirements'
    union all select pg_catalog.coalesce(c.responsible_user_id,c.user_id),cap.player_id,'unpaid_balance' from public.sd_customer_accounts c left join public.sd_customer_account_players cap on cap.account_id=c.id where c.org_id=p_organization_id and exists(select 1 from public.sd_invoices i where i.customer_account_id=c.id and i.financial_layer='organization_customer' and i.amount_remaining_cents>0 and i.status in ('issued','partially_paid','overdue')) and p_audience_type='unpaid_balances'
  ) expanded where expanded.user_id is not null;
$$;
revoke all on function public.sd_expand_communication_recipients(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.sd_expand_communication_recipients(uuid,text,jsonb) to service_role;

create or replace function public.sd_consume_organization_notification_intent(p_source_type text,p_source_id uuid,p_actor_id uuid,p_dry_run boolean default true) returns jsonb language plpgsql security definer set search_path='' as $$
declare organization_id uuid; intent_type text; payload jsonb; deduplication_key text; application_id uuid; customer_account_id uuid; invoice_id uuid; recipient_id uuid; subject_id uuid; preference jsonb; category text; source_name text; route text; title text; body text; required boolean:=false; notification_id uuid; delivered integer:=0; suppressed integer:=0;
begin
  if p_source_type='registration' then
    select i.organization_id,i.intent_type,i.payload,i.deduplication_key,i.application_id into organization_id,intent_type,payload,deduplication_key,application_id from public.sd_registration_notification_intents i where i.id=p_source_id and i.consumed_at is null for update;
    select pg_catalog.coalesce(a.guardian_user_id,a.applicant_user_id),a.player_user_id into recipient_id,subject_id from public.sd_registration_applications a where a.id=application_id;
    category:=case when intent_type='registration_balance_due' then 'payment_notice' else 'registration' end; source_name:='registration'; route:='registration';
  elsif p_source_type='finance' then
    select i.org_id,i.intent_type,i.payload,i.deduplication_key,i.customer_account_id,i.invoice_id into organization_id,intent_type,payload,deduplication_key,customer_account_id,invoice_id from public.sd_financial_notification_intents i where i.id=p_source_id and i.consumed_at is null for update;
    select pg_catalog.coalesce(a.responsible_user_id,a.user_id),cap.player_id into recipient_id,subject_id from public.sd_customer_accounts a left join lateral(select player_id from public.sd_customer_account_players where account_id=a.id order by created_at limit 1) cap on true where a.id=customer_account_id;
    if recipient_id is null and invoice_id is not null then select i.payer_id,i.child_id into recipient_id,subject_id from public.sd_invoices i where i.id=invoice_id; end if;
    category:='payment_notice'; source_name:='organization_finance'; route:='finance';
  else raise exception using errcode='22023',message='invalid_notification_source'; end if;
  if organization_id is null then raise exception using errcode='P0002',message='notification_intent_not_found'; end if;
  if not exists(select 1 from public.sd_org_memberships where org_id=organization_id and user_id=p_actor_id and status='active' and role in ('owner','admin')) then raise exception using errcode='42501',message='manage_notification_delivery_required'; end if;
  if recipient_id is null then raise exception using errcode='P0001',message='notification_recipient_missing'; end if;
  required:=intent_type in ('required_form_missing','waiver_missing','invoice_overdue');
  title:=pg_catalog.initcap(pg_catalog.replace(intent_type,'_',' ')); body:=pg_catalog.coalesce(nullif(payload->>'body',''),'Open Home Plate for details.');
  preference:=public.sd_effective_notification_preference(recipient_id,organization_id,null,subject_id,case category when 'payment_notice' then 'payments' else 'registration' end,required);
  if not p_dry_run then
    if (preference->>'in_app')::boolean or (preference->>'push')::boolean then
      insert into public.sd_notifications(org_id,recipient_user_id,category,title,body,related_entity_type,related_entity_id,action_route,action_payload,deduplication_key,created_by,source,metadata,archived_at)
        values(organization_id,recipient_id,category,title,body,p_source_type,p_source_id::text,route,payload,deduplication_key,p_actor_id,source_name,pg_catalog.jsonb_build_object('intent_id',p_source_id,'push_suppressed',not((preference->>'push')::boolean)),case when (preference->>'in_app')::boolean then null else pg_catalog.now() end)
        on conflict(org_id,recipient_user_id,category,deduplication_key) do update set metadata=excluded.metadata returning id into notification_id;
      delivered:=1;
    else suppressed:=1; end if;
    insert into public.sd_notification_intent_receipts(organization_id,source_type,source_id,recipient_user_id,category,delivery_state,preference_decision,notification_id,deep_link,delivered_at)
      values(organization_id,p_source_type,p_source_id,recipient_id,category,case when delivered=1 then 'delivered' else 'suppressed' end,case when delivered=1 then 'deliver' else 'preference_suppressed' end,notification_id,pg_catalog.jsonb_build_object('route',route,'payload',payload),case when delivered=1 then pg_catalog.now() else null end) on conflict do nothing;
    if p_source_type='registration' then update public.sd_registration_notification_intents set consumed_at=pg_catalog.now() where id=p_source_id; else update public.sd_financial_notification_intents set consumed_at=pg_catalog.now() where id=p_source_id; end if;
  end if;
  return pg_catalog.jsonb_build_object('source_type',p_source_type,'source_id',p_source_id,'dry_run',p_dry_run,'recipient_count',1,'delivered_count',delivered,'suppressed_count',suppressed);
end $$;
revoke all on function public.sd_consume_organization_notification_intent(text,uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.sd_consume_organization_notification_intent(text,uuid,uuid,boolean) to service_role;
