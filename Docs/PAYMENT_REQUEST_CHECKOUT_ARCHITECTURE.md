# Payment-request Checkout architecture

Status: local implementation foundation; not deployed or configured.

## Domain boundary

An `sd_payment_requests` row is Home Plate's organization-scoped instruction
that one player owes one amount. It is not proof of a Stripe payment. Creating
or canceling a request remains an organization-management action. Opening
Checkout is a payer action. Marking a request paid is a verified-provider
webhook action.

Organization SaaS subscriptions, Apple player-access subscriptions, and Stripe
Connect onboarding remain separate systems and are not changed by this flow.

## Payer authorization

The authenticated actor is resolved with `auth.getUser()` from the Supabase JWT.
The Checkout client sends only `payment_request_id`.

A player may pay only when the request child is that actor and the actor has an
active `player` membership in the request organization. A parent may pay only
when the actor has an active `parent` membership in that organization and an
organization-scoped parent-child link to the request child has `can_pay = true`.
The child must still have an active player membership.

Coach, owner, organization-admin, platform-admin, inactive, unrelated, and
cross-organization identities are denied unless the same authenticated user
separately qualifies under the player or linked-parent rule. Platform-support
request management never broadens payer or Stripe Connect management authority.

## Connected-account charge model

Customer payments use connected-account direct charges. The Checkout Session is
created with the organization account in Stripe's `Stripe-Account` request
context. The organization is therefore the direct connected-account recipient.
No transfer destination is accepted from a client, and the organization SaaS
Stripe customer/subscription is not read or changed.

Customer-payment readiness requires the request organization's authoritative
`sd_connected_payment_accounts` row to be Stripe-backed with:

- `onboarding_status = ready`
- a non-null `provider_account_id`
- details, charges, and payouts enabled
- no disabled reason
- no blocking past-due requirements (current requirements may be future-due,
  matching the existing Connect readiness mapper)

## Server fee policy

`HOME_PLATE_PAYMENT_PLATFORM_FEE_BPS` is a server-only integer configuration in
the range 0 through 1,000 basis points. It defaults to `0`. The fee is calculated
from the authoritative request amount in the preparation RPC and snapshotted on
the Checkout attempt with policy version `home_plate_fee_bps_v1:<bps>`.

At the zero default, `payment_intent_data[application_fee_amount]` is omitted.
The client cannot send or override a fee. Enabling a nonzero fee requires an
explicit product/finance decision and compatible Stripe connected-account terms.

## Checkout attempt lifecycle

`sd_payment_checkout_sessions` stores one attempt at a time for each payment
request:

`creating -> open -> complete`

`creating/open -> expired` and `creating -> failed` are terminal attempt paths.
`anomaly` retains evidence for a payment that conflicts with internal state.

The preparation RPC locks only the internal request long enough to validate the
request, payer, organization, player, connected account, fee policy, and current
attempt. It reuses an unexpired `creating` or `open` attempt; otherwise it creates
a new attempt with a stable server-generated Stripe idempotency key and a
60-minute expiration.

The database transaction ends before Stripe is called. The Edge Function calls
Stripe with that stable key, then a second short RPC records the Checkout Session
ID and expiration. A network failure or Stripe 5xx has an ambiguous provider
outcome, so the attempt stays `creating`; the next call repeats the exact Stripe
operation with the same key. A definitive provider rejection marks the attempt
failed. A valid existing open Session is retrieved and reused.

A partial unique index permits only one `creating`/`open` attempt per request.
Stripe Session and PaymentIntent identifiers are unique. No client idempotency
key is accepted.

## Checkout contents and metadata

Checkout uses `mode=payment` and one line item. Title, bounded description,
amount, currency, organization name, and connected account all come from the
database. Success and cancel URLs come from server configuration.

Both Checkout Session and PaymentIntent metadata contain only bounded internal
identifiers:

- metadata schema version
- payment-request ID
- request-batch ID when present
- organization ID
- child/player ID
- authenticated payer actor ID
- internal Checkout-attempt ID

Unrestricted notes, player-development data, JWTs, payment methods, and secrets
are not written to metadata.

## Webhook authority and idempotency

`stripe-connected-payments-webhook` is public at the Supabase JWT layer because
Stripe does not send a Supabase JWT. It verifies `Stripe-Signature` against the
raw request body with the dedicated connected-payments webhook secret before
JSON parsing.

`sd_webhook_events` provides account-aware provider-event idempotency. Only a
small event summary is stored. Processed or concurrently processing duplicates
return successfully without repeating financial mutation. Failed internal
events may be reclaimed. A processing claim is a five-minute optimistic lease,
so a worker crash does not strand the event forever; attempt-count matching lets
only one retry reclaim a stale claim. Validation anomalies remain quarantined
with a bounded error code.

The initial event set is:

- `checkout.session.completed`
- `checkout.session.expired`
- `payment_intent.succeeded`
- `payment_intent.payment_failed`
- `charge.refunded` (recorded only; refund reconciliation is deferred)

An unpaid Checkout completion never marks a request paid. A paid Checkout
completion or successful PaymentIntent must include valid internal metadata and
must match the attempt's connected account, organization, request, child,
amount, currency, and provider identifiers.

## Successful-payment reconciliation

One service-role-only RPC locks the Checkout attempt and request, validates all
provider facts, inserts one succeeded `sd_payments` row linked by
`payment_request_id`, snapshots gross/platform/net amounts and connected-account
context, transitions the request from `open` to `paid`, sets `paid_at`, and marks
the attempt complete.

A partial unique payment index permits only one successful payment record per
request. Duplicate delivery of the same PaymentIntent returns the existing
payment. A second distinct success becomes an anomaly instead of a second
financial record. Later events cannot regress a paid request.

## Cancellation anomaly

Canceling an open request stops the native client from offering Pay Now and
prevents new Checkout creation. If Stripe later reports a real success from a
previously open Session, the request remains canceled. The attempt is marked
`anomaly`, no silent paid transition occurs, and the signed event remains in the
financial webhook ledger for manual review. Automatic refunds are deliberately
not implemented.

## Native client behavior

Player and parent request cards show organization, player context, title,
description, amount, due date, and backend status. `can_current_user_pay` controls
the payer action presentation, while the server independently reauthorizes every
Checkout creation.

Pay Now opens a confirmation sheet, disables repeat taps, calls the authenticated
Checkout function with only the request ID, and opens only the returned HTTPS
Stripe URL through the system browser. Returning to the foreground refreshes the
request list. The client shows processing while the request remains open and
shows paid only after the backend returns `status=paid`; redirects are never
treated as payment proof.

## Required server secrets/configuration

Do not put these values in the native application:

- `STRIPE_SECRET_KEY`
- `SUPABASE_URL` (or the established `DHD_SUPABASE_URL` fallback)
- `SUPABASE_ANON_KEY` (or the established fallback)
- `SUPABASE_SERVICE_ROLE_KEY` (or the established fallback)
- `HOME_PLATE_PAYMENT_SUCCESS_URL`
- `HOME_PLATE_PAYMENT_CANCEL_URL`
- `HOME_PLATE_PAYMENT_PLATFORM_FEE_BPS` (optional; defaults to `0`)
- `STRIPE_CONNECT_PAYMENTS_WEBHOOK_SECRET`

The success and cancel URLs must be HTTPS application return pages. They are
navigation only and must never assert payment completion.

## Deployment order (future operation)

1. Review live preflight data and apply migrations through
   `20260714200000_platform_payment_request_support.sql` if not already applied.
2. Apply `20260714210000_payment_request_checkout_foundation.sql`.
3. Configure Checkout URL/fee secrets and deploy
   `create-payment-request-checkout` with JWT verification enabled.
4. Configure the dedicated webhook signing secret and deploy
   `stripe-connected-payments-webhook` with Supabase JWT verification disabled.
5. In Stripe, create the connected-account event destination for the event set
   above and copy its signing secret to the dedicated server secret.
6. Deploy the native client after backend smoke tests pass.

No step is performed by this implementation task.

## Test checklist

- JWT and exact-input contract
- player/parent authorization and all denied roles
- active organization/player and connected-account readiness
- server-derived amount, currency, account, URLs, metadata, and fee
- concurrent/repeated/ambiguous Checkout retries
- signature verification and provider-event idempotency
- account/org/request/child/amount/currency reconciliation
- duplicate and out-of-order success
- canceled-request success anomaly
- payer UI, browser failure, foreground refresh, and backend-only paid display
- management, Stripe Connect, SaaS billing, and StoreKit regressions

## Explicit non-goals

This foundation does not implement custom card entry, saved payment methods,
ACH, taxes, subscriptions for organization customers, invoices redesign,
automatic collection, refunds UI or automation, disputes, payouts, finance
analytics, receipts beyond Stripe defaults, email/push notifications, StoreKit
changes, organization SaaS billing changes, or Stripe Connect onboarding changes.
