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
    HPStateScreenLayout(widthMode: .compact) { context in
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.md) {
          Text("Previous Apple purchases").font(HP.Font.title)
          subscriptionStatus
          recoveryActions(context)
          legalLinks(context)

          Rectangle()
            .fill(HP.Color.border)
            .frame(height: 1)
            .accessibilityHidden(true)

          HPButton(
            title: "Sign Out",
            systemImage: "rectangle.portrait.and.arrow.right",
            variant: .destructive,
            size: .md,
            fullWidth: true
          ) {
            Task { await appState.signOut() }
          }
        }
      }
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
      HPCard(style: .flat) {
        HPErrorState(title: "Subscription unavailable", message: contextError)
      }
    } else if let accessMessage {
      statusRow("Active", message: accessMessage, kind: .success)
    } else {
      switch store.state {
      case .idle:
        statusRow("Checking", message: "Checking previous Apple purchases…", kind: .neutral, showsProgress: true)
      case .loadingProduct:
        statusRow("Loading", message: "Loading purchase history…", kind: .neutral, showsProgress: true)
      case .ready:
        statusRow("Ready", message: "Ready to restore an existing purchase.", kind: .info)
      case .purchasing:
        statusRow("Purchasing", message: "Waiting for Apple to complete the purchase…", kind: .info, showsProgress: true)
      case .pending:
        statusRow("Pending", message: "Apple is processing this purchase. It will remain recoverable until access is updated.", kind: .warning, showsProgress: true)
      case .recovering:
        statusRow("Restoring", message: "Looking for an existing Apple purchase…", kind: .info, showsProgress: true)
      case .synchronizing:
        statusRow("Verifying", message: "Updating Home Plate access…", kind: .info, showsProgress: true)
      case .active:
        statusRow("Active", message: "Your previous purchase has been verified.", kind: .success)
      case .canceled:
        statusRow("Canceled", message: "Purchase canceled. No charge or access change was made.", kind: .neutral)
      case .failed(let failure):
        HPCard(style: .flat) {
          HPErrorState(title: "Subscription needs attention", message: failure.message)
        }
      }
    }
  }

  private func statusRow(
    _ label: String,
    message: String,
    kind: HPStatusKind,
    showsProgress: Bool = false
  ) -> some View {
    HPCard(style: .flat) {
      VStack(alignment: .leading, spacing: HP.Space.xs) {
        HStack(spacing: HP.Space.xs) {
          if showsProgress {
            ProgressView().controlSize(.small)
          }
          HPStatusBadge(text: label, kind: kind)
        }
        Text(message)
          .font(HP.Font.callout)
          .foregroundStyle(HP.Color.text)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(label). \(message)")
  }

  @ViewBuilder
  private func recoveryActions(_ context: HPScreenLayoutContext) -> some View {
    let layout = context.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: HP.Space.xs))
      : AnyLayout(HStackLayout(spacing: HP.Space.xs))

    layout {
      HPButton(
        title: "Restore Purchases",
        systemImage: "arrow.clockwise",
        variant: .tertiary,
        size: .md,
        fullWidth: true
      ) {
        Task { await restore() }
      }
      .disabled(isWorking)

      HPButton(
        title: "Retry Verification",
        systemImage: "arrow.triangle.2.circlepath",
        variant: .secondary,
        size: .md,
        fullWidth: true
      ) {
        Task { await retryVerification() }
      }
      .disabled(isWorking)
    }

    layout {
      HPButton(
        title: "Check previous purchase",
        systemImage: "checkmark.shield",
        variant: .secondary,
        size: .md,
        fullWidth: true
      ) {
        Task { await refreshAccess() }
      }
      .disabled(isWorking)

      HPButton(
        title: "Contact Support",
        systemImage: "envelope",
        variant: .tertiary,
        size: .md,
        fullWidth: true,
        action: contactSupport
      )
      .disabled(supportEmail == nil)
    }
  }

  @ViewBuilder
  private func legalLinks(_ context: HPScreenLayoutContext) -> some View {
    let layout = context.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.xs))
      : AnyLayout(HStackLayout(spacing: HP.Space.md))

    layout {
      Link("Privacy", destination: privacyURL)
        .font(HP.Font.callout.weight(.semibold))
        .foregroundStyle(HP.Color.textTertiary)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      Link("Terms", destination: termsURL)
        .font(HP.Font.callout.weight(.semibold))
        .foregroundStyle(HP.Color.textTertiary)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
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
        accessMessage = "Your previous purchase has been verified."
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
          accessMessage = "Your previous purchase has been verified."
          contextError = nil
        } else {
          contextError = "No active historical entitlement was found for this player."
        }
      } else {
        let entitlement = try await supabase.fetchAccessEntitlement(userId: playerId)
        if entitlement?.is_active == true {
          accessMessage = "Your previous purchase has been verified."
          contextError = nil
        } else {
          contextError = "No active historical entitlement was found for this player."
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
