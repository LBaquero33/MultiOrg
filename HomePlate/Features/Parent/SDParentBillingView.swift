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
        if let orgId = appState.activeOrgId, let userId = appState.myProfile?.id {
          OrganizationTierCheckoutPanel(
            orgId: orgId, userId: userId, authorizationKey: appState.activeOrgAuthorizationKey
          )
          .id(appState.activeOrgAuthorizationKey)
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
struct OrganizationTierCheckoutPanel: View {
  private struct SavedCheckout {
    let purchaseId: UUID
    let requestKey: SDOrganizationTierRequestKey
    let url: URL
  }

  @EnvironmentObject private var appState: AppState
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase
  let orgId: UUID
  let userId: UUID
  let authorizationKey: String
  @State private var tiers: [SDOrganizationPaymentTier] = []
  @State private var requests: [SDOrganizationTierRequestKey: UUID] = [:]
  @State private var previousOffer: SDOrganizationPaymentTier?
  @State private var savedCheckout: SavedCheckout?
  @State private var purchaseId: UUID?
  @State private var purchaseRequest: SDOrganizationTierRequestKey?
  @State private var isOpening = false
  @State private var status: String?

  private var hasSameAuthorization: Bool {
    appState.activeOrgId == orgId && appState.myProfile?.id == userId &&
      appState.activeOrgAuthorizationKey == authorizationKey
  }

  var body: some View {
    Group {
      if !tiers.isEmpty || previousOffer != nil || savedCheckout != nil || status != nil {
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            Text("Organization Memberships").font(HP.Font.headline)
            if let previousOffer {
              Text("You have an existing checkout at the previous price.")
                .font(HP.Font.caption)
              Button("Continue previous checkout for \(amount(previousOffer))") {
                Task { await checkout(previousOffer) }
              }
              .disabled(isOpening)
            }
            if let savedCheckout {
              Button("Continue existing Stripe checkout") {
                Task { await openSavedCheckout(savedCheckout) }
              }
              .disabled(isOpening)
            }
            ForEach(tiers) { tier in
              Button {
                Task { await checkout(tier) }
              } label: {
                Label("\(tier.name) · \(amount(tier))", systemImage: "creditcard")
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
    .task { await loadOffers() }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active, let purchaseId else { return }
      Task { await checkStatus(purchaseId) }
    }
  }

  private func amount(_ tier: SDOrganizationPaymentTier) -> String {
    (Double(tier.amount_cents) / 100).formatted(.currency(code: tier.currency.uppercased()))
  }

  private func loadOffers() async {
    guard hasSameAuthorization, let service = appState.supabase else { return }
    if let offers = try? await service.organizationPaymentTiers(orgId: orgId),
       hasSameAuthorization, !Task.isCancelled {
      tiers = offers
    }
  }

  private func checkout(_ tier: SDOrganizationPaymentTier) async {
    guard hasSameAuthorization, let service = appState.supabase, !isOpening else { return }
    let key = SDOrganizationTierRequestKey(
      userId: userId, orgId: orgId, tierId: tier.id, versionId: tier.version_id
    )
    let isSquare = tier.checkout_provider == "square"
    let savedRequest = isSquare
      ? UserDefaults.standard.string(forKey: key.storageKey).flatMap { UUID(uuidString: $0) }
      : nil
    let request = requests[key] ?? savedRequest ?? UUID()
    requests[key] = request
    if isSquare { UserDefaults.standard.set(request.uuidString, forKey: key.storageKey) }
    isOpening = true
    status = nil
    previousOffer = nil
    savedCheckout = nil
    purchaseId = nil
    purchaseRequest = nil
    defer { isOpening = false }
    do {
      let response = try await service.organizationTierCheckout(orgId: orgId, tier: tier, requestId: request)
      guard hasSameAuthorization, !Task.isCancelled else { return }
      if let quote = try response.previousOffer(for: tier) {
        previousOffer = quote
        return
      }
      if let url = try response.existingStripeDestination(for: tier) {
        savedCheckout = SavedCheckout(purchaseId: response.purchase.id, requestKey: key, url: url)
        return
      }
      let destination = try response.destination(expectedProvider: tier.checkout_provider)
      purchaseId = response.purchase.id
      purchaseRequest = key
      switch destination {
      case .alreadyPaid:
        await checkStatus(response.purchase.id)
      case .browser(let url):
        await showCheckout(url)
      }
    } catch {
      guard hasSameAuthorization, !Task.isCancelled else { return }
      switch (error as? SDEdgeFunctionHTTPError)?.code {
      case "payment_tier_price_changed":
        clearRequest(key)
        status = "The price changed. Review the updated option before continuing."
        await loadOffers()
      case "payment_tier_checkout_expired", "payment_tier_previous_checkout_unavailable":
        clearRequest(key)
        status = "The previous checkout is closed. Select the current offer to start again."
        await loadOffers()
      case "payment_tier_prior_checkout_conflict", "payment_tier_checkout_review_required":
        status = "An earlier checkout needs review. Contact your organization."
      default:
        status = "Secure checkout could not be opened. Try again."
      }
    }
  }

  private func openSavedCheckout(_ checkout: SavedCheckout) async {
    guard hasSameAuthorization, !isOpening else { return }
    isOpening = true
    defer { isOpening = false }
    savedCheckout = nil
    purchaseId = checkout.purchaseId
    purchaseRequest = checkout.requestKey
    await showCheckout(checkout.url)
  }

  private func showCheckout(_ url: URL) async {
    guard hasSameAuthorization, !Task.isCancelled else { return }
    let opened: Bool = await withCheckedContinuation { continuation in
      openURL(url) { continuation.resume(returning: $0) }
    }
    guard hasSameAuthorization, !Task.isCancelled else { return }
    status = opened ? "Waiting for payment confirmation." : "Secure checkout could not be opened."
  }

  private func clearRequest(_ key: SDOrganizationTierRequestKey) {
    requests[key] = nil
    UserDefaults.standard.removeObject(forKey: key.storageKey)
  }

  private func checkStatus(_ id: UUID) async {
    guard hasSameAuthorization, let service = appState.supabase else { return }
    do {
      let purchase = try await service.organizationTierPurchase(orgId: orgId, purchaseId: id)
      guard hasSameAuthorization, purchaseId == id, !Task.isCancelled else { return }
      if ["expired", "failed"].contains(purchase.status), let purchaseRequest {
        clearRequest(purchaseRequest)
      }
      if purchase.hasConfirmedRefund {
        status = "Refund confirmed."
      } else {
        switch purchase.status {
        case "paid": status = "Payment confirmed."
        case "expired", "failed": status = "Checkout ended without a confirmed payment."
        default: status = "Waiting for payment confirmation."
        }
      }
    } catch {
      guard hasSameAuthorization, purchaseId == id, !Task.isCancelled else { return }
      status = "Payment status is unavailable. Check again when you return."
    }
  }
}
