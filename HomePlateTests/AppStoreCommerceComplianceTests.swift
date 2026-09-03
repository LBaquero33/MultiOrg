import Foundation
import Testing
@testable import HomePlate

@Suite("App Store commerce compliance")
struct AppStoreCommerceComplianceTests {
  @Test("iOS authentication is sign-in only")
  func iOSAuthenticationIsSignInOnly() throws {
    let login = try sourceFile("HomePlate/Features/Login/LoginView.swift")
    let appState = try sourceFile("HomePlate/Core/AppState.swift")
    let platformAdmin = try sourceFile("HomePlate/Features/Admin/PlatformAdminDashboardView.swift")
    let service = try sourceFile("HomePlate/Core/SupabaseService.swift")

    #expect(login.contains("#if os(macOS)\n    case create = \"Create account\""))
    #expect(login.contains("#if os(macOS)\n  private var publicHeader"))
    #expect(login.contains("return \"Use the email and password provided through your organization.\""))
    #expect(appState.contains("#if os(macOS)\n  func signUp("))
    #expect(platformAdmin.contains("#if os(macOS)\n  private func newOrganizationButton"))
    #expect(service.contains("#if os(macOS)\n  func platformCreateOrganization("))
  }

  @Test("iOS target exposes no external digital-subscription route")
  func iOSTargetHasNoExternalDigitalSubscriptionRoute() throws {
    let project = try sourceFile("project.yml")
    let info = try sourceFile("Configs/HomePlate-iOS-Info.plist")
    let service = try sourceFile("HomePlate/Core/SupabaseService.swift")
    let parentBilling = try sourceFile("HomePlate/Features/Parent/SDParentBillingView.swift")
    let iOSTarget = try #require(project.range(of: "  HomePlate:\n"))
    let macTarget = try #require(project.range(of: "  HomePlateMac:\n"))
    let iOSProjectConfiguration = String(project[iOSTarget.lowerBound..<macTarget.lowerBound])

    #expect(!iOSProjectConfiguration.contains("DHD_STRIPE_SUBSCRIBE_URL"))
    #expect(!info.contains("DHD_STRIPE_SUBSCRIBE_URL"))
    #expect(!service.contains("func createPlayerBillingPortal"))
    #expect(!parentBilling.contains("Player Subscription"))
    #expect(!parentBilling.contains("openSubscriptionPortal"))
    #expect(parentBilling.contains("never unlock Home Plate digital access"))
  }

  @Test("organization admins cannot manually grant consumer access")
  func organizationAdminsCannotGrantConsumerAccess() throws {
    let actions = try sourceFile("supabase/functions/_shared/org_admin_actions.ts")
    let backend = try sourceFile("supabase/functions/org_admin/index.ts")
    let service = try sourceFile("HomePlate/Core/SupabaseService.swift")
    let playerProfile = try sourceFile("HomePlate/Features/Coach/CoachPlayerProfileView.swift")

    #expect(!actions.contains("set_player_access"))
    #expect(!backend.contains("action === \"set_player_access\""))
    #expect(!backend.contains("source: \"org_admin_override\""))
    #expect(backend.contains("organization_subscription_lookup_failed"))
    #expect(backend.contains("\"organization_sponsored\""))
    #expect(backend.contains("\"pending_apple_purchase\""))
    #expect(!service.contains("adminSetPlayerAccess"))
    #expect(service.contains("#if os(macOS)\n  func adminCreateOrgUser("))
    #expect(!playerProfile.contains("Grant access"))
    #expect(!playerProfile.contains("Require payment"))
  }

  @Test("legacy Stripe and service-payment access grants fail closed")
  func legacyAccessGrantsFailClosed() throws {
    let migration = try sourceFile("supabase/migrations/20260903180000_app_store_commerce_compliance.sql")
    let retiredWebhook = try sourceFile("supabase/functions/stripe-webhook/index.ts")
    let paymentCard = try sourceFile("HomePlate/Features/Payments/PaymentRequestCard.swift")

    #expect(migration.contains("drop trigger if exists trg_sd_payment_requests_paid"))
    #expect(migration.contains("drop function if exists public.sd_on_payment_request_paid()"))
    #expect(migration.contains("message = 'stripe_player_digital_access_disabled'"))
    #expect(migration.contains("source not in ('apple', 'organization_sponsored')"))
    #expect(migration.contains("'reclassified_organization_sponsored'"))
    #expect(migration.contains("subscription.status in ('active', 'trialing')"))
    #expect(migration.contains("alter column source set default 'pending_apple_purchase'"))
    #expect(!retiredWebhook.contains("createClient"))
    #expect(!retiredWebhook.contains(".rpc(\"sd_sync_stripe_player_subscription\""))
    #expect(retiredWebhook.contains("player_digital_access_uses_apple_iap"))
    #expect(paymentCard.contains("does not purchase or unlock Home Plate digital access"))
  }

  @Test("individual access remains purchasable with Apple IAP")
  func appleIAPRemainsAvailable() throws {
    let paywall = try sourceFile("HomePlate/Features/Home/PlayerSubscriptionPaywall.swift")
    let purchaseContext = try sourceFile("HomePlate/Core/ApplePlayerPurchaseContext.swift")
    let verifier = try sourceFile("supabase/functions/verify-apple-player-subscription/index.ts")
    let subscriptionSync = try sourceFile("supabase/functions/_shared/apple_player_subscription.ts")

    #expect(paywall.contains("title: \"Subscribe\""))
    #expect(paywall.contains("Billed through the App Store"))
    #expect(purchaseContext.contains("com.homeplate.player.monthly"))
    #expect(verifier.contains("syncAppleSubscriptionAtomically"))
    #expect(subscriptionSync.contains("\"sd_sync_apple_player_subscription\""))
  }

  private func sourceFile(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}
