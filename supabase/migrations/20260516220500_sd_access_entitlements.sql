-- Access entitlement table for "web purchase + iOS sign-in only" flow.
-- The iOS app never initiates payments; it only checks whether the signed-in user has access.

create table if not exists public.sd_access_entitlements (
  user_id uuid primary key references auth.users(id) on delete cascade,
  is_active boolean not null default false,
  source text not null default 'manual',
  stripe_customer_id text,
  stripe_subscription_id text,
  current_period_end timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.sd_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists sd_access_entitlements_touch on public.sd_access_entitlements;
create trigger sd_access_entitlements_touch
before update on public.sd_access_entitlements
for each row execute function public.sd_touch_updated_at();

alter table public.sd_access_entitlements enable row level security;

-- Player can view their own access row.
drop policy if exists "sd_access_entitlements_select_own" on public.sd_access_entitlements;
create policy "sd_access_entitlements_select_own"
on public.sd_access_entitlements
for select
to authenticated
using (auth.uid() = user_id);

-- Only service role / server jobs should insert/update entitlements.
-- (Coaches can be granted an admin UI later via an RPC; not from client writes.)

