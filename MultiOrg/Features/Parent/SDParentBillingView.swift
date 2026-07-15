import SwiftUI

/// Parent-facing organization payment requests and Stripe-hosted Checkout.
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
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        DHDHeaderCard {
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text("Payment Requests")
                .font(.title3.weight(.semibold))
              Text(child.displayName)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.85))
            }
            Spacer()
            if isLoading { ProgressView().tint(.white) }
          }
          .foregroundStyle(.white)
        }

        DHDCard {
          VStack(alignment: .leading, spacing: 10) {
            Label("Secure payments through Stripe", systemImage: "lock.shield")
              .font(.headline)
            Text("Pay Now is available only when your organization link allows payment for this child.")
              .font(.footnote)
              .foregroundStyle(DHDTheme.textSecondary)
          }
        }

        if let errorText {
          DHDCard {
            VStack(alignment: .leading, spacing: 10) {
              Text(errorText).foregroundStyle(.red)
              Button("Try Again") { Task { await reload() } }
                .buttonStyle(.bordered)
            }
          }
        } else if requestState.requests.isEmpty, !isLoading {
          ContentUnavailableView(
            "No Payment Requests",
            systemImage: "doc.text",
            description: Text("This organization has not requested a payment for \(child.displayName).")
          )
          .frame(maxWidth: .infinity, minHeight: 220)
        } else {
          ForEach(requestState.requests) { request in
            paymentRequestCard(request)
          }
        }
      }
      .padding(DHDTheme.pagePadding)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(DHDTheme.pageBackground)
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
    guard let supabase = appState.supabase else { return }
    guard checkoutState.beginOpening(requestId: request.id) else { return }
    do {
      let response = try await supabase.createPaymentRequestCheckout(paymentRequestId: request.id)
      guard response.checkout.payment_request_id == request.id else {
        checkoutState.fail(requestId: request.id, message: "Checkout returned the wrong payment request. Refresh and try again.")
        return
      }
      let wasOpened: Bool = await withCheckedContinuation { continuation in
        openURL(response.checkout.url) { accepted in
          continuation.resume(returning: accepted)
        }
      }
      if !wasOpened {
        checkoutState.fail(requestId: request.id, message: "Stripe Checkout could not be opened in the system browser.")
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
