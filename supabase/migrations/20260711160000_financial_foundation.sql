-- Home Plate financial foundation.
--
-- This additive migration creates organization-scoped billing, invoice, payment,
-- refund, webhook, and expense records. It does not migrate existing payment
-- requests or entitlements, and it does not call Stripe or Apple.
--
-- Rollback strategy: drop the tables in reverse dependency order:
-- sd_expenses, sd_webhook_events, sd_refunds, sd_payments, sd_invoice_items,
-- sd_invoices, sd_connected_payment_accounts, sd_player_subscriptions,
-- sd_org_subscriptions, sd_org_billing_accounts; then drop the policies,
-- triggers, indexes, and sd_is_platform_admin_finance helper created here.

create extension if not exists pgcrypto;

-- Security-definer helper keeps platform support authorization consistent and
-- avoids exposing the platform-admin table to ordinary application users.
create or replace function public.sd_is_platform_admin_finance()
returns boolean
language sql
stable
security definer
set search_path to 'public', 'auth'
as $$
  select exists (
    select 1
    from public.sd_platform_admins a
    where a.user_id = auth.uid()
  );
$$;

-- Stripe customer relation for an organization paying Home Plate's software fee.
create table if not exists public.sd_org_billing_accounts (
  org_id uuid primary key references public.sd_orgs(id) on delete cascade,
  provider text not null default 'stripe',
  provider_customer_id text unique,
  billing_email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.sd_org_billing_accounts is 'Provider customer identity for an organization paying Home Plate.';

-- Home Plate software subscriptions owned by an organization.
create table if not exists public.sd_org_subscriptions (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  provider text not null default 'stripe',
  provider_subscription_id text unique,
  provider_product_id text,
  provider_price_id text,
  status text not null,
  current_period_start timestamptz,
  current_period_end timestamptz,
  cancel_at_period_end boolean not null default false,
  canceled_at timestamptz,
  grace_period_ends_at timestamptz,
  provider_state jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.sd_org_subscriptions is 'Organization software subscription state from a billing provider.';

-- Player subscriptions, initially supporting Apple IAP while remaining provider-neutral.
create table if not exists public.sd_player_subscriptions (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  player_id uuid not null references public.profiles(id) on delete cascade,
  billing_user_id uuid references public.profiles(id) on delete set null,
  provider text not null,
  provider_customer_id text,
  provider_subscription_id text,
  provider_transaction_id text,
  original_transaction_id text,
  provider_product_id text,
  status text not null,
  current_period_start timestamptz,
  current_period_end timestamptz,
  cancel_at_period_end boolean not null default false,
  environment text,
  provider_state jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.sd_player_subscriptions is 'Per-player subscription history and current provider state.';

-- Stripe Connect account an organization uses to collect its own customer payments.
create table if not exists public.sd_connected_payment_accounts (
  org_id uuid primary key references public.sd_orgs(id) on delete cascade,
  provider text not null default 'stripe',
  provider_account_id text unique,
  onboarding_status text not null default 'not_started',
  details_submitted boolean not null default false,
  charges_enabled boolean not null default false,
  payouts_enabled boolean not null default false,
  disabled_reason text,
  requirements_currently_due jsonb not null default '[]'::jsonb,
  requirements_eventually_due jsonb not null default '[]'::jsonb,
  default_currency text,
  country text,
  last_synced_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.sd_connected_payment_accounts is 'Organization-owned connected payment account state.';

-- Invoice header created by organization staff for a payer, child, team, or booking.
create table if not exists public.sd_invoices (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  payer_id uuid references public.profiles(id) on delete set null,
  child_id uuid references public.profiles(id) on delete set null,
  created_by uuid not null references public.profiles(id) on delete restrict,
  payment_request_id uuid references public.sd_payment_requests(id) on delete set null,
  team_id uuid references public.sd_teams(id) on delete set null,
  booking_id uuid references public.sd_facility_bookings(id) on delete set null,
  status text not null,
  collection_method text,
  currency text not null default 'usd',
  subtotal_cents integer not null default 0 check (subtotal_cents >= 0),
  discount_cents integer not null default 0 check (discount_cents >= 0),
  tax_cents integer not null default 0 check (tax_cents >= 0),
  total_cents integer not null default 0 check (total_cents >= 0),
  amount_paid_cents integer not null default 0 check (amount_paid_cents >= 0),
  amount_remaining_cents integer not null default 0 check (amount_remaining_cents >= 0),
  due_date date,
  provider_invoice_id text,
  hosted_invoice_url text,
  invoice_pdf_url text,
  sent_at timestamptz,
  paid_at timestamptz,
  voided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.sd_invoices is 'Organization invoice headers for family, team, booking, or other charges.';

-- Line items displayed on an invoice.
create table if not exists public.sd_invoice_items (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  invoice_id uuid not null references public.sd_invoices(id) on delete cascade,
  item_type text,
  description text not null,
  quantity integer not null default 1 check (quantity > 0),
  unit_amount_cents integer not null,
  total_amount_cents integer not null,
  taxable boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.sd_invoice_items is 'Line-item charges belonging to an organization invoice.';

-- Provider payment attempts and completed payments against invoices.
create table if not exists public.sd_payments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  invoice_id uuid references public.sd_invoices(id) on delete set null,
  payer_id uuid references public.profiles(id) on delete set null,
  provider text not null,
  connected_account_id text,
  provider_payment_intent_id text,
  provider_charge_id text,
  amount_cents integer not null check (amount_cents >= 0),
  currency text not null default 'usd',
  status text not null,
  payment_method_type text,
  processing_fee_cents integer,
  platform_fee_cents integer,
  net_to_organization_cents integer,
  failure_code text,
  failure_message text,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.sd_payments is 'Provider payment records toward organization invoices.';

-- Full or partial refunds for recorded payments.
create table if not exists public.sd_refunds (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  payment_id uuid not null references public.sd_payments(id) on delete restrict,
  provider_refund_id text unique,
  amount_cents integer not null check (amount_cents > 0),
  status text not null,
  reason text,
  requested_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.sd_refunds is 'Provider refund records for organization payments.';

-- Idempotency ledger for Stripe and Apple server/webhook events.
create table if not exists public.sd_webhook_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_account_id text,
  provider_event_id text not null,
  event_type text not null,
  processing_status text not null,
  payload jsonb not null default '{}'::jsonb,
  attempt_count integer not null default 0 check (attempt_count >= 0),
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  error_message text
);
comment on table public.sd_webhook_events is 'Idempotency and processing ledger for verified provider webhooks.';

-- Organization operating expenses and receipt storage references.
create table if not exists public.sd_expenses (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  created_by uuid not null references public.profiles(id) on delete restrict,
  vendor text,
  category text,
  description text,
  amount_cents integer not null check (amount_cents >= 0),
  currency text not null default 'usd',
  expense_date date not null,
  payment_method text,
  receipt_path text,
  reimbursable boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.sd_expenses is 'Organization business expenses and receipt storage references.';

-- Prevent duplicate current subscriptions without preventing historical records.
create unique index if not exists ux_sd_player_subscriptions_current
  on public.sd_player_subscriptions(org_id, player_id)
  where status in ('active', 'trialing', 'grace', 'past_due');

-- Provider id lookup and organization/reporting indexes.
create index if not exists idx_sd_org_subscriptions_org_status on public.sd_org_subscriptions(org_id, status);
create index if not exists idx_sd_org_subscriptions_provider_subscription on public.sd_org_subscriptions(provider_subscription_id);
create index if not exists idx_sd_player_subscriptions_org_player on public.sd_player_subscriptions(org_id, player_id);
create index if not exists idx_sd_player_subscriptions_billing_user on public.sd_player_subscriptions(billing_user_id);
create index if not exists idx_sd_player_subscriptions_status on public.sd_player_subscriptions(status, current_period_end);
create index if not exists idx_sd_player_subscriptions_provider_subscription on public.sd_player_subscriptions(provider_subscription_id);
create index if not exists idx_sd_connected_payment_accounts_provider_account on public.sd_connected_payment_accounts(provider_account_id);
create index if not exists idx_sd_invoices_org_status_due on public.sd_invoices(org_id, status, due_date);
create index if not exists idx_sd_invoices_payer on public.sd_invoices(payer_id, created_at desc);
create index if not exists idx_sd_invoices_child on public.sd_invoices(child_id, created_at desc);
create index if not exists idx_sd_invoices_provider_invoice on public.sd_invoices(provider_invoice_id);
create index if not exists idx_sd_invoice_items_org_invoice on public.sd_invoice_items(org_id, invoice_id);
create index if not exists idx_sd_payments_org_status on public.sd_payments(org_id, status, created_at desc);
create index if not exists idx_sd_payments_invoice on public.sd_payments(invoice_id);
create index if not exists idx_sd_payments_payer on public.sd_payments(payer_id, created_at desc);
create index if not exists idx_sd_payments_provider_intent on public.sd_payments(provider_payment_intent_id);
create index if not exists idx_sd_payments_provider_charge on public.sd_payments(provider_charge_id);
create index if not exists idx_sd_refunds_org_payment on public.sd_refunds(org_id, payment_id);
create unique index if not exists ux_sd_webhook_events_provider_event_account
  on public.sd_webhook_events(provider, coalesce(provider_account_id, ''), provider_event_id);
create index if not exists idx_sd_webhook_events_processing on public.sd_webhook_events(processing_status, received_at);
create index if not exists idx_sd_expenses_org_date on public.sd_expenses(org_id, expense_date desc);

-- Reuse the established timestamp trigger convention.
create trigger trg_sd_org_billing_accounts_updated_at before update on public.sd_org_billing_accounts for each row execute function public.sd_set_updated_at();
create trigger trg_sd_org_subscriptions_updated_at before update on public.sd_org_subscriptions for each row execute function public.sd_set_updated_at();
create trigger trg_sd_player_subscriptions_updated_at before update on public.sd_player_subscriptions for each row execute function public.sd_set_updated_at();
create trigger trg_sd_connected_payment_accounts_updated_at before update on public.sd_connected_payment_accounts for each row execute function public.sd_set_updated_at();
create trigger trg_sd_invoices_updated_at before update on public.sd_invoices for each row execute function public.sd_set_updated_at();
create trigger trg_sd_invoice_items_updated_at before update on public.sd_invoice_items for each row execute function public.sd_set_updated_at();
create trigger trg_sd_payments_updated_at before update on public.sd_payments for each row execute function public.sd_set_updated_at();
create trigger trg_sd_refunds_updated_at before update on public.sd_refunds for each row execute function public.sd_set_updated_at();
create trigger trg_sd_expenses_updated_at before update on public.sd_expenses for each row execute function public.sd_set_updated_at();

alter table public.sd_org_billing_accounts enable row level security;
alter table public.sd_org_subscriptions enable row level security;
alter table public.sd_player_subscriptions enable row level security;
alter table public.sd_connected_payment_accounts enable row level security;
alter table public.sd_invoices enable row level security;
alter table public.sd_invoice_items enable row level security;
alter table public.sd_payments enable row level security;
alter table public.sd_refunds enable row level security;
alter table public.sd_webhook_events enable row level security;
alter table public.sd_expenses enable row level security;

-- Provider-controlled account/subscription state is visible to org staff and
-- platform support, while writes remain service-role/webhook-only.
create policy "sd_org_billing_accounts_select_finance" on public.sd_org_billing_accounts for select to authenticated
  using (public.sd_is_org_staff(org_id) or public.sd_is_platform_admin_finance());
create policy "sd_org_subscriptions_select_finance" on public.sd_org_subscriptions for select to authenticated
  using (public.sd_is_org_staff(org_id) or public.sd_is_platform_admin_finance());
create policy "sd_player_subscriptions_select_finance" on public.sd_player_subscriptions for select to authenticated
  using (
    public.sd_is_org_staff(org_id)
    or public.sd_is_platform_admin_finance()
    or player_id = auth.uid()
    or billing_user_id = auth.uid()
    or public.sd_is_linked_parent(auth.uid(), player_id)
  );
create policy "sd_connected_payment_accounts_select_finance" on public.sd_connected_payment_accounts for select to authenticated
  using (public.sd_is_org_staff(org_id) or public.sd_is_platform_admin_finance());

-- Staff create and manage invoices/items/expenses within their own organization.
create policy "sd_invoices_select_finance" on public.sd_invoices for select to authenticated
  using (
    public.sd_is_org_staff(org_id)
    or public.sd_is_platform_admin_finance()
    or payer_id = auth.uid()
    or public.sd_is_linked_parent(auth.uid(), child_id)
  );
create policy "sd_invoices_write_staff" on public.sd_invoices for all to authenticated
  using (public.sd_is_org_staff(org_id) or public.sd_is_platform_admin_finance())
  with check (public.sd_is_org_staff(org_id) or public.sd_is_platform_admin_finance());
create policy "sd_invoice_items_select_finance" on public.sd_invoice_items for select to authenticated
  using (
    public.sd_is_org_staff(org_id)
    or public.sd_is_platform_admin_finance()
    or exists (
      select 1 from public.sd_invoices i
      where i.id = invoice_id
        and (i.payer_id = auth.uid() or public.sd_is_linked_parent(auth.uid(), i.child_id))
    )
  );
create policy "sd_invoice_items_write_staff" on public.sd_invoice_items for all to authenticated
  using (public.sd_is_org_staff(org_id) or public.sd_is_platform_admin_finance())
  with check (public.sd_is_org_staff(org_id) or public.sd_is_platform_admin_finance());
create policy "sd_expenses_select_staff" on public.sd_expenses for select to authenticated
  using (public.sd_is_org_staff(org_id) or public.sd_is_platform_admin_finance());
create policy "sd_expenses_write_staff" on public.sd_expenses for all to authenticated
  using (public.sd_is_org_staff(org_id) or public.sd_is_platform_admin_finance())
  with check (public.sd_is_org_staff(org_id) or public.sd_is_platform_admin_finance());

-- Payers/linked parents can read payment results. Provider mutations are only
-- performed by service-role Edge Functions or verified webhook handlers.
create policy "sd_payments_select_finance" on public.sd_payments for select to authenticated
  using (
    public.sd_is_org_staff(org_id)
    or public.sd_is_platform_admin_finance()
    or payer_id = auth.uid()
    or exists (
      select 1 from public.sd_invoices i
      where i.id = invoice_id and public.sd_is_linked_parent(auth.uid(), i.child_id)
    )
  );
create policy "sd_refunds_select_finance" on public.sd_refunds for select to authenticated
  using (
    public.sd_is_org_staff(org_id)
    or public.sd_is_platform_admin_finance()
    or exists (
      select 1 from public.sd_payments p
      left join public.sd_invoices i on i.id = p.invoice_id
      where p.id = payment_id
        and (p.payer_id = auth.uid() or public.sd_is_linked_parent(auth.uid(), i.child_id))
    )
  );

-- No authenticated-user policy is created for webhook events. Service-role
-- functions bypass RLS and are the only intended writers/readers.
