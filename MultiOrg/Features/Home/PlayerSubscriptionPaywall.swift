import SwiftUI

struct PlayerSubscriptionPaywall: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase

  @StateObject private var store = PlayerSubscriptionStore()
  let playerId: UUID

  @State private var contextError: String?
  @State private var accessMessage: String?
  @State private var isRefreshingAccess = false
  @State private var automaticallyAttemptedTransactionIDs = Set<UInt64>()

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 5) {
        Text(store.product?.displayName ?? "Home Plate Player Monthly Access")
          .font(.headline)
        Text(store.product?.description ?? "Unlock this player's Home Plate training, scheduling, and development tools.")
          .font(.footnote)
          .foregroundStyle(DHDTheme.textSecondary)
        if let price = store.product?.displayPrice {
          Text("\(price) per month")
            .font(.subheadline.weight(.semibold))
        }
      }

      subscriptionStatus

      Button {
        Task { await subscribe() }
      } label: {
        Label("Subscribe", systemImage: "apple.logo")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .disabled(store.product == nil || isWorking)

      HStack(spacing: 10) {
        Button {
          Task { await restore() }
        } label: {
          Label("Restore Purchases", systemImage: "arrow.clockwise")
        }
        .disabled(isWorking)

        Button {
          Task { await retryVerification() }
        } label: {
          Label("Retry", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(isWorking)
      }
      .buttonStyle(.bordered)

      HStack(spacing: 10) {
        Button {
          Task { await refreshAccess() }
        } label: {
          Label("Refresh Access", systemImage: "checkmark.shield")
        }
        .disabled(isWorking)

        Button {
          contactSupport()
        } label: {
          Label("Contact Support", systemImage: "envelope")
        }
        .disabled(supportEmail == nil)
      }
      .buttonStyle(.bordered)

      HStack(spacing: 16) {
        Link("Privacy", destination: privacyURL)
        Link("Terms", destination: termsURL)
        Spacer()
        Button("Sign Out", role: .destructive) {
          Task { await appState.signOut() }
        }
      }
      .font(.footnote)
    }
    .task {
      await prepareAndRecover()
    }
    .onChange(of: store.pendingPurchase?.id) { _, newID in
      guard newID != nil, let purchase = store.pendingPurchase else { return }
      Task { await synchronize(purchase, automatic: true) }
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      Task { await recoverAfterForeground() }
    }
  }

  @ViewBuilder
  private var subscriptionStatus: some View {
    if let contextError {
      statusRow(contextError, color: .red, symbol: "exclamationmark.triangle")
    } else if let accessMessage {
      statusRow(accessMessage, color: .green, symbol: "checkmark.circle")
    } else {
      switch store.state {
      case .idle:
        EmptyView()
      case .loadingProduct:
        statusRow("Loading Apple subscription options...", color: DHDTheme.textSecondary, symbol: nil, showsProgress: true)
      case .ready:
        statusRow("Ready to subscribe or restore an existing purchase.", color: DHDTheme.textSecondary, symbol: "checkmark.circle")
      case .purchasing:
        statusRow("Waiting for Apple to complete the purchase...", color: DHDTheme.textSecondary, symbol: nil, showsProgress: true)
      case .pending:
        statusRow("Apple is processing this purchase. It will remain recoverable until access is updated.", color: .orange, symbol: "clock")
      case .recovering:
        statusRow("Looking for an existing Apple purchase...", color: DHDTheme.textSecondary, symbol: nil, showsProgress: true)
      case .synchronizing:
        statusRow("Updating Home Plate access...", color: DHDTheme.textSecondary, symbol: nil, showsProgress: true)
      case .active:
        statusRow("Player access is active.", color: .green, symbol: "checkmark.shield.fill")
      case .canceled:
        statusRow("Purchase canceled. No charge or access change was made.", color: DHDTheme.textSecondary, symbol: "xmark.circle")
      case .failed(let failure):
        statusRow(failure.message, color: .red, symbol: "exclamationmark.triangle")
      }
    }
  }

  private func statusRow(
    _ message: String,
    color: Color,
    symbol: String?,
    showsProgress: Bool = false
  ) -> some View {
    HStack(alignment: .top, spacing: 8) {
      if showsProgress {
        ProgressView()
          .controlSize(.small)
      } else if let symbol {
        Image(systemName: symbol)
          .padding(.top, 1)
      }
      Text(message)
        .font(.footnote)
        .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(color)
  }

  private var isWorking: Bool {
    store.isBusy || isRefreshingAccess
  }

  private func prepareAndRecover() async {
    guard let context = await purchaseContext() else { return }
    if let purchase = await store.prepare(context: context) {
      await synchronize(purchase, automatic: true)
    }
  }

  private func subscribe() async {
    contextError = nil
    accessMessage = nil
    guard let context = await purchaseContext() else { return }
    if let purchase = await store.purchase(context: context) {
      await synchronize(purchase, automatic: true)
    }
  }

  private func restore() async {
    contextError = nil
    accessMessage = nil
    guard let context = await purchaseContext() else { return }
    if let purchase = await store.restorePurchases(context: context) {
      await synchronize(purchase, automatic: true)
    }
  }

  private func retryVerification() async {
    contextError = nil
    accessMessage = nil
    guard let context = await purchaseContext() else { return }
    guard let purchase = await store.retryVerification(context: context) else { return }
    await synchronize(purchase, automatic: false)
  }

  private func recoverAfterForeground() async {
    guard let context = await purchaseContext() else { return }
    if let purchase = await store.recoverForForeground(context: context) {
      await synchronize(purchase, automatic: true)
    }
  }

  private func synchronize(
    _ purchase: PlayerSubscriptionStore.VerifiedPurchase,
    automatic: Bool
  ) async {
    if automatic {
      guard automaticallyAttemptedTransactionIDs.insert(purchase.id).inserted else { return }
    }
    guard store.beginSynchronization(transactionID: purchase.id) else { return }
    guard let context = await purchaseContext(), let supabase = appState.supabase else {
      store.synchronizationFailed(
        transactionID: purchase.id,
        failure: .backendSynchronizationFailed
      )
      return
    }

    do {
      diagnostic("backend_verification_started")
      let response = try await supabase.verifyApplePlayerSubscription(
        purchase: purchase,
        context: context
      )
      diagnostic("backend_verification_response_received")

      // Re-read the target player's backend entitlement before StoreKit is
      // finished. This covers both self-pay and linked-parent purchases.
      let entitlement = try await supabase.fetchAccessEntitlement(userId: context.playerId)
      let accessIsActive = response.access_is_active && entitlement?.is_active == true
      if context.billingUserId == context.playerId {
        await appState.refreshEntitlement()
      }

      await store.completeSynchronization(
        transactionID: purchase.id,
        backendPersisted: response.persisted,
        entitlementSynchronized: response.entitlement_synchronized,
        accessIsActive: accessIsActive
      )
      if accessIsActive {
        contextError = nil
        accessMessage = "Player access is active."
      }
    } catch let error as SupabaseService.AppleSubscriptionSynchronizationError {
      diagnostic("backend_verification_response_received")
      store.synchronizationFailed(
        transactionID: purchase.id,
        failure: error.subscriptionFailure
      )
    } catch {
      diagnostic("backend_verification_response_received")
      store.synchronizationFailed(
        transactionID: purchase.id,
        failure: .backendSynchronizationFailed
      )
    }
  }

  private func refreshAccess() async {
    guard let supabase = appState.supabase else { return }
    isRefreshingAccess = true
    defer { isRefreshingAccess = false }
    do {
      let session = try await supabase.client.auth.session
      if session.user.id == playerId {
        await appState.refreshEntitlement()
        if appState.myEntitlement?.is_active == true, !appState.needsAccess {
          accessMessage = "Player access is active."
          contextError = nil
        } else {
          contextError = "This player does not have active access yet."
        }
      } else {
        let entitlement = try await supabase.fetchAccessEntitlement(userId: playerId)
        if entitlement?.is_active == true {
          accessMessage = "Player access is active."
          contextError = nil
        } else {
          contextError = "This player does not have active access yet."
        }
      }
    } catch {
      contextError = "Home Plate could not refresh access. Please try again."
    }
  }

  private func purchaseContext() async -> ApplePlayerPurchaseContext? {
    guard let organizationId = appState.activeOrgId,
          let supabase = appState.supabase else {
      contextError = "Select an organization before managing a player subscription."
      return nil
    }

    do {
      let session = try await supabase.client.auth.session
      if appState.myProfile?.isPlayer == true, session.user.id != playerId {
        contextError = "A player account can only purchase access for itself."
        return nil
      }
      guard let context = ApplePlayerPurchaseContext.make(
        organizationId: organizationId,
        playerId: playerId,
        billingUserId: session.user.id
      ) else {
        contextError = "Home Plate could not prepare this subscription."
        return nil
      }
      contextError = nil
      return context
    } catch {
      contextError = "Your sign-in expired. Sign in again before managing a purchase."
      return nil
    }
  }

  private var supportEmail: String? {
    let organizationEmail = appState.activeOrgSettings?.support_email?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if organizationEmail.contains("@") { return organizationEmail }
    let appEmail = DHDAppConfig.supportEmail?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return appEmail.contains("@") ? appEmail : nil
  }

  private func contactSupport() {
    guard let supportEmail,
          let url = URL(string: "mailto:\(supportEmail)") else { return }
    openURL(url)
  }

  private var organizationWebsite: URL? {
    guard let raw = appState.activeOrgSettings?.website_host?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !raw.isEmpty else { return nil }
    let value = raw.contains("://") ? raw : "https://\(raw)"
    return URL(string: value)
  }

  private var privacyURL: URL {
    organizationWebsite?.appendingPathComponent("privacy")
      ?? URL(string: "https://www.apple.com/legal/privacy/")!
  }

  private var termsURL: URL {
    organizationWebsite?.appendingPathComponent("terms")
      ?? URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
  }

  private func diagnostic(_ event: String) {
    print("apple_subscription \(event)")
  }
}
