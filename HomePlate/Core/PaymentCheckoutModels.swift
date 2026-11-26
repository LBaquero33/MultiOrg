import Foundation

struct SDPaymentCheckout: Decodable, Equatable, Sendable {
  let payment_request_id: UUID
  let session_id: String
  let url: URL
  let expires_at: Date
  let reused: Bool

  private enum CodingKeys: String, CodingKey {
    case payment_request_id
    case session_id
    case url
    case expires_at
    case reused
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    payment_request_id = try container.decode(UUID.self, forKey: .payment_request_id)
    session_id = try container.decode(String.self, forKey: .session_id)
    url = try container.decode(URL.self, forKey: .url)
    reused = try container.decode(Bool.self, forKey: .reused)
    let timestamp = try container.decode(String.self, forKey: .expires_at)
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let wholeSeconds = ISO8601DateFormatter()
    wholeSeconds.formatOptions = [.withInternetDateTime]
    guard let date = fractional.date(from: timestamp) ?? wholeSeconds.date(from: timestamp) else {
      throw DecodingError.dataCorruptedError(
        forKey: .expires_at,
        in: container,
        debugDescription: "Expected an ISO-8601 Checkout expiration timestamp."
      )
    }
    expires_at = date
  }
}
struct SDPaymentCheckoutResponse: Decodable, Equatable, Sendable {
  let checkout: SDPaymentCheckout
}

enum SDOrganizationCheckoutDestination: Equatable, Sendable {
  case browser(URL)
  case alreadyPaid
}

struct SDSquarePaymentCheckoutResponse: Decodable, Sendable {
  let status: String?
  let url: URL?

  func destination(expectedMode: String) throws -> SDOrganizationCheckoutDestination {
    let expectedHost: String
    switch expectedMode {
    case "sandbox": expectedHost = "sandbox.square.link"
    case "production": expectedHost = "square.link"
    default: throw SDOrganizationCheckoutError.unavailable
    }
    if status == "paid", url == nil { return .alreadyPaid }
    guard let url, let parsed = URLComponents(url: url, resolvingAgainstBaseURL: false),
          parsed.scheme == "https", parsed.host == expectedHost, parsed.user == nil,
          parsed.password == nil, parsed.port == nil, parsed.query == nil, parsed.fragment == nil,
          parsed.percentEncodedPath.range(of: #"^/u/[A-Za-z0-9_-]{1,127}$"#, options: .regularExpression) != nil
    else { throw SDOrganizationCheckoutError.unavailable }
    return .browser(url)
  }
}

struct SDOrganizationPaymentTier: Decodable, Equatable, Identifiable, Sendable {
  let id: UUID
  let version_id: UUID
  let name: String
  let amount_cents: Int
  let currency: String
  let checkout_provider: String?
}

struct SDOrganizationPaymentTierList: Decodable, Sendable {
  let tiers: [SDOrganizationPaymentTier]
}

struct SDOrganizationTierPurchase: Decodable, Equatable, Sendable {
  let id: UUID
  let status: String
  let provider: String?
  let provider_mode: String?
  let refund_state: String?
}

struct SDOrganizationTierCheckout: Decodable, Sendable {
  let purchase: SDOrganizationTierPurchase
  let checkout_url: URL?
  let previous_quote: SDOrganizationTierPreviousQuote?

  func destination(expectedProvider: String?) throws -> SDOrganizationCheckoutDestination {
    guard previous_quote == nil else { throw SDOrganizationCheckoutError.unavailable }
    if expectedProvider == "square" && purchase.provider != "square" {
      throw SDOrganizationCheckoutError.unavailable
    }
    if purchase.provider == "square" {
      guard let mode = purchase.provider_mode else { throw SDOrganizationCheckoutError.unavailable }
      return try SDSquarePaymentCheckoutResponse(status: purchase.status, url: checkout_url)
        .destination(expectedMode: mode)
    }
    guard purchase.provider == nil || purchase.provider == "stripe" else {
      throw SDOrganizationCheckoutError.unavailable
    }
    if purchase.status == "paid" && checkout_url == nil { return .alreadyPaid }
    guard let checkout_url,
          let url = URLComponents(url: checkout_url, resolvingAgainstBaseURL: false),
          url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
          url.host == "checkout.stripe.com" || url.host == "buy.stripe.com"
    else { throw SDOrganizationCheckoutError.unavailable }
    return .browser(checkout_url)
  }
}

struct SDOrganizationTierPreviousQuote: Decodable, Sendable {
  let tier_id: UUID
}

struct SDOrganizationTierStatus: Decodable, Sendable {
  let purchase: SDOrganizationTierPurchase
}

enum SDOrganizationCheckoutError: LocalizedError {
  case unavailable

  var errorDescription: String? {
    "Secure checkout could not be verified. Refresh and try again."
  }
}

enum SDPaymentRequestPayerContext: Equatable, Sendable {
  case player
  case parent
  case management
}

enum SDPaymentRequestPayerAction: Equatable, Sendable {
  case payNow
  case unavailable(String)
  case hidden
}

enum SDPaymentRequestPayerAuthorization {
  static func action(
    for request: SDPaymentRequest,
    context: SDPaymentRequestPayerContext
  ) -> SDPaymentRequestPayerAction {
    guard context != .management else { return .hidden }
    guard request.status == .open else {
      return .unavailable(request.status == .paid
        ? "This request has been paid."
        : "This request was canceled.")
    }
    guard request.amount_cents.map({ $0 > 0 }) == true else {
      return .unavailable("This request does not have a payable amount.")
    }
    guard request.can_current_user_pay else {
      return .unavailable(context == .parent
        ? "You can view this request, but payment permission is not enabled for this child."
        : "You are not authorized to pay this request.")
    }
    return .payNow
  }
}

enum SDPaymentCheckoutState: Equatable, Sendable {
  case idle
  case opening(UUID)
  case processing(UUID)
  case failed(UUID, String)

  var requestId: UUID? {
    switch self {
    case .idle: return nil
    case .opening(let requestId), .processing(let requestId), .failed(let requestId, _):
      return requestId
    }
  }

  var isMutationInFlight: Bool {
    if case .opening = self { return true }
    return false
  }

  func isOpening(_ requestId: UUID) -> Bool {
    self == .opening(requestId)
  }

  func isProcessing(_ requestId: UUID) -> Bool {
    self == .processing(requestId)
  }

  func errorMessage(for requestId: UUID) -> String? {
    guard case .failed(let failedRequestId, let message) = self,
          failedRequestId == requestId else { return nil }
    return message
  }

  var shouldRefreshWhenActive: Bool {
    if case .processing = self { return true }
    return false
  }

  mutating func beginOpening(requestId: UUID) -> Bool {
    guard !isMutationInFlight else { return false }
    self = .opening(requestId)
    return true
  }

  mutating func browserOpened(requestId: UUID) {
    guard self == .opening(requestId) else { return }
    self = .processing(requestId)
  }

  mutating func fail(requestId: UUID, message: String) {
    self = .failed(requestId, message)
  }

  mutating func reconcile(with requests: [SDPaymentRequest]) {
    guard let requestId else { return }
    guard let request = requests.first(where: { $0.id == requestId }) else {
      self = .idle
      return
    }
    if request.status == .paid || request.status == .canceled {
      self = .idle
    } else if case .processing = self {
      self = .processing(requestId)
    }
  }
}
