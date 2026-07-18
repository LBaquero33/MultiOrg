-- Phase 12 execution-level compatibility repairs.
--
-- The source migrations now contain these corrections for clean databases.
-- These guarded replacements update functions that were already installed on
-- the linked project before the source corrections were committed.

do $repair$
declare
  definition text;
begin
  select pg_catalog.pg_get_functiondef(
    'public.sd_mark_chat_conversation_read(uuid,uuid)'::pg_catalog.regprocedure
  ) into definition;

  if pg_catalog.strpos(definition, 'pg_catalog.greatest(') > 0 then
    execute pg_catalog.replace(
      definition,
      'pg_catalog.greatest(',
      'greatest('
    );
  elsif pg_catalog.strpos(definition, 'greatest(') = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'unexpected_sd_mark_chat_conversation_read_definition';
  end if;
end;
$repair$;

create or replace function public.sd_consume_organization_notification_intent(
  p_source_type text,
  p_source_id uuid,
  p_actor_id uuid,
  p_dry_run boolean default true
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  organization_id uuid;
  intent_type text;
  payload jsonb;
  v_deduplication_key text;
  application_id uuid;
  customer_account_id uuid;
  invoice_id uuid;
  recipient_id uuid;
  subject_id uuid;
  preference jsonb;
  v_category text;
  source_name text;
  route text;
  title text;
  body text;
  required boolean := false;
  notification_id uuid;
  delivered integer := 0;
  suppressed integer := 0;
begin
  if p_source_type = 'registration' then
    select
      intent.organization_id,
      intent.intent_type,
      intent.payload,
      intent.deduplication_key,
      intent.application_id
    into
      organization_id,
      intent_type,
      payload,
      v_deduplication_key,
      application_id
    from public.sd_registration_notification_intents intent
    where intent.id = p_source_id
      and intent.consumed_at is null
    for update;

    select
      coalesce(application.guardian_user_id, application.applicant_user_id),
      application.player_user_id
    into recipient_id, subject_id
    from public.sd_registration_applications application
    where application.id = application_id;

    v_category := case
      when intent_type = 'registration_balance_due' then 'payment_notice'
      else 'registration'
    end;
    source_name := 'registration';
    route := 'registration';
  elsif p_source_type = 'finance' then
    select
      intent.org_id,
      intent.intent_type,
      intent.payload,
      intent.deduplication_key,
      intent.customer_account_id,
      intent.invoice_id
    into
      organization_id,
      intent_type,
      payload,
      v_deduplication_key,
      customer_account_id,
      invoice_id
    from public.sd_financial_notification_intents intent
    where intent.id = p_source_id
      and intent.consumed_at is null
    for update;

    select
      coalesce(account.responsible_user_id, account.user_id),
      account_player.player_id
    into recipient_id, subject_id
    from public.sd_customer_accounts account
    left join lateral (
      select player.player_id
      from public.sd_customer_account_players player
      where player.account_id = account.id
      order by player.created_at
      limit 1
    ) account_player on true
    where account.id = customer_account_id;

    if recipient_id is null and invoice_id is not null then
      select invoice.payer_id, invoice.child_id
      into recipient_id, subject_id
      from public.sd_invoices invoice
      where invoice.id = invoice_id;
    end if;

    v_category := 'payment_notice';
    source_name := 'organization_finance';
    route := 'finance';
  else
    raise exception using
      errcode = '22023',
      message = 'invalid_notification_source';
  end if;

  if organization_id is null then
    raise exception using
      errcode = 'P0002',
      message = 'notification_intent_not_found';
  end if;
  if not exists (
    select 1
    from public.sd_org_memberships membership
    where membership.org_id = organization_id
      and membership.user_id = p_actor_id
      and membership.status = 'active'
      and membership.role in ('owner', 'admin')
  ) then
    raise exception using
      errcode = '42501',
      message = 'manage_notification_delivery_required';
  end if;
  if recipient_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'notification_recipient_missing';
  end if;

  required := intent_type in (
    'required_form_missing',
    'waiver_missing',
    'invoice_overdue'
  );
  title := pg_catalog.initcap(pg_catalog.replace(intent_type, '_', ' '));
  body := coalesce(
    nullif(payload->>'body', ''),
    'Open Home Plate for details.'
  );
  preference := public.sd_effective_notification_preference(
    recipient_id,
    organization_id,
    null,
    subject_id,
    case v_category
      when 'payment_notice' then 'payments'
      else 'registration'
    end,
    required
  );

  if not p_dry_run then
    if (preference->>'in_app')::boolean
      or (preference->>'push')::boolean then
      insert into public.sd_notifications(
        org_id,
        recipient_user_id,
        category,
        title,
        body,
        related_entity_type,
        related_entity_id,
        action_route,
        action_payload,
        deduplication_key,
        created_by,
        source,
        metadata,
        archived_at
      ) values (
        organization_id,
        recipient_id,
        v_category,
        title,
        body,
        p_source_type,
        p_source_id::text,
        route,
        payload,
        v_deduplication_key,
        p_actor_id,
        source_name,
        pg_catalog.jsonb_build_object(
          'intent_id', p_source_id,
          'push_suppressed', not ((preference->>'push')::boolean)
        ),
        case
          when (preference->>'in_app')::boolean then null
          else pg_catalog.now()
        end
      )
      on conflict (
        org_id,
        recipient_user_id,
        category,
        deduplication_key
      ) do update
      set metadata = excluded.metadata
      returning id into notification_id;
      delivered := 1;
    else
      suppressed := 1;
    end if;

    insert into public.sd_notification_intent_receipts(
      organization_id,
      source_type,
      source_id,
      recipient_user_id,
      category,
      delivery_state,
      preference_decision,
      notification_id,
      deep_link,
      delivered_at
    ) values (
      organization_id,
      p_source_type,
      p_source_id,
      recipient_id,
      v_category,
      case when delivered = 1 then 'delivered' else 'suppressed' end,
      case
        when delivered = 1 then 'deliver'
        else 'preference_suppressed'
      end,
      notification_id,
      pg_catalog.jsonb_build_object('route', route, 'payload', payload),
      case when delivered = 1 then pg_catalog.now() else null end
    ) on conflict do nothing;

    if p_source_type = 'registration' then
      update public.sd_registration_notification_intents
      set consumed_at = pg_catalog.now()
      where id = p_source_id;
    else
      update public.sd_financial_notification_intents
      set consumed_at = pg_catalog.now()
      where id = p_source_id;
    end if;
  end if;

  return pg_catalog.jsonb_build_object(
    'source_type', p_source_type,
    'source_id', p_source_id,
    'dry_run', p_dry_run,
    'recipient_count', 1,
    'delivered_count', delivered,
    'suppressed_count', suppressed
  );
end;
$$;

revoke all on function public.sd_consume_organization_notification_intent(
  text,
  uuid,
  uuid,
  boolean
) from public, anon, authenticated;
grant execute on function public.sd_consume_organization_notification_intent(
  text,
  uuid,
  uuid,
  boolean
) to service_role;
