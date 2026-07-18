-- Phase 12H: organization customer finance operations.
-- Existing SaaS billing and Apple subscription tables remain separate and authoritative.
-- No provider calls are made here; online refunds remain pending until webhook confirmation.

create table public.sd_customer_accounts (
  id uuid primary key default pg_catalog.gen_random_uuid(), org_id uuid not null references public.sd_orgs(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete set null, responsible_user_id uuid references public.profiles(id) on delete set null,
  account_type text not null check(account_type in ('user','parent_guardian','household','external')),
  display_name text not null, billing_email text, billing_phone text, external_reference text,
  credit_balance_cents integer not null default 0 check(credit_balance_cents>=0), currency text not null default 'usd', active boolean not null default true,
  version integer not null default 1, created_by uuid not null references public.profiles(id), updated_by uuid references public.profiles(id), created_at timestamptz not null default pg_catalog.now(), updated_at timestamptz not null default pg_catalog.now(), unique(org_id,id)
);
create table public.sd_customer_account_players (
  account_id uuid not null references public.sd_customer_accounts(id) on delete cascade, player_id uuid not null references public.profiles(id) on delete restrict,
  relationship text, created_at timestamptz not null default pg_catalog.now(), primary key(account_id,player_id)
);

alter table public.sd_invoices
  add column if not exists invoice_number text,
  add column if not exists financial_layer text not null default 'organization_customer',
  add column if not exists customer_account_id uuid references public.sd_customer_accounts(id) on delete restrict,
  add column if not exists season_id uuid references public.sd_seasons(id) on delete set null,
  add column if not exists registration_application_id uuid references public.sd_registration_applications(id) on delete set null,
  add column if not exists issue_date date,
  add column if not exists notes text,
  add column if not exists internal_notes text,
  add column if not exists payment_terms text,
  add column if not exists credit_cents integer not null default 0,
  add column if not exists written_off_cents integer not null default 0,
  add column if not exists written_off_at timestamptz,
  add column if not exists cancelled_at timestamptz,
  add column if not exists version integer not null default 1;
alter table public.sd_invoices add constraint sd_invoices_financial_layer_check check(financial_layer in ('organization_customer','home_plate_saas','apple_player_access'));
alter table public.sd_invoices add constraint sd_invoices_adjustments_nonnegative check(credit_cents>=0 and written_off_cents>=0);
create unique index uq_sd_invoices_org_number on public.sd_invoices(org_id,invoice_number) where invoice_number is not null;

create table public.sd_invoice_installments (
  id uuid primary key default pg_catalog.gen_random_uuid(), org_id uuid not null references public.sd_orgs(id) on delete cascade,
  invoice_id uuid not null references public.sd_invoices(id) on delete cascade, sequence integer not null, due_date date not null,
  amount_cents integer not null check(amount_cents>0), amount_paid_cents integer not null default 0 check(amount_paid_cents>=0), grace_days integer not null default 0 check(grace_days between 0 and 90),
  status text not null default 'scheduled' check(status in ('scheduled','partial','paid','past_due','waived','cancelled')),
  created_at timestamptz not null default pg_catalog.now(), updated_at timestamptz not null default pg_catalog.now(), unique(invoice_id,sequence)
);

alter table public.sd_payments
  add column if not exists financial_layer text not null default 'organization_customer',
  add column if not exists customer_account_id uuid references public.sd_customer_accounts(id) on delete set null,
  add column if not exists recorded_by uuid references public.profiles(id) on delete set null,
  add column if not exists received_at timestamptz,
  add column if not exists external_reference text,
  add column if not exists unapplied_cents integer not null default 0,
  add column if not exists reversed_at timestamptz,
  add column if not exists version integer not null default 1;
alter table public.sd_payments add constraint sd_payments_financial_layer_check check(financial_layer in ('organization_customer','home_plate_saas','apple_player_access'));
alter table public.sd_payments add constraint sd_payments_unapplied_check check(unapplied_cents>=0 and unapplied_cents<=amount_cents);
create unique index uq_sd_payments_org_external_reference on public.sd_payments(org_id,provider,external_reference) where external_reference is not null;

create table public.sd_payment_applications (
  id uuid primary key default pg_catalog.gen_random_uuid(), org_id uuid not null references public.sd_orgs(id) on delete cascade,
  payment_id uuid not null references public.sd_payments(id) on delete restrict, invoice_id uuid not null references public.sd_invoices(id) on delete restrict,
  amount_cents integer not null check(amount_cents>0), applied_by uuid not null references public.profiles(id), applied_at timestamptz not null default pg_catalog.now(),
  reversed_at timestamptz, reversal_reason text
);

create table public.sd_account_credits (
  id uuid primary key default pg_catalog.gen_random_uuid(), org_id uuid not null references public.sd_orgs(id) on delete cascade,
  customer_account_id uuid not null references public.sd_customer_accounts(id) on delete restrict, invoice_id uuid references public.sd_invoices(id) on delete set null,
  amount_cents integer not null check(amount_cents>0), remaining_cents integer not null check(remaining_cents>=0), status text not null default 'available' check(status in ('available','partially_applied','applied','void')),
  reason text not null, created_by uuid not null references public.profiles(id), created_at timestamptz not null default pg_catalog.now(), voided_at timestamptz
);

alter table public.sd_refunds
  add column if not exists financial_layer text not null default 'organization_customer',
  add column if not exists confirmed_at timestamptz,
  add column if not exists failure_reason text;

alter table public.sd_expenses
  add column if not exists financial_layer text not null default 'organization_expense',
  add column if not exists season_id uuid references public.sd_seasons(id) on delete set null,
  add column if not exists team_id uuid references public.sd_teams(id) on delete set null,
  add column if not exists facility_id uuid references public.sd_facilities(id) on delete set null,
  add column if not exists program_reference text,
  add column if not exists recurring boolean not null default false,
  add column if not exists tax_category_guidance text,
  add column if not exists reimbursement_status text not null default 'not_applicable',
  add column if not exists approved_by uuid references public.profiles(id) on delete set null,
  add column if not exists approved_at timestamptz,
  add column if not exists version integer not null default 1;
alter table public.sd_expenses add constraint sd_expenses_financial_layer_check check(financial_layer='organization_expense');
alter table public.sd_expenses add constraint sd_expenses_reimbursement_status_check check(reimbursement_status in ('not_applicable','requested','approved','paid','declined'));

create table public.sd_financial_reminder_policies (
  org_id uuid primary key references public.sd_orgs(id) on delete cascade, days_before_due integer[] not null default '{7,1}', days_after_due integer[] not null default '{1,7,14}',
  remind_on_due_date boolean not null default true, maximum_reminders integer not null default 6 check(maximum_reminders between 0 and 20), paused boolean not null default false,
  channels jsonb not null default '{"in_app":true,"push":true,"email_ready":false,"sms_ready":false}'::jsonb,
  updated_by uuid references public.profiles(id), updated_at timestamptz not null default pg_catalog.now()
);

create table public.sd_financial_notification_intents (
  id uuid primary key default pg_catalog.gen_random_uuid(), org_id uuid not null references public.sd_orgs(id) on delete cascade,
  customer_account_id uuid references public.sd_customer_accounts(id), invoice_id uuid references public.sd_invoices(id), payment_id uuid references public.sd_payments(id), refund_id uuid references public.sd_refunds(id),
  intent_type text not null check(intent_type in ('invoice_issued','upcoming_due','payment_due','invoice_overdue','payment_failed','partial_payment','payment_received','refund_issued','credit_issued','registration_balance_due')),
  deduplication_key text not null, payload jsonb not null default '{}'::jsonb, created_by uuid references public.profiles(id), created_at timestamptz not null default pg_catalog.now(), consumed_at timestamptz,
  unique(org_id,deduplication_key)
);

create table public.sd_financial_audit_logs (
  id uuid primary key default pg_catalog.gen_random_uuid(), org_id uuid not null references public.sd_orgs(id) on delete cascade,
  actor_id uuid references public.profiles(id), action text not null, target_type text not null, target_id uuid, request_id uuid not null,
  amount_cents integer, details jsonb not null default '{}'::jsonb, created_at timestamptz not null default pg_catalog.now(), unique(org_id,request_id,action)
);

create index idx_sd_customer_accounts_lookup on public.sd_customer_accounts(org_id,responsible_user_id,active);
create index idx_sd_invoice_installments_due on public.sd_invoice_installments(org_id,status,due_date);
create index idx_sd_payment_applications_invoice on public.sd_payment_applications(org_id,invoice_id,applied_at);
create index idx_sd_account_credits_account on public.sd_account_credits(org_id,customer_account_id,status);
create index idx_sd_financial_intents_pending on public.sd_financial_notification_intents(org_id,created_at) where consumed_at is null;
create index idx_sd_financial_audit_scope on public.sd_financial_audit_logs(org_id,created_at desc);

alter table public.sd_customer_accounts enable row level security; alter table public.sd_customer_account_players enable row level security;
alter table public.sd_invoice_installments enable row level security; alter table public.sd_payment_applications enable row level security;
alter table public.sd_account_credits enable row level security; alter table public.sd_financial_reminder_policies enable row level security;
alter table public.sd_financial_notification_intents enable row level security; alter table public.sd_financial_audit_logs enable row level security;

drop policy if exists "sd_org_billing_accounts_select_finance" on public.sd_org_billing_accounts;
drop policy if exists "sd_org_subscriptions_select_finance" on public.sd_org_subscriptions;
drop policy if exists "sd_player_subscriptions_select_finance" on public.sd_player_subscriptions;
drop policy if exists "sd_connected_payment_accounts_select_finance" on public.sd_connected_payment_accounts;
drop policy if exists "sd_invoices_select_finance" on public.sd_invoices;
drop policy if exists "sd_invoices_write_staff" on public.sd_invoices;
drop policy if exists "sd_invoice_items_select_finance" on public.sd_invoice_items;
drop policy if exists "sd_invoice_items_write_staff" on public.sd_invoice_items;
drop policy if exists "sd_payments_select_finance" on public.sd_payments;
drop policy if exists "sd_refunds_select_finance" on public.sd_refunds;
drop policy if exists "sd_expenses_select_staff" on public.sd_expenses;
drop policy if exists "sd_expenses_write_staff" on public.sd_expenses;
create policy sd_org_billing_accounts_admin_read on public.sd_org_billing_accounts for select to authenticated using(exists(select 1 from public.sd_org_memberships m where m.org_id=org_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin')) or public.sd_is_platform_admin_finance());
create policy sd_org_subscriptions_admin_read on public.sd_org_subscriptions for select to authenticated using(exists(select 1 from public.sd_org_memberships m where m.org_id=org_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin')) or public.sd_is_platform_admin_finance());
create policy sd_player_subscriptions_party_read on public.sd_player_subscriptions for select to authenticated using(player_id=(select auth.uid()) or billing_user_id=(select auth.uid()) or public.sd_is_linked_parent((select auth.uid()),player_id) or exists(select 1 from public.sd_org_memberships m where m.org_id=org_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin')) or public.sd_is_platform_admin_finance());
create policy sd_connected_accounts_admin_read on public.sd_connected_payment_accounts for select to authenticated using(exists(select 1 from public.sd_org_memberships m where m.org_id=org_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin')) or public.sd_is_platform_admin_finance());
create policy sd_invoices_party_read on public.sd_invoices for select to authenticated using(payer_id=(select auth.uid()) or public.sd_is_linked_parent((select auth.uid()),child_id) or exists(select 1 from public.sd_customer_accounts a where a.id=customer_account_id and (a.user_id=(select auth.uid()) or a.responsible_user_id=(select auth.uid()))) or exists(select 1 from public.sd_org_memberships m where m.org_id=org_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin')));
create policy sd_invoices_write_finance_admin on public.sd_invoices for all to authenticated using(exists(select 1 from public.sd_org_memberships m where m.org_id=org_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin'))) with check(exists(select 1 from public.sd_org_memberships m where m.org_id=org_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin')));
create policy sd_invoice_items_party_read on public.sd_invoice_items for select to authenticated using(exists(select 1 from public.sd_invoices i where i.id=invoice_id and (i.payer_id=(select auth.uid()) or public.sd_is_linked_parent((select auth.uid()),i.child_id) or exists(select 1 from public.sd_customer_accounts a where a.id=i.customer_account_id and (a.user_id=(select auth.uid()) or a.responsible_user_id=(select auth.uid()))) or exists(select 1 from public.sd_org_memberships m where m.org_id=i.org_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin')))));
create policy sd_invoice_items_write_finance_admin on public.sd_invoice_items for all to authenticated using(exists(select 1 from public.sd_org_memberships m where m.org_id=org_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin'))) with check(exists(select 1 from public.sd_org_memberships m where m.org_id=org_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin')));
create policy sd_payments_party_read on public.sd_payments for select to authenticated using(payer_id=(select auth.uid()) or exists(select 1 from public.sd_customer_accounts a where a.id=customer_account_id and (a.user_id=(select auth.uid()) or a.responsible_user_id=(select auth.uid()))) or exists(select 1 from public.sd_invoices i where i.id=invoice_id and public.sd_is_linked_parent((select auth.uid()),i.child_id)) or exists(select 1 from public.sd_org_memberships m where m.org_id=org_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin')));
create policy sd_refunds_party_read on public.sd_refunds for select to authenticated using(exists(select 1 from public.sd_payments p left join public.sd_customer_accounts a on a.id=p.customer_account_id left join public.sd_invoices i on i.id=p.invoice_id where p.id=payment_id and (p.payer_id=(select auth.uid()) or a.user_id=(select auth.uid()) or a.responsible_user_id=(select auth.uid()) or public.sd_is_linked_parent((select auth.uid()),i.child_id) or exists(select 1 from public.sd_org_memberships m where m.org_id=p.org_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin')))));
create policy sd_expenses_read_finance_admin on public.sd_expenses for select to authenticated using(exists(select 1 from public.sd_org_memberships m where m.org_id=org_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin')));
create policy sd_expenses_write_finance_admin on public.sd_expenses for all to authenticated using(exists(select 1 from public.sd_org_memberships m where m.org_id=org_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin'))) with check(exists(select 1 from public.sd_org_memberships m where m.org_id=org_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin')));

revoke all on table public.sd_customer_accounts,public.sd_customer_account_players,public.sd_invoice_installments,public.sd_payment_applications,public.sd_account_credits,public.sd_financial_reminder_policies,public.sd_financial_notification_intents,public.sd_financial_audit_logs from public,anon,authenticated;
grant select on table public.sd_customer_accounts,public.sd_customer_account_players,public.sd_invoice_installments,public.sd_payment_applications,public.sd_account_credits to authenticated;
grant select,insert,update,delete on table public.sd_customer_accounts,public.sd_customer_account_players,public.sd_invoice_installments,public.sd_payment_applications,public.sd_account_credits,public.sd_financial_reminder_policies,public.sd_financial_notification_intents,public.sd_financial_audit_logs to service_role;
create policy sd_customer_accounts_party_read on public.sd_customer_accounts for select to authenticated using(user_id=(select auth.uid()) or responsible_user_id=(select auth.uid()) or exists(select 1 from public.sd_org_memberships m where m.org_id=org_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin')));
create policy sd_customer_players_party_read on public.sd_customer_account_players for select to authenticated using(exists(select 1 from public.sd_customer_accounts a where a.id=account_id and (a.user_id=(select auth.uid()) or a.responsible_user_id=(select auth.uid()) or exists(select 1 from public.sd_parent_child_links l where l.org_id=a.org_id and l.parent_id=(select auth.uid()) and l.child_id=player_id) or exists(select 1 from public.sd_org_memberships m where m.org_id=a.org_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin')))));
create policy sd_installments_party_read on public.sd_invoice_installments for select to authenticated using(exists(select 1 from public.sd_invoices i where i.id=invoice_id and (i.payer_id=(select auth.uid()) or public.sd_is_linked_parent((select auth.uid()),i.child_id) or exists(select 1 from public.sd_org_memberships m where m.org_id=i.org_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin')))));
create policy sd_payment_applications_party_read on public.sd_payment_applications for select to authenticated using(exists(select 1 from public.sd_invoices i where i.id=invoice_id and (i.payer_id=(select auth.uid()) or public.sd_is_linked_parent((select auth.uid()),i.child_id) or exists(select 1 from public.sd_org_memberships m where m.org_id=i.org_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin')))));
create policy sd_account_credits_party_read on public.sd_account_credits for select to authenticated using(exists(select 1 from public.sd_customer_accounts a where a.id=customer_account_id and (a.user_id=(select auth.uid()) or a.responsible_user_id=(select auth.uid()) or exists(select 1 from public.sd_org_memberships m where m.org_id=a.org_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner','admin')))));

create or replace function public.sd_record_manual_payment(p_org_id uuid,p_actor_id uuid,p_customer_account_id uuid,p_amount_cents integer,p_currency text,p_method text,p_external_reference text,p_allocations jsonb,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare payment public.sd_payments%rowtype; allocation jsonb; invoice public.sd_invoices%rowtype; allocated integer:=0; item_amount integer;
begin
  if not exists(select 1 from public.sd_org_memberships where org_id=p_org_id and user_id=p_actor_id and status='active' and role in ('owner','admin')) then raise exception using errcode='42501',message='record_payment_required'; end if;
  if p_amount_cents<=0 or p_method not in ('cash','check','bank_transfer','card_terminal','external_provider','credit','adjustment','other') or pg_catalog.jsonb_typeof(p_allocations)<>'array' then raise exception using errcode='22023',message='invalid_payment'; end if;
  if exists(select 1 from public.sd_financial_audit_logs where org_id=p_org_id and request_id=p_request_id and action='record_payment') then select * into payment from public.sd_payments where id=(select target_id from public.sd_financial_audit_logs where org_id=p_org_id and request_id=p_request_id and action='record_payment'); return pg_catalog.jsonb_build_object('payment',pg_catalog.to_jsonb(payment),'replayed',true); end if;
  insert into public.sd_payments(org_id,payer_id,provider,amount_cents,currency,status,payment_method_type,paid_at,financial_layer,customer_account_id,recorded_by,received_at,external_reference,unapplied_cents,net_to_organization_cents)
    select p_org_id,a.responsible_user_id,'manual',p_amount_cents,pg_catalog.lower(p_currency),'succeeded',p_method,pg_catalog.now(),'organization_customer',a.id,p_actor_id,pg_catalog.now(),p_external_reference,p_amount_cents,p_amount_cents from public.sd_customer_accounts a where a.id=p_customer_account_id and a.org_id=p_org_id returning * into payment;
  if payment.id is null then raise exception using errcode='P0002',message='customer_account_not_found'; end if;
  for allocation in select value from pg_catalog.jsonb_array_elements(p_allocations) loop
    item_amount:=(allocation->>'amount_cents')::integer;
    select * into invoice from public.sd_invoices where id=(allocation->>'invoice_id')::uuid and org_id=p_org_id and financial_layer='organization_customer' for update;
    if invoice.id is null or item_amount<=0 or item_amount>invoice.amount_remaining_cents or allocated+item_amount>p_amount_cents then raise exception using errcode='22023',message='invalid_payment_allocation'; end if;
    insert into public.sd_payment_applications(org_id,payment_id,invoice_id,amount_cents,applied_by) values(p_org_id,payment.id,invoice.id,item_amount,p_actor_id);
    update public.sd_invoices set amount_paid_cents=amount_paid_cents+item_amount,amount_remaining_cents=amount_remaining_cents-item_amount,status=case when amount_remaining_cents-item_amount=0 then 'paid' else 'partially_paid' end,paid_at=case when amount_remaining_cents-item_amount=0 then pg_catalog.now() else paid_at end,version=version+1 where id=invoice.id;
    if invoice.registration_application_id is not null then update public.sd_registration_applications set balance_cents=pg_catalog.greatest(balance_cents-item_amount,0),fee_status=case when pg_catalog.greatest(balance_cents-item_amount,0)=0 then 'paid' else 'partial' end,version=version+1,updated_at=pg_catalog.now() where id=invoice.registration_application_id and organization_id=p_org_id; end if;
    allocated:=allocated+item_amount;
  end loop;
  update public.sd_payments set unapplied_cents=p_amount_cents-allocated where id=payment.id returning * into payment;
  insert into public.sd_financial_audit_logs(org_id,actor_id,action,target_type,target_id,request_id,amount_cents,details) values(p_org_id,p_actor_id,'record_payment','payment',payment.id,p_request_id,p_amount_cents,pg_catalog.jsonb_build_object('allocated_cents',allocated,'method',p_method));
  insert into public.sd_financial_notification_intents(org_id,customer_account_id,payment_id,intent_type,deduplication_key,payload,created_by) values(p_org_id,p_customer_account_id,payment.id,'payment_received',p_request_id::text||':payment_received',pg_catalog.jsonb_build_object('amount_cents',p_amount_cents),p_actor_id);
  return pg_catalog.jsonb_build_object('payment',pg_catalog.to_jsonb(payment),'allocated_cents',allocated,'replayed',false);
end $$;

create or replace function public.sd_change_invoice_state(p_org_id uuid,p_actor_id uuid,p_invoice_id uuid,p_action text,p_expected_version integer,p_request_id uuid,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare invoice public.sd_invoices%rowtype; next_status text; intent_type text;
begin
  if not exists(select 1 from public.sd_org_memberships where org_id=p_org_id and user_id=p_actor_id and status='active' and role in ('owner','admin')) then raise exception using errcode='42501',message='manage_invoice_required'; end if;
  if exists(select 1 from public.sd_financial_audit_logs where org_id=p_org_id and request_id=p_request_id and action=p_action||'_invoice') then select * into invoice from public.sd_invoices where id=p_invoice_id and org_id=p_org_id; return pg_catalog.jsonb_build_object('invoice',pg_catalog.to_jsonb(invoice),'replayed',true); end if;
  select * into invoice from public.sd_invoices where id=p_invoice_id and org_id=p_org_id and financial_layer='organization_customer' for update;
  if invoice.id is null or invoice.version<>p_expected_version then raise exception using errcode='P0001',message='stale_invoice'; end if;
  next_status:=case p_action when 'issue' then 'issued' when 'void' then 'void' when 'cancel' then 'cancelled' when 'write_off' then 'written_off' else null end;
  if next_status is null or (p_action='issue' and invoice.status<>'draft') or (p_action<>'issue' and invoice.status not in ('issued','partially_paid','overdue')) then raise exception using errcode='P0001',message='invalid_invoice_transition'; end if;
  if p_action in ('void','cancel','write_off') and pg_catalog.btrim(pg_catalog.coalesce(p_reason,''))='' then raise exception using errcode='22023',message='financial_reason_required'; end if;
  update public.sd_invoices set status=next_status,issue_date=case when p_action='issue' then pg_catalog.current_date else issue_date end,sent_at=case when p_action='issue' then pg_catalog.now() else sent_at end,voided_at=case when p_action='void' then pg_catalog.now() else voided_at end,cancelled_at=case when p_action='cancel' then pg_catalog.now() else cancelled_at end,written_off_at=case when p_action='write_off' then pg_catalog.now() else written_off_at end,written_off_cents=case when p_action='write_off' then amount_remaining_cents else written_off_cents end,amount_remaining_cents=case when p_action='write_off' then 0 else amount_remaining_cents end,version=version+1 where id=invoice.id returning * into invoice;
  insert into public.sd_financial_audit_logs(org_id,actor_id,action,target_type,target_id,request_id,amount_cents,details) values(p_org_id,p_actor_id,p_action||'_invoice','invoice',invoice.id,p_request_id,invoice.total_cents,pg_catalog.jsonb_build_object('reason',p_reason));
  if p_action='issue' then insert into public.sd_financial_notification_intents(org_id,customer_account_id,invoice_id,intent_type,deduplication_key,payload,created_by) values(p_org_id,invoice.customer_account_id,invoice.id,'invoice_issued',p_request_id::text||':invoice_issued',pg_catalog.jsonb_build_object('balance_cents',invoice.amount_remaining_cents,'due_date',invoice.due_date),p_actor_id); end if;
  return pg_catalog.jsonb_build_object('invoice',pg_catalog.to_jsonb(invoice));
end $$;

create or replace function public.sd_issue_financial_adjustment(p_org_id uuid,p_actor_id uuid,p_action text,p_target_id uuid,p_amount_cents integer,p_reason text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare payment public.sd_payments%rowtype; refund public.sd_refunds%rowtype; credit public.sd_account_credits%rowtype; account public.sd_customer_accounts%rowtype; already_adjusted integer:=0; adjustment_status text;
begin
  if not exists(select 1 from public.sd_org_memberships where org_id=p_org_id and user_id=p_actor_id and status='active' and role in ('owner','admin')) then raise exception using errcode='42501',message='financial_adjustment_required'; end if;
  if p_amount_cents<=0 or pg_catalog.btrim(pg_catalog.coalesce(p_reason,''))='' then raise exception using errcode='22023',message='financial_reason_and_amount_required'; end if;
  if exists(select 1 from public.sd_financial_audit_logs where org_id=p_org_id and request_id=p_request_id and action=p_action) then return pg_catalog.jsonb_build_object('replayed',true,'target_id',(select target_id from public.sd_financial_audit_logs where org_id=p_org_id and request_id=p_request_id and action=p_action)); end if;
  if p_action='issue_refund' then
    select * into payment from public.sd_payments where id=p_target_id and org_id=p_org_id and financial_layer='organization_customer' and status in ('succeeded','paid') for update;
    if payment.id is null then raise exception using errcode='P0002',message='payment_not_found'; end if;
    select pg_catalog.coalesce(sum(amount_cents),0) into already_adjusted from public.sd_refunds where payment_id=payment.id and status in ('pending','confirmed','succeeded');
    if already_adjusted+p_amount_cents>payment.amount_cents then raise exception using errcode='22023',message='refund_exceeds_payment'; end if;
    adjustment_status:=case when payment.provider='manual' then 'confirmed' else 'pending' end;
    insert into public.sd_refunds(org_id,payment_id,amount_cents,status,reason,requested_by,financial_layer,confirmed_at) values(p_org_id,payment.id,p_amount_cents,adjustment_status,p_reason,p_actor_id,'organization_customer',case when adjustment_status='confirmed' then pg_catalog.now() else null end) returning * into refund;
    if adjustment_status='confirmed' then insert into public.sd_financial_notification_intents(org_id,customer_account_id,payment_id,refund_id,intent_type,deduplication_key,payload,created_by) values(p_org_id,payment.customer_account_id,payment.id,refund.id,'refund_issued',p_request_id::text||':refund',pg_catalog.jsonb_build_object('amount_cents',p_amount_cents),p_actor_id); end if;
    insert into public.sd_financial_audit_logs(org_id,actor_id,action,target_type,target_id,request_id,amount_cents,details) values(p_org_id,p_actor_id,p_action,'refund',refund.id,p_request_id,p_amount_cents,pg_catalog.jsonb_build_object('reason',p_reason,'provider_confirmation_required',adjustment_status='pending'));
    return pg_catalog.jsonb_build_object('refund',pg_catalog.to_jsonb(refund),'provider_invoked',false,'provider_confirmation_required',adjustment_status='pending');
  elsif p_action='issue_credit' then
    select * into account from public.sd_customer_accounts where id=p_target_id and org_id=p_org_id for update;
    if account.id is null then raise exception using errcode='P0002',message='customer_account_not_found'; end if;
    insert into public.sd_account_credits(org_id,customer_account_id,amount_cents,remaining_cents,reason,created_by) values(p_org_id,account.id,p_amount_cents,p_amount_cents,p_reason,p_actor_id) returning * into credit;
    update public.sd_customer_accounts set credit_balance_cents=credit_balance_cents+p_amount_cents,version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=account.id;
    insert into public.sd_financial_notification_intents(org_id,customer_account_id,intent_type,deduplication_key,payload,created_by) values(p_org_id,account.id,'credit_issued',p_request_id::text||':credit',pg_catalog.jsonb_build_object('amount_cents',p_amount_cents),p_actor_id);
    insert into public.sd_financial_audit_logs(org_id,actor_id,action,target_type,target_id,request_id,amount_cents,details) values(p_org_id,p_actor_id,p_action,'account_credit',credit.id,p_request_id,p_amount_cents,pg_catalog.jsonb_build_object('reason',p_reason));
    return pg_catalog.jsonb_build_object('credit',pg_catalog.to_jsonb(credit),'provider_invoked',false);
  else raise exception using errcode='22023',message='invalid_financial_adjustment'; end if;
end $$;

create or replace function public.sd_approve_expense(p_org_id uuid,p_actor_id uuid,p_expense_id uuid,p_expected_version integer,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare expense public.sd_expenses%rowtype;
begin
  if not exists(select 1 from public.sd_org_memberships where org_id=p_org_id and user_id=p_actor_id and status='active' and role in ('owner','admin')) then raise exception using errcode='42501',message='approve_expense_required'; end if;
  select * into expense from public.sd_expenses where id=p_expense_id and org_id=p_org_id for update;
  if expense.id is null or expense.version<>p_expected_version then raise exception using errcode='P0001',message='stale_expense'; end if;
  update public.sd_expenses set approved_by=p_actor_id,approved_at=pg_catalog.now(),reimbursement_status=case when reimbursable then 'approved' else reimbursement_status end,version=version+1,updated_at=pg_catalog.now() where id=expense.id returning * into expense;
  insert into public.sd_financial_audit_logs(org_id,actor_id,action,target_type,target_id,request_id,amount_cents) values(p_org_id,p_actor_id,'approve_expense','expense',expense.id,p_request_id,expense.amount_cents);
  return pg_catalog.to_jsonb(expense);
end $$;

create or replace function public.sd_generate_financial_reminder_intents(p_org_id uuid,p_actor_id uuid,p_as_of date default pg_catalog.current_date,p_dry_run boolean default true) returns jsonb language plpgsql security definer set search_path='' as $$
declare policy public.sd_financial_reminder_policies%rowtype; invoice record; generated integer:=0; reminder_type text; day_delta integer;
begin
  if not exists(select 1 from public.sd_org_memberships where org_id=p_org_id and user_id=p_actor_id and status='active' and role in ('owner','admin')) then raise exception using errcode='42501',message='manage_notification_delivery_required'; end if;
  select * into policy from public.sd_financial_reminder_policies where org_id=p_org_id;
  if pg_catalog.coalesce(policy.paused,false) then return pg_catalog.jsonb_build_object('dry_run',p_dry_run,'generated_count',0,'paused',true); end if;
  for invoice in select i.* from public.sd_invoices i where i.org_id=p_org_id and i.financial_layer='organization_customer' and i.status in ('issued','partially_paid','overdue') and i.amount_remaining_cents>0 and i.due_date is not null loop
    day_delta:=invoice.due_date-p_as_of;
    reminder_type:=case when day_delta>0 and day_delta=any(pg_catalog.coalesce(policy.days_before_due,'{7,1}')) then 'upcoming_due' when day_delta=0 and pg_catalog.coalesce(policy.remind_on_due_date,true) then 'payment_due' when day_delta<0 and -day_delta=any(pg_catalog.coalesce(policy.days_after_due,'{1,7,14}')) then 'invoice_overdue' else null end;
    if reminder_type is not null and (select pg_catalog.count(*) from public.sd_financial_notification_intents n where n.invoice_id=invoice.id and n.intent_type in ('upcoming_due','payment_due','invoice_overdue'))<pg_catalog.coalesce(policy.maximum_reminders,6) then
      generated:=generated+1;
      if not p_dry_run then
        insert into public.sd_financial_notification_intents(org_id,customer_account_id,invoice_id,intent_type,deduplication_key,payload,created_by) values(p_org_id,invoice.customer_account_id,invoice.id,reminder_type,invoice.id::text||':'||reminder_type||':'||p_as_of::text,pg_catalog.jsonb_build_object('invoice_id',invoice.id,'balance_cents',invoice.amount_remaining_cents,'due_date',invoice.due_date),p_actor_id) on conflict do nothing;
        if reminder_type='invoice_overdue' and invoice.status<>'overdue' then update public.sd_invoices set status='overdue',version=version+1,updated_at=pg_catalog.now() where id=invoice.id; end if;
      end if;
    end if;
  end loop;
  return pg_catalog.jsonb_build_object('dry_run',p_dry_run,'generated_count',generated,'as_of',p_as_of,'paused',false);
end $$;

revoke all on function public.sd_record_manual_payment(uuid,uuid,uuid,integer,text,text,text,jsonb,uuid),public.sd_change_invoice_state(uuid,uuid,uuid,text,integer,uuid,text),public.sd_issue_financial_adjustment(uuid,uuid,text,uuid,integer,text,uuid),public.sd_approve_expense(uuid,uuid,uuid,integer,uuid),public.sd_generate_financial_reminder_intents(uuid,uuid,date,boolean) from public,anon,authenticated;
grant execute on function public.sd_record_manual_payment(uuid,uuid,uuid,integer,text,text,text,jsonb,uuid),public.sd_change_invoice_state(uuid,uuid,uuid,text,integer,uuid,text),public.sd_issue_financial_adjustment(uuid,uuid,text,uuid,integer,text,uuid),public.sd_approve_expense(uuid,uuid,uuid,integer,uuid),public.sd_generate_financial_reminder_intents(uuid,uuid,date,boolean) to service_role;
