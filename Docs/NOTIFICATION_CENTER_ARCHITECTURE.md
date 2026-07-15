# Notification Center Architecture (Phase 9A)

## Scope

Phase 9A adds an organization-scoped, recipient-owned in-app inbox. It does not add APNs, Firebase, email, SMS, device tokens, notification preferences, chat, campaigns, or universal links.

The fully connected producers are:

- `payment_request_created`
- `payment_received`
- `organization_announcement`

The category constraint also reserves booking, program, message, testing, and system categories for later producers.

## Core model

`public.sd_notifications` stores one immutable event projection for one recipient in one organization. Its public contract contains the notification ID, organization, category, bounded title/body, optional related entity, internal action route/payload, creation time, and read time. `source`, `metadata`, `created_by`, recipient identity, and archive state remain server-side.

`public.sd_notification_batches` is a server-only idempotency ledger for announcement fan-out. It binds one organization, actor, audience, authorization source, deterministic material fingerprint, initial recipient set, and idempotency key. The announcement body is not written to the audit log.

## Multi-tenant isolation and RLS

RLS is enabled on both tables. An authenticated user can select only rows where `recipient_user_id = auth.uid()`. The user can update only `read_at` and `archived_at` on their own rows. An update guard rejects changes to immutable content and prevents clearing a terminal read/archive timestamp.

Clients cannot insert notifications. Production functions use service-role credentials after verifying the JWT. All service-only `SECURITY DEFINER` functions set `search_path = ''`, schema-qualify security-sensitive objects, revoke execution from `public`, `anon`, and `authenticated`, and grant only `service_role`.

## Edge Function

`notification-center` has `verify_jwt = true` and independently verifies the bearer token with `auth.getUser()`. Its actions are:

- `list`: actor-owned, optionally organization-scoped and unread-only, archived excluded, newest first, bounded pagination.
- `unread_count`: total actor unread count and optional organization count.
- `mark_read`: sets the actor-owned row's `read_at` only when null; retries return the same row.
- `mark_all_read`: marks only the actor's rows, optionally within one organization.
- `create_announcement`: validates organization, audience, title/body, explicit support context, and idempotency; recipients are never accepted from the client.

Inbox requests never accept recipient IDs, actor IDs, ownership claims, read ownership, or platform-admin truth claims. Responses omit producer metadata and financial/provider secrets.

## Producers

### Reusable producer

`sd_create_notifications` is service-role-only. It validates an active organization, normalizes/deduplicates a bounded recipient list, confirms every recipient has an active membership in that organization, and inserts one row per recipient with deterministic conflict handling.

### Payment request created

An `AFTER INSERT` trigger on `sd_payment_requests` runs inside the payment-request batch transaction. It notifies:

- the active player whose membership user ID equals `child_id`;
- active linked parents who have request visibility in the same organization.

Parent `can_pay` is deliberately not required for notification visibility. Unrelated, inactive, and cross-organization parents are excluded. Each recipient's unique key is `payment_request_created:<request id>`, so batch/RPC retry cannot duplicate the event.

### Payment received

An `AFTER INSERT OR UPDATE OF status` trigger on `sd_payments` reacts only when an authoritative payment-request payment first reaches `succeeded`. It derives the successful payment/request and notifies the active player, active linked parents with request visibility, and active organization owners/admins. The unique key is `payment_received:<payment id>`.

Notification production never originates from the client or Checkout redirect. The signed connected-payment webhook and existing reconciliation remain authoritative. To preserve reconciliation semantics, notification failure is caught and logged with only the payment UUID; it cannot roll back or rewrite financial state. The deterministic service producer can be retried safely.

### Organization announcement

Active organization owners/admins may announce within their organization. A verified platform admin may announce for another organization only when the client explicitly requests platform-support mode. Support mode creates no membership and grants no inbox or organization ownership.

Recipients are derived from active organization memberships and deduplicated. Audiences are:

- `all`: every active member;
- `players`, `parents`, `coaches`: matching active role;
- `staff`: active owner, admin, or coach.

The actor is included when their active membership matches the audience. A platform-support actor without membership is not silently added. A successful fan-out and `organization_announcement_created` audit row share one transaction. The audit records actor, organization, audience, batch key, recipient count, timestamp, and authorization source, but not the announcement body.

## Deduplication

The notification unique constraint is `(org_id, recipient_user_id, category, deduplication_key)`. Producer keys bind the authoritative related entity. Announcement requests additionally use an operation UUID and a SHA-256 material fingerprint; reusing a key with changed organization, actor, audience, title, body, or support context fails closed. A Swift operation state preserves that UUID after ambiguous failure and clears it only after confirmed success.

## Swift architecture

`NotificationCenterModels.swift` defines strict request/response contracts, unknown-safe categories/routes, announcement validation, idempotency state, and safe internal destinations. `SupabaseService` exposes the five typed Edge actions. `NotificationCenterViewModel` owns pagination, unread state, stale-response tokens, read de-duplication, user-switch clearing, and announcement in-flight protection.

One shared top-level bell opens `NotificationCenterView` for every authenticated role. The list supports all-organizations or selected-organization scope, unread filtering, refresh, pagination, mark-all-read, badge counts, and readable loading/empty/error states. Announcement controls appear only for an active local owner/admin context or an explicit platform-support organization screen; the server remains authoritative.

## Routing

Supported internal route values are `payment_request`, `payment`, `finance`, `organization_announcement`, and `notification_detail`. Routes validate required UUID payloads. Unknown categories, future routes, and malformed payloads fall back to a notification detail view instead of crashing or crossing an authorization boundary. Phase 9A does not add external deep links.

## Read and archive semantics

`read_at` is set once. Repeated mark-read calls are idempotent. Badge counts decrement only after server success and reconcile from server truth on refresh. Mark-all is actor-owned and optionally organization-scoped. Archive is supported at the table/RLS layer for later UI work; archived rows are excluded from the current inbox.

## Future delivery channels

A future `sd_notification_deliveries` table can reference `sd_notifications.id` and store one row per channel attempt (`apns`, `email`, or `sms`) with provider-neutral status, attempt timestamps, and bounded error codes. The core notification row remains the canonical recipient/event record; channel delivery must not duplicate authorization or store provider secrets/full payloads in the inbox table.

## Deployment order

No deployment is performed by this implementation. A future controlled release should:

1. Back up and review the additive migration and live role/status assumptions.
2. Apply `20260715020000_notification_center_foundation.sql`.
3. Deploy `notification-center` with JWT verification and required Supabase secrets.
4. Run actor-isolation, producer, deduplication, and announcement smoke tests.
5. Release the Swift clients.

The Edge Function should not be released before its tables/RPCs exist. Clients tolerate an unavailable center with a readable error, but producers require the migration.

## Testing checklist

- Actor-only list/read/mark-all and archived exclusion.
- Organization isolation, pagination, and unread counts.
- Announcement role/support authorization, active audiences, deduplication, and audit safety.
- Payment-request player/linked-parent producer and retry behavior.
- Successful-payment player/parent/staff producer, webhook retry, and failure isolation.
- Unknown Swift category/route fallback, user switching, stale-response rejection, badge updates, and double-send prevention.
- Existing payment-request, payment-webhook, finance, and expense regressions.
- Native macOS and iOS Simulator builds.

## Non-goals

Phase 9A does not implement push/email/SMS delivery, device registration, chat, attachments, chat read receipts, preferences, quiet hours, scheduling, campaigns, analytics, universal links, or changes to Stripe, StoreKit, finance, expenses, Checkout, authentication, membership semantics, or payment reconciliation.
