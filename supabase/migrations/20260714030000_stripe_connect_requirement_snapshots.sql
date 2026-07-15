-- Stripe Connect requirement snapshot completion.
--
-- Rollback: ALTER TABLE public.sd_connected_payment_accounts
--   DROP COLUMN IF EXISTS requirements_past_due;
-- The change is additive, preserves all existing rows and policies, and stores
-- only Stripe requirement field names (never identity documents or bank data).

alter table public.sd_connected_payment_accounts
  add column if not exists requirements_past_due jsonb not null default '[]'::jsonb;
