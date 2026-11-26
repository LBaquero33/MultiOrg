import Foundation
import Testing
@testable import HomePlate

@Suite("Payment-request Checkout")
struct PaymentCheckoutTests {
  private let requestId = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!
  private let orgId = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
  private let playerId = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
  private let creatorId = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

  private func request(
    status: SDPaymentRequestStatus = .open,
    canPay: Bool = true,
    amountCents: Int? = 1_234
  ) -> SDPaymentRequest {
    SDPaymentRequest(
      id: requestId,
      request_batch_id: nil,
      org_id: orgId,
      player_id: playerId,
      player_name: "Test Player",
      created_by: creatorId,
      title: "Team fee",
      description: "One-time request",
      amount_cents: amountCents,
      currency: "usd",
      due_date: "2026-08-01",
      status: status,
      created_at: nil,
      updated_at: nil,
      can_current_user_pay: canPay
    )
  }

  @Test("Exact Checkout success response decodes")
  func successContractDecodes() throws {
    let json = """
      {
        "checkout": {
          "payment_request_id": "77777777-7777-4777-8777-777777777777",
          "session_id": "cs_test_homeplate",
          "url": "https://checkout.stripe.com/c/pay/test",
          "expires_at": "2026-07-14T18:00:00.123Z",
          "reused": false
        }
      }
      """
    let response = try JSONDecoder().decode(SDPaymentCheckoutResponse.self, from: Data(json.utf8))
    #expect(response.checkout.payment_request_id == requestId)
    #expect(response.checkout.session_id == "cs_test_homeplate")
    #expect(response.checkout.url.host == "checkout.stripe.com")
    #expect(!response.checkout.reused)
  }

  @Test("Malformed Checkout success response fails closed")
  func malformedSuccessFailsClosed() {
    let json = """
      {"checkout":{"payment_request_id":"77777777-7777-4777-8777-777777777777","url":"https://checkout.stripe.com/test"}}
      """
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(SDPaymentCheckoutResponse.self, from: Data(json.utf8))
    }
  }

  @Test("One-time memberships require the selected provider and exact hosted checkout")
  func organizationTierCheckoutDestination() throws {
    let id = "77777777-7777-4777-8777-777777777777"
    func decode(provider: String, mode: String, url: String) throws -> SDOrganizationTierCheckout {
      try JSONDecoder().decode(SDOrganizationTierCheckout.self, from: Data("""
        {"purchase":{"id":"\(id)","status":"pending","provider":"\(provider)","provider_mode":"\(mode)"},"checkout_url":"\(url)"}
        """.utf8))
    }
    let square = try decode(provider: "square", mode: "sandbox", url: "https://sandbox.square.link/u/Tier")
    #expect(try square.destination(expectedProvider: "square") == .browser(URL(string: "https://sandbox.square.link/u/Tier")!))
    let incorrectMode = try decode(provider: "square", mode: "production", url: "https://sandbox.square.link/u/Tier")
    #expect(throws: SDOrganizationCheckoutError.self) { try incorrectMode.destination(expectedProvider: "square") }
    let stripe = try decode(provider: "stripe", mode: "test", url: "https://checkout.stripe.com/c/pay/Tier")
    #expect(try stripe.destination(expectedProvider: nil) == .browser(URL(string: "https://checkout.stripe.com/c/pay/Tier")!))
    #expect(throws: SDOrganizationCheckoutError.self) { try stripe.destination(expectedProvider: "square") }
  }

  @Test("Square checkout validates the precise host and route")
  func squareCheckoutDestination() throws {
    let ok = try JSONDecoder().decode(SDSquarePaymentCheckoutResponse.self, from: Data(
      #"{"url":"https://sandbox.square.link/u/Test123"}"#.utf8
    ))
    #expect(try ok.destination(expectedMode: "sandbox") == .browser(URL(string: "https://sandbox.square.link/u/Test123")!))
    #expect(throws: SDOrganizationCheckoutError.self) { try ok.destination(expectedMode: "production") }
    let paid = try JSONDecoder().decode(SDSquarePaymentCheckoutResponse.self, from: Data(#"{"status":"paid"}"#.utf8))
    #expect(try paid.destination(expectedMode: "production") == .alreadyPaid)
    let redirected = try JSONDecoder().decode(SDSquarePaymentCheckoutResponse.self, from: Data(
      #"{"url":"https://sandbox.square.link/u/Test123?redirect=example.com"}"#.utf8
    ))
    #expect(throws: SDOrganizationCheckoutError.self) { try redirected.destination(expectedMode: "sandbox") }
  }

  @Test("Player and authorized parent see Pay Now")
  func authorizedPayers() {
    #expect(SDPaymentRequestPayerAuthorization.action(for: request(), context: .player) == .payNow)
    #expect(SDPaymentRequestPayerAuthorization.action(for: request(), context: .parent) == .payNow)
  }

  @Test("Parent without can_pay sees a readable explanation")
  func parentWithoutPaymentPermission() {
    #expect(
      SDPaymentRequestPayerAuthorization.action(for: request(canPay: false), context: .parent) ==
        .unavailable("You can view this request, but payment permission is not enabled for this child.")
    )
  }

  @Test("Management authority never implies payer authority")
  func managementDoesNotImplyPayNow() {
    #expect(SDPaymentRequestPayerAuthorization.action(for: request(), context: .management) == .hidden)
  }

  @Test("Paid and canceled requests remove Pay Now")
  func terminalRequestsAreNotPayable() {
    #expect(
      SDPaymentRequestPayerAuthorization.action(for: request(status: .paid), context: .player) ==
        .unavailable("This request has been paid.")
    )
    #expect(
      SDPaymentRequestPayerAuthorization.action(for: request(status: .canceled), context: .parent) ==
        .unavailable("This request was canceled.")
    )
  }

  @Test("Missing legacy amount is not payable")
  func missingAmountIsNotPayable() {
    #expect(
      SDPaymentRequestPayerAuthorization.action(
        for: request(amountCents: nil),
        context: .player
      ) == .unavailable("This request does not have a payable amount.")
    )
  }

  @Test("Checkout state prevents button double taps")
  func doubleTapGuard() {
    var state = SDPaymentCheckoutState.idle
    let didBegin = state.beginOpening(requestId: requestId)
    let didBeginAgain = state.beginOpening(requestId: UUID())
    #expect(didBegin)
    #expect(!didBeginAgain)
    #expect(state.isOpening(requestId))
  }

  @Test("Browser opening becomes processing, not paid")
  func redirectDoesNotMarkPaid() {
    var state = SDPaymentCheckoutState.idle
    let didBegin = state.beginOpening(requestId: requestId)
    #expect(didBegin)
    state.browserOpened(requestId: requestId)
    #expect(state.isProcessing(requestId))
    #expect(state.shouldRefreshWhenActive)
    state.reconcile(with: [request(status: .open)])
    #expect(state.isProcessing(requestId))
  }

  @Test("Only backend paid status completes processing presentation")
  func backendPaidStatusCompletesProcessing() {
    var state = SDPaymentCheckoutState.opening(requestId)
    state.browserOpened(requestId: requestId)
    state.reconcile(with: [request(status: .paid)])
    #expect(state == .idle)
  }

  @Test("Browser-open and backend failures remain readable")
  func failurePresentation() {
    var state = SDPaymentCheckoutState.opening(requestId)
    state.fail(requestId: requestId, message: "Stripe Checkout could not be opened.")
    #expect(state.errorMessage(for: requestId) == "Stripe Checkout could not be opened.")
    #expect(!state.isMutationInFlight)
  }

  @Test("Organization/request refresh removes stale Checkout state")
  func staleRequestClearsCheckoutState() {
    var state = SDPaymentCheckoutState.processing(requestId)
    state.reconcile(with: [])
    #expect(state == .idle)
  }
}
