# Home Plate billing Edge Functions

Required Supabase Edge Function secrets (test mode only for this phase):

- `STRIPE_SECRET_KEY` — Stripe test secret key (`sk_test_...`)
- `STRIPE_PLATFORM_WEBHOOK_SECRET` — signing secret for `stripe-platform-webhook` (`whsec_...`)
- `STRIPE_ORG_MONTHLY_PRICE_ID` — server-owned $200/month Stripe test Price ID
- `HOME_PLATE_BILLING_SUCCESS_URL` — Checkout success URL
- `HOME_PLATE_BILLING_CANCEL_URL` — Checkout cancel URL
- `HOME_PLATE_BILLING_PORTAL_RETURN_URL` — Customer Portal return URL

Also required by the functions: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY`.

Never put Stripe secrets in Swift, Info.plist, or xcconfig files. Stripe REST requests are pinned to API version `2025-06-30.basil` in `_shared/stripe.ts`.
