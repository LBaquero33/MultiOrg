import SwiftUI

struct PlayerSubscriptionPaywall: View {
  @EnvironmentObject private var appState: AppState
  @StateObject private var store = PlayerSubscriptionStore()
  let playerId: UUID

  @State private var syncError: String?
  @State private var isVerifying = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(store.product?.displayName ?? "Home Plate Player Access").font(.headline)
      Text(store.product?.description ?? "Monthly player access through the App Store.")
        .font(.footnote).foregroundStyle(DHDTheme.textSecondary)
      if let price = store.product?.displayPrice { Text(price + " per month").font(.subheadline.weight(.semibold)) }
      purchaseState
      HStack(spacing: 10) {
        Button { Task { await buy() } } label: { Label("Subscribe with Apple", systemImage: "apple.logo") }
          .buttonStyle(.borderedProminent).disabled(store.product == nil || isWorking)
        Button { Task { await restore() } } label: { Text("Restore Purchases") }
          .buttonStyle(.bordered).disabled(isWorking)
      }
      if store.pendingPurchase != nil {
        HStack(spacing: 8) {
          if let syncError { Text(syncError).font(.footnote).foregroundStyle(.red) }
          Button(syncError == nil ? "Verify purchase" : "Retry verification") {
            Task { await synchronizePendingPurchase() }
          }
            .font(.footnote.weight(.semibold))
            .disabled(isVerifying)
        }
      }
    }
    .task { await store.loadProduct(); _ = await store.refreshCurrentEntitlements() }
  }

  @ViewBuilder private var purchaseState: some View {
    switch store.state {
    case .loading, .purchasing: HStack { ProgressView(); Text("Contacting Apple…").foregroundStyle(DHDTheme.textSecondary) }
    case .pending: Text("Purchase approval is pending.").font(.footnote).foregroundStyle(.orange)
    case .canceled: Text("Purchase canceled. Your account remains available for restore or organization-granted access.").font(.footnote).foregroundStyle(DHDTheme.textSecondary)
    case .restored: Text("Purchases restored. Refreshing account access…").font(.footnote).foregroundStyle(DHDTheme.textSecondary)
    case .unavailable: Text("Apple subscriptions are unavailable on this device right now.").font(.footnote).foregroundStyle(.orange)
    case .failed(let message): Text(message).font(.footnote).foregroundStyle(.red)
    default: EmptyView()
    }
  }

  private var isWorking: Bool { if case .purchasing = store.state { return true }; if case .loading = store.state { return true }; return isVerifying }

  private func buy() async {
    guard let context = await purchaseContext() else { return }
    if let purchase = await store.purchase(context: context) {
      await synchronize(purchase)
    }
  }

  private func restore() async {
    if let purchase = await store.restorePurchases() {
      await synchronize(purchase)
    }
  }

  private func synchronizePendingPurchase() async {
    guard let pending = store.pendingPurchase else { return }
    await synchronize(pending)
  }

  private func synchronize(_ pending: PlayerSubscriptionStore.VerifiedPurchase) async {
    guard !isVerifying, let context = await purchaseContext(), let supabase = appState.supabase else { return }
    guard pending.productID == PlayerSubscriptionStore.monthlyProductID else {
      syncError = "The restored purchase is for a different Home Plate product."
      return
    }
    guard let transactionToken = pending.appAccountToken else {
      syncError = "This purchase is missing its secure player-account link. Contact support."
      return
    }
    guard transactionToken == context.appAccountToken else {
      syncError = "This purchase belongs to a different player or organization context. Contact support."
      return
    }
    isVerifying = true
    defer { isVerifying = false }
    do {
      _ = try await supabase.verifyApplePlayerSubscription(signedTransaction: pending.signedTransaction, context: context)
      await store.finishPendingTransaction(id: pending.id)
      syncError = nil
      await appState.refreshEntitlement()
    } catch {
      syncError = error.localizedDescription
    }
  }

  private func purchaseContext() async -> PlayerSubscriptionContext? {
    guard let orgId = appState.activeOrgId, let supabase = appState.supabase else { syncError = "No active organization was found."; return nil }
    do {
      let session = try await supabase.client.auth.session
      if appState.myProfile?.isPlayer == true, session.user.id != playerId {
        throw NSError(domain: "HomePlate", code: 2)
      }
      guard let context = PlayerSubscriptionContext.make(orgId: orgId, playerId: playerId, billingUserId: session.user.id) else { throw NSError(domain: "HomePlate", code: 1) }
      return context
    } catch { syncError = "Sign in again before starting a purchase."; return nil }
  }
}
