# Home Plate App Store review remediation

## Decision

Home Plate uses two intentionally separate commercial models:

1. Individual and family digital player access is purchased only with Apple In-App Purchase in the iOS app.
2. Organization access is contracted directly with baseball organizations for their groups. The iOS app does not offer organization enrollment, organization subscription checkout, or organization billing management.

Payments that an organization requests from a player or parent are only for real-world baseball services delivered outside the app. Those payments never create or reactivate a Home Plate digital entitlement.

## Guideline 2.3.6: accurate age-rating metadata

Home Plate supports parent and guardian relationships, but it does not currently claim to provide Apple-defined Parental Controls or Age Assurance. The App Store Connect age-rating answer for Parental Controls must therefore be **None**. This is metadata-only and is not represented as an application feature.

## Guideline 3.1.1: account registration

The iOS login experience is sign-in-only. It has no Create Account mode, no Create Organization mode, no organization early-access call to action, and no public pricing or payment navigation. Organization and member provisioning remain available only on the separately distributed macOS/web administration surfaces.

An invited iOS user who is not signed in is directed to sign in with credentials supplied through the organization. The iOS app does not turn an invitation into a self-registration form.

## Guidelines 3.1.1 and 3.1.3(c): payment authority

The iOS player paywall uses StoreKit product `com.homeplate.player.monthly`. Verified StoreKit transactions are sent to the server, which checks the authenticated organization/player/billing relationship and calls the service-role-only atomic Apple subscription synchronizer. A client cannot submit an access boolean.

The following retired paths cannot activate individual digital access:

- organization administrators cannot grant or revoke player entitlements;
- players created by an organization administrator on a non-iOS administration surface receive `organization_sponsored` access only when the server verifies an active organization-wide subscription; self-registered or otherwise uncovered players start inactive as `pending_apple_purchase`;
- the legacy Stripe player webhook is a verified no-op;
- the public web Stripe player checkout is permanently retired;
- paying an organization payment request does not activate digital access;
- the legacy Stripe subscription database function fails closed;
- legacy active entitlements backed by active organization membership and subscription evidence are audited and reclassified as `organization_sponsored`; all remaining non-Apple legacy access is audited and deactivated.

Organization Stripe Connect and organization-issued payment requests remain separate because they support real-world baseball services. The copy shown before checkout explicitly says that the payment is for a service delivered outside the app and does not buy or unlock Home Plate digital access.

## Deployment order

The iOS and website repositories currently identify different Supabase projects. Treat both as potentially authoritative until production ownership is confirmed, and run the read-only audit against both before applying either migration:

```sql
select
  source,
  count(*) as active_entitlement_count,
  array_agg(user_id order by user_id) as affected_user_ids
from public.sd_access_entitlements
where is_active is true
  and source not in ('apple', 'organization_sponsored')
group by source
order by source;
```

1. Run the read-only audit against both configured Supabase projects and identify every legacy active entitlement.
2. Cancel or migrate any still-billing legacy Stripe player subscription and communicate the change before access is deactivated.
3. Confirm which project or projects serve production, then apply each repository's `20260903180000_app_store_commerce_compliance.sql` migration to every production project in use.
4. Deploy `org_admin`, `create_account`, and the retired `stripe-webhook` from this repository.
5. Deploy the public website remediation, including the retired `create-player-subscription-checkout` and the platform Stripe webhook no-op for player subscriptions.
6. Run a StoreKit sandbox purchase and restore test for a player and an authorized linked parent.
7. Confirm a paid organization service request changes payment state but does not change `sd_access_entitlements`.
8. Confirm the production iOS archive contains no external subscription URL or organization registration UI.

## Production remediation record — September 3, 2026

- Both repositories resolve to Supabase project `kbulbvngysflfhaqpvtv` for the deployed production backend.
- Before migration, 120 active entitlements were labeled `org_admin_override`. Every one had both an active organization membership and an active organization-wide subscription. No active Stripe player subscriptions existed.
- Migration `20260903180000_app_store_commerce_compliance.sql` was applied successfully. The 120 covered entitlements were audited and reclassified as `organization_sponsored`; zero active users were deactivated.
- The legacy payment-request access trigger is absent, and `service_role` cannot execute the retired Stripe player-entitlement function.
- Edge Functions `org_admin`, `create_account`, `stripe-webhook`, `create-player-subscription-checkout`, and `stripe-platform-webhook` were deployed and reported active.
- The remediated website was deployed to production as Vercel deployment `dpl_DcqLVRV2CrNg26fGmyFoP5cYmELj`, and `www.homeplateapps.com` resolved to that ready deployment.
- The iOS source and packaged simulator product contain no organization/account-creation, organization-checkout, organization-billing-management, or external player-subscription route. App Store upload and submission remain an App Store Connect task.

## App Review test path

1. Launch Home Plate. The first screen offers sign-in and support only.
2. Sign in with the supplied player review account.
3. If the player has no access, the Apple paywall shows the StoreKit product, Subscribe, and Restore Purchases.
4. No organization creation, organization subscription, Stripe player subscription, or manual grant action is available in the iOS app.
5. Organization payment requests, if present in the review account, are labeled as payments for real-world baseball services and explicitly state that they do not unlock digital access.

## Suggested App Review reply after the App Store Connect metadata is corrected

We revised Home Plate to address Guidelines 3.1.1 and 3.1.3(c). The iOS app is now sign-in-only and no longer contains account or organization registration, organization subscription checkout, external player subscription checkout, or manual player-access grants. Individual and family digital player access is available through Apple In-App Purchase using product `com.homeplate.player.monthly`. Direct organization agreements are limited to organization-sponsored group access. Any Stripe payment request visible in the app is for a real-world baseball service delivered outside the app and cannot activate digital access. Reviewers can launch the app, sign in with the review credentials, and see the StoreKit paywall for an inactive player account.

We also corrected the Age Rating selection for Parental Controls to None because Home Plate does not currently provide Apple-defined Parental Controls or Age Assurance.
