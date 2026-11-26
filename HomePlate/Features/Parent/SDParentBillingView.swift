import SwiftUI

/// Parent-facing payment requests for real-world baseball services.
struct SDParentBillingView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase
  let child: Profile

  @State private var requestState = SDPaymentRequestListState()
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var checkoutState = SDPaymentCheckoutState.idle
  @State private var checkoutConfirmationRequest: SDPaymentRequest?

  var body: some View {
    HPListScreenLayout {
      HPWorkspaceHeader(
        "Payment Requests",
        orgLabel: activeOrganizationName,
        context: child.displayName
      ) {
        if isLoading {
          HPProgressIndicator(style: .spinner)
            .accessibilityLabel("Refreshing payment requests")
        }
      }
    } controls: {
      VStack(spacing: HP.Space.md) {
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            Label("Secure checkout", systemImage: "lock.shield")
              .font(HP.Font.headline)
              .foregroundStyle(HP.Color.text)
            Text("Pay Now is available only when your organization link allows payment for this child.")
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.textMuted)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.xs) {
            Text("About These Payments")
              .font(HP.Font.headline)
            Text("Organization payment requests cover baseball services delivered outside the app. They are separate from Apple In-App Purchase and never unlock Home Plate digital access.")
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.textMuted)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    } results: { context in
      VStack(alignment: .leading, spacing: HP.Space.md) {
        if let orgId = appState.activeOrgId {
          OrganizationTierCheckoutPanel(orgId: orgId)
            .id(orgId)
        }
        if let errorText {
          HPCard {
            HPErrorState(
              message: errorText,
              onRetry: { Task { await reload() } }
            )
          }
        } else if requestState.requests.isEmpty {
          if isLoading {
            HPCard {
              HPLoadingState(text: "Loading payment requests…")
            }
          } else {
            HPCard {
              HPEmptyState(
                title: "No Payment Requests",
                message: "This organization has not requested a payment for \(child.displayName).",
                systemImage: "doc.text"
              )
            }
          }
        } else {
          HPSectionHeader("Requests") {
            HPStatusBadge(text: "\(requestState.requests.count)", kind: .neutral)
          }
          LazyVGrid(
            columns: context.gridColumns(compact: 1, regular: 2, wide: 2),
            spacing: HP.Space.md
          ) {
            ForEach(requestState.requests) { request in
              paymentRequestCard(request)
            }
          }
        }
      }
    }
    .refreshable { await reload() }
    .task(id: loadKey) { await reload() }
    .sheet(item: $checkoutConfirmationRequest) { request in
      PaymentCheckoutConfirmationSheet(
        request: request,
        organizationName: activeOrganizationName,
        playerName: request.player_name ?? child.displayName,
        onConfirm: { Task { await openCheckout(for: request) } }
      )
    }
    .onChange(of: scenePhase) { _, next in
      guard next == .active, checkoutState.shouldRefreshWhenActive else { return }
      Task { await reload() }
    }
  }

  private var loadKey: String {
    "\(appState.activeOrgId?.uuidString ?? "none"):\(child.id.uuidString)"
  }

  private func paymentRequestCard(_ request: SDPaymentRequest) -> some View {
    PaymentRequestCard(
      request: request,
      organizationName: activeOrganizationName,
      playerName: request.player_name ?? child.displayName,
      context: .parent,
      checkoutState: checkoutState,
      onPay: { checkoutConfirmationRequest = request }
    )
  }

  private func reload() async {
    errorText = nil
    guard let supabase = appState.supabase, let orgId = appState.activeOrgId else {
      requestState.clear()
      checkoutState = .idle
      checkoutConfirmationRequest = nil
      errorText = "Choose an organization to view payment requests."
      return
    }
    if requestState.organizationId != orgId {
      checkoutState = .idle
      checkoutConfirmationRequest = nil
    }
    requestState.beginLoading(organizationId: orgId)
    isLoading = true
    defer { isLoading = false }
    do {
      let requests = try await supabase.listPaymentRequests(orgId: orgId, playerId: child.id)
      requestState.apply(requests, organizationId: orgId)
      checkoutState.reconcile(with: requests)
    } catch {
      guard requestState.organizationId == orgId else { return }
      errorText = "Payment requests could not be loaded. \(error.localizedDescription)"
    }
  }

  private func openCheckout(for request: SDPaymentRequest) async {
    guard let supabase = appState.supabase, appState.activeOrgId == request.org_id else { return }
    guard checkoutState.beginOpening(requestId: request.id) else { return }
    do {
      let destination = try await supabase.organizationPaymentCheckout(for: request)
      guard appState.activeOrgId == request.org_id else { return }
      guard case .browser(let url) = destination else {
        checkoutState.browserOpened(requestId: request.id)
        await reload()
        return
      }
      let wasOpened: Bool = await withCheckedContinuation { continuation in
        openURL(url) { accepted in
          continuation.resume(returning: accepted)
        }
      }
      if !wasOpened {
        checkoutState.fail(requestId: request.id, message: "Secure checkout could not be opened in the browser.")
      } else {
        checkoutState.browserOpened(requestId: request.id)
      }
    } catch {
      checkoutState.fail(requestId: request.id, message: error.localizedDescription)
    }
  }

  private var activeOrganizationName: String {
    if let orgId = appState.activeOrgId,
       let organization = appState.availableOrganizations.first(where: { $0.id == orgId }) {
      return organization.displayName
    }
    return appState.activeOrgSettings?.display_name ?? "Organization"
  }

}

/// One-time organization membership payments use the same server plans as web.
private struct OrganizationTierCheckoutPanel: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase
  let orgId: UUID
  @State private var tiers: [SDOrganizationPaymentTier] = []
  @State private var requestByVersion: [UUID: UUID] = [:]
  @State private var purchaseId: UUID?
  @State private var isOpening = false
  @State private var status: String?

  var body: some View {
    Group {
      if !tiers.isEmpty {
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            Text("Organization Memberships").font(HP.Font.headline)
            ForEach(tiers) { tier in
              let amount = (Double(tier.amount_cents) / 100).formatted(
                .currency(code: tier.currency.uppercased())
              )
              Button {
                Task { await checkout(tier) }
              } label: {
                Label("\(tier.name) · \(amount)", systemImage: "creditcard")
                  .font(HP.Font.body)
              }
              .disabled(isOpening)
            }
            if let status {
              Text(status)
                .font(HP.Font.caption)
                .foregroundStyle(HP.Color.textMuted)
                .accessibilityAddTraits(.updatesFrequently)
            }
          }
        }
      }
    }
    .task {
      guard let service = appState.supabase else { return }
      if let offers = try? await service.organizationPaymentTiers(orgId: orgId),
         appState.activeOrgId == orgId {
        tiers = offers
      }
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active, let purchaseId else { return }
      Task { await checkStatus(purchaseId) }
    }
  }

  private func checkout(_ tier: SDOrganizationPaymentTier) async {
    guard let service = appState.supabase, appState.activeOrgId == orgId, !isOpening else { return }
    let request = requestByVersion[tier.version_id, default: UUID()]
    requestByVersion[tier.version_id] = request
    isOpening = true
    status = nil
    defer { isOpening = false }
    do {
      let response = try await service.organizationTierCheckout(orgId: orgId, tier: tier, requestId: request)
      guard appState.activeOrgId == orgId else { return }
      let destination = try response.destination(expectedProvider: tier.checkout_provider)
      purchaseId = response.purchase.id
      switch destination {
      case .alreadyPaid:
        await checkStatus(response.purchase.id)
      case .browser(let url):
        let opened: Bool = await withCheckedContinuation { continuation in
          openURL(url) { continuation.resume(returning: $0) }
        }
        status = opened ? "Waiting for payment confirmation." : "Secure checkout could not be opened."
      }
    } catch {
      status = "Secure checkout could not be opened. Refresh and try again."
    }
  }

  private func checkStatus(_ id: UUID) async {
    guard let service = appState.supabase, appState.activeOrgId == orgId else { return }
    do {
      let purchase = try await service.organizationTierPurchase(orgId: orgId, purchaseId: id)
      guard appState.activeOrgId == orgId, purchaseId == id else { return }
      if purchase.refund_state == "refunded" {
        status = "Refund confirmed."
      } else {
        switch purchase.status {
        case "paid": status = "Payment confirmed."
        case "expired", "failed": status = "Checkout ended without a confirmed payment."
        default: status = "Waiting for payment confirmation."
        }
      }
    } catch {
      status = "Payment status is unavailable. Check again when you return."
    }
  }
}
