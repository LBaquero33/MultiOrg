# Home Plate APNs Push Delivery (Phase 9B)

## Source of truth

`public.sd_notifications` remains the authoritative inbox. APNs is a best-effort delivery channel layered on that row; a missing device, an APNs outage, or a terminal delivery failure never removes the inbox notification or changes a payment/payment-request transaction.

Phase 9B queues remote alerts only for `payment_request_created`, `payment_received`, and `organization_announcement`. Chat, facility alerts, category preferences, quiet hours, and test-push UI are non-goals.

## Device lifecycle

Apple returns an opaque token to the app after the user authorizes notifications. Swift converts its bytes to lowercase hexadecimal and calls the JWT-authenticated `push-device-registration` function with token, platform, build environment, bundle identifier, app version, and OS version. The Edge Function derives the user from `auth.getUser()`; clients cannot supply a user or authorization claim.

`public.sd_push_devices` has one row per `(device_token, environment, app_bundle_id)`. Re-registering refreshes metadata and re-enables the row. When the same physical app token registers after an account change, the service-role RPC locks and transfers that one row to the new verified actor, while marking old unsent deliveries skipped. Thus one active token cannot belong to two users. Normal sign-out calls unregister before ending the Supabase session; an offline failure is repaired by the controlled transfer on the next sign-in. Delivery history is not deleted.

Authenticated users can select only their own device rows under RLS. They cannot directly insert/update device rows or access any delivery row. Registration mutations use SECURITY DEFINER RPCs with `search_path = ''`, schema-qualified objects, revoked public/anon/authenticated execution, and service-role-only grants.

## APNs token authentication and environments

The worker uses Apple token authentication, not certificates. Native Web Crypto imports the PKCS#8 `.p8` key and signs an ES256 provider JWT with:

- header: `alg=ES256`, `kid=APNS_KEY_ID`
- claims: `iss=APNS_TEAM_ID`, `iat=current Unix seconds`

The token is reused for at most 50 minutes. `APNS_PRIVATE_KEY` accepts either real multiline PEM text or a secret whose newlines are represented as `\n`. Credentials, provider tokens, complete device tokens, and notification bodies are never logged.

Server configuration selects exactly one trusted environment per deployment:

- `sandbox` → `https://api.sandbox.push.apple.com`
- `production` → `https://api.push.apple.com`

The device row environment must equal `APNS_ENVIRONMENT`; the row bundle identifier must equal the configured iOS or macOS topic. Debug targets advertise development/sandbox, Release targets production. A sandbox token is never routed to production APNs or vice versa.

## Queue and state machine

Migration `20260715030000_apns_push_delivery.sql` adds:

- `sd_push_devices`: actor ownership, canonical token, Apple platform, environment/topic, authorization state, app/OS metadata, activity/disable timestamps and reason.
- `sd_notification_deliveries`: source notification, target device, channel, state, bounded attempt count, claim identity/time, APNs response facts, retry/sent/failed timestamps.

The delivery uniqueness key is `(notification_id, device_id, channel)`. An after-insert statement trigger on `sd_notifications` inserts one pending row per active authorized recipient device for the three Phase 9B categories. `ON CONFLICT DO NOTHING` prevents producer retries from duplicating delivery. With no device, the inbox row simply remains available.

The trigger never contacts APNs. It asks `pg_net` to invoke the internal worker. `pg_net` records the request in the notification transaction and dispatches it only after commit, so the immediate worker normally sees committed deliveries within seconds. A one-minute `pg_cron` job is the fallback for missed wakeups and scheduled retries. Both obtain the worker URL and a dedicated internal secret from Supabase Vault.

Additive reliability migration `20260715040000_notification_delivery_wakeup_reliability.sql` preserves that flow and adds one bounded recovery: a `queue_trigger` worker invocation that initially claims zero rows waits 600 milliseconds and claims once more. Cron and manual invocations remain single-pass. Duplicate wakeups remain harmless because the claim RPC still uses `FOR UPDATE SKIP LOCKED`.

The same migration adds service-role-readable `sd_notification_delivery_wakeups`. It stores only wakeup source, ready-row count, `pg_net` request ID, normalized state/status/error, worker claimed count, and poll count. A separate one-minute observer maps `net._http_response` outcomes to `succeeded`, `unauthorized`, `worker_failed`, or `network_failed`. It never copies request headers, Vault values, or response/notification bodies. Records expire after 14 days.

The interactive payment-request and organization-announcement paths also issue a best-effort `producer_commit` wake only after their transaction RPC returns. This provides the normal 1–5 second path even when database HTTP dispatch is degraded. It sends no recipient or notification payload and cannot change or roll back the already-completed business result. Payment reconciliation remains unchanged and, like every producer, uses the database after-commit trigger and one-minute cron fallback.

The worker accepts no recipient or payload. It requires `x-home-plate-worker-secret`, then calls service-role-only `sd_claim_notification_deliveries(25, claim_uuid)`. The RPC uses `FOR UPDATE SKIP LOCKED`, rechecks current token ownership/authorization and notification eligibility, and recovers claims stale for five minutes. Independent workers therefore cannot claim the same ready row concurrently. The notification title/body/routing and recipient unread badge are loaded from authoritative database rows at claim time.

States are:

`pending → sending → sent | retryable | failed | skipped`

Retryable failures use delays of 30 seconds, 2 minutes, 10 minutes, and 30 minutes. Five attempts is terminal. HTTP 429/500/503 and APNs `Shutdown`, `TooManyRequests`, `InternalServerError`, or `ServiceUnavailable` are retryable. Authentication/topic/payload configuration failures are terminal rather than looping.

`BadDeviceToken`, `DeviceTokenNotForTopic`, `Unregistered`, and `TopicDisallowed` permanently fail that delivery, disable the device, and skip its other unsent rows. A later authenticated Apple token registration may safely re-enable/replace it.

## Payload and badge

The worker sends an alert payload bounded to 4,096 bytes:

```json
{
  "aps": {
    "alert": { "title": "…", "body": "…" },
    "sound": "default",
    "badge": 3,
    "category": "HOME_PLATE_NOTIFICATION",
    "thread-id": "organization UUID"
  },
  "home_plate": {
    "notification_id": "notification UUID",
    "org_id": "organization UUID",
    "category": "payment_request_created",
    "action_route": "payment_request",
    "action_payload": { "payment_request_id": "UUID" },
    "schema_version": "notification_v1"
  }
}
```

Badge is the recipient's authoritative, unarchived unread count at claim time. Routing metadata is allowlisted to payment request/payment/announcement UUIDs. Unknown categories become a generic “Home Plate” alert and unknown routes become `notification_detail`. No email, payment method, Stripe secret/identifier, medical data, JWT, or unrestricted metadata is included.

## Tap and foreground behavior

The Apple delegate extracts only a versioned `home_plate.notification_id`. `AppState` calls notification-center `get`, scoped to the JWT recipient, then `mark_read`; only that returned inbox model enters the existing `NotificationRouter`. A malformed or unauthorized ID displays a safe unavailable message. If signed out, only the opaque UUID is kept in `UserDefaults`, then ownership is validated after sign-in. Push title/body and route data are never treated as authorization.

In the foreground, the existing Apple delegate policy presents banner/list/sound and posts an internal refresh event. The bell reloads its authoritative unread count and refreshes an open inbox. It does not schedule a second local notification.

The older local “announcement” behavior belongs to realtime chat channels (`sd_chat_message_*`), which is explicitly outside Phase 9B. The Phase 9A organization announcement composer never calls `UNUserNotificationCenter.add`; its server-created inbox row produces exactly one APNs delivery per device. Existing local chat and facility behavior is unchanged.

## Apple capabilities

Both XcodeGen targets reference target-specific entitlements:

- iOS: `aps-environment = $(APS_ENVIRONMENT)`
- macOS: `com.apple.developer.aps-environment = $(APS_ENVIRONMENT)`

XcodeGen maps Debug to `development` and Release to `production`. No background mode was added: alert delivery and tap handling do not require background content execution.

Before a real build, in Apple Developer:

1. Enable Push Notifications for App ID `com.multiorg.app` and, if shipping native Mac push, `com.multiorg.app.mac`.
2. Regenerate/download provisioning profiles containing the push entitlement.
3. Create or select one APNs Auth Key with APNs permission; retain its Key ID, Team ID, and `.p8` once. Do not commit the key.
4. Confirm iOS topic `com.multiorg.app`; configure the Mac topic only when that target is provisioned for APNs.

## Secrets and deployment order

Set these Edge Function secrets later (values are intentionally absent here):

- `APNS_KEY_ID`
- `APNS_TEAM_ID`
- `APNS_PRIVATE_KEY`
- `APNS_TOPIC` (`com.multiorg.app` in the intended project)
- `APNS_MAC_TOPIC` (optional until Mac APNs is provisioned)
- `APNS_ENVIRONMENT` (`sandbox` or `production`)
- `NOTIFICATION_DELIVERY_WORKER_SECRET` (new random dedicated value)
- normal `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY`

Deployment sequence after review:

1. Configure Apple identifiers/profiles and Edge secrets for the chosen environment.
2. Deploy `push-device-registration` (`verify_jwt=true`).
3. Deploy `process-notification-deliveries` (`verify_jwt=false`; internal secret enforced in handler).
4. Deploy the changed `notification-center` authoritative `get` action.
5. Put `notification_delivery_worker_url` (the deployed worker URL) and `notification_delivery_worker_secret` (same dedicated secret) into Supabase Vault.
6. Apply migrations through Phase 9A, then `20260715030000_apns_push_delivery.sql`, then `20260715040000_notification_delivery_wakeup_reliability.sql`. The latter deterministically replaces the one-minute fallback and adds wakeup-response observation.
7. Ship signed Apple builds with matching environment/topic profiles.

No separate dashboard webhook must be created: the migration owns the `pg_net` immediate wakeup and `pg_cron` fallback. If the project disallows these extensions, do not apply the migration until an equivalent authenticated scheduler is selected.

Rollback the reliability layer first: unschedule its observer, restore the original no-argument worker cron command/function, and drop its overload, observer, and diagnostics table. To remove all Phase 9B behavior afterward, unschedule the worker, drop the queue trigger/functions, and then drop delivery/device tables. Never drop `sd_notifications` as part of rollback.

## Producer integration and testing

Payment-request creation and verified payment reconciliation already insert canonical Phase 9A rows transactionally. Phase 9B observes only those rows; push failure cannot roll back or rewrite their business state. Organization announcement idempotency likewise deduplicates inbox rows, while delivery uniqueness deduplicates each device channel.

Pre-release checklist:

- Run Deno format/check and push, notification-center, payment-request, connected-payment webhook, finance, expense, and StoreKit regressions.
- Verify the migration in a disposable/local Supabase environment, including extensions, Vault lookup, concurrent claims, retry timing, and RLS.
- Build iOS and macOS from regenerated XcodeGen output.
- On physical sandbox devices: permission prompt, token registration, multiple devices, account switching, foreground alert/inbox refresh, signed-out tap resume, payment request/payment received/announcement, badge, invalid token disable, and retry recovery.
- Repeat in production with production provisioning and APNs configuration before release.

Simulator/unit tests prove contracts and lifecycle logic but do not prove APNs network delivery. Real credentials, signed provisioning, a physical device, deployed functions, Vault values, and the applied migration are still required.
