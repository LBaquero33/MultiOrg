import Foundation

struct SDParentInvite: Identifiable, Decodable, Equatable {
  let id: UUID
  let email_norm: String
  let child_id: UUID
  let invited_by: UUID?
  let relationship: String?
  let accepted_at: Date?
  let parent_id: UUID?
  let created_at: Date?
}

struct SDParentChildLink: Identifiable, Decodable, Equatable {
  var id: String { "\(org_id?.uuidString ?? "legacy")|\(parent_id.uuidString)|\(child_id.uuidString)" }
  let org_id: UUID?
  let parent_id: UUID
  let child_id: UUID
  let relationship: String?
  let can_book: Bool
  let can_pay: Bool
  let created_at: Date?
  let created_by: UUID?
}

enum SDPaymentRequestStatus: String, Codable, CaseIterable, Sendable {
  case open
  case canceled
  case paid
}

enum SDPaymentRequestAuthorizationSource: String, Decodable, Equatable, Sendable {
  case organizationMembership = "organization_membership"
  case platformSupport = "platform_support"
}

struct SDPaymentRequestEligiblePlayersResponse: Decodable, Equatable, Sendable {
  let players: [SDPaymentRequestEligiblePlayer]
  let authorization_source: SDPaymentRequestAuthorizationSource
}

struct SDPaymentRequestEligiblePlayer: Decodable, Identifiable, Hashable, Sendable {
  let userId: UUID
  let organizationId: UUID
  let role: String
  let status: String
  let createdAt: String?
  let createdBy: UUID?
  let username: String?
  let email: String?
  let fullName: String?
  let profileRole: String?

  var id: UUID { userId }

  var displayName: String {
    if let fullName {
      let value = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
      if !value.isEmpty { return value }
    }
    if let username {
      let value = username.trimmingCharacters(in: .whitespacesAndNewlines)
      if !value.isEmpty { return "@\(value)" }
    }
    if let email {
      let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
      if !value.isEmpty { return value }
    }
    return "Player \(userId.uuidString.lowercased().suffix(6))"
  }

  private enum CodingKeys: String, CodingKey {
    case userId = "user_id"
    case organizationId = "org_id"
    case role
    case status
    case createdAt = "created_at"
    case createdBy = "created_by"
    case username
    case email
    case fullName = "full_name"
    case profileRole = "profile_role"
  }
}

enum SDPaymentRequestEligiblePlayersContractError: LocalizedError, Equatable {
  case invalidResponse

  var errorDescription: String? {
    "Eligible players could not be read from the server response. Please try again."
  }
}

enum SDPaymentRequestEligiblePlayersContract {
  static func decode(_ data: Data) throws -> SDPaymentRequestEligiblePlayersResponse {
    do {
      return try JSONDecoder().decode(SDPaymentRequestEligiblePlayersResponse.self, from: data)
    } catch {
      throw SDPaymentRequestEligiblePlayersContractError.invalidResponse
    }
  }
}

struct SDPaymentRequest: Identifiable, Decodable, Equatable, Sendable {
  let id: UUID
  let request_batch_id: UUID?
  let org_id: UUID
  let player_id: UUID
  let player_name: String?
  let created_by: UUID
  let title: String
  let description: String?
  let amount_cents: Int?
  let currency: String
  let due_date: String?
  let status: SDPaymentRequestStatus
  let created_at: Date?
  let updated_at: Date?
  let can_current_user_pay: Bool

  var money: SDMoney? {
    amount_cents.map { SDMoney(minorUnits: $0, currency: currency) }
  }
}

extension SDPaymentRequest {
  private enum CodingKeys: String, CodingKey {
    case id
    case request_batch_id
    case org_id
    case player_id
    case player_name
    case created_by
    case title
    case description
    case amount_cents
    case currency
    case due_date
    case status
    case created_at
    case updated_at
    case can_current_user_pay
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    request_batch_id = try container.decodeIfPresent(UUID.self, forKey: .request_batch_id)
    org_id = try container.decode(UUID.self, forKey: .org_id)
    player_id = try container.decode(UUID.self, forKey: .player_id)
    player_name = try container.decodeIfPresent(String.self, forKey: .player_name)
    created_by = try container.decode(UUID.self, forKey: .created_by)
    title = try container.decode(String.self, forKey: .title)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    amount_cents = try container.decodeIfPresent(Int.self, forKey: .amount_cents)
    currency = try container.decode(String.self, forKey: .currency)
    due_date = try container.decodeIfPresent(String.self, forKey: .due_date)
    status = try container.decode(SDPaymentRequestStatus.self, forKey: .status)
    created_at = try Self.decodeTimestampIfPresent(from: container, forKey: .created_at)
    updated_at = try Self.decodeTimestampIfPresent(from: container, forKey: .updated_at)
    can_current_user_pay = try container.decode(Bool.self, forKey: .can_current_user_pay)
  }

  private static func decodeTimestampIfPresent(
    from container: KeyedDecodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) throws -> Date? {
    guard let value = try container.decodeIfPresent(String.self, forKey: key) else { return nil }

    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) { return date }

    let wholeSeconds = ISO8601DateFormatter()
    wholeSeconds.formatOptions = [.withInternetDateTime]
    if let date = wholeSeconds.date(from: value) { return date }

    throw DecodingError.dataCorruptedError(
      forKey: key,
      in: container,
      debugDescription: "Expected an ISO-8601 timestamp, received \(value)."
    )
  }
}

struct SDPaymentRequestCreateResponse: Decodable, Equatable, Sendable {
  let requests: [SDPaymentRequest]
  let created_count: Int
  let reused: Bool
  let authorization_source: SDPaymentRequestAuthorizationSource
}

struct SDPaymentRequestListResponse: Decodable, Equatable, Sendable {
  let requests: [SDPaymentRequest]
  let authorization_source: SDPaymentRequestAuthorizationSource
}

struct SDPaymentRequestSingleResponse: Decodable, Equatable, Sendable {
  let request: SDPaymentRequest
  let authorization_source: SDPaymentRequestAuthorizationSource
}

struct SDEdgeFunctionErrorResponse: Decodable, Equatable, Sendable {
  let error: String
  let message: String?
}

struct SDEdgeFunctionHTTPError: LocalizedError, Equatable, Sendable {
  let statusCode: Int
  let code: String
  let message: String

  var errorDescription: String? { message }

  static func decode(statusCode: Int, data: Data) -> SDEdgeFunctionHTTPError {
    do {
      let payload = try JSONDecoder().decode(SDEdgeFunctionErrorResponse.self, from: data)
      let cleanedMessage = payload.message?.trimmingCharacters(in: .whitespacesAndNewlines)
      let readableMessage: String
      if let cleanedMessage, !cleanedMessage.isEmpty {
        readableMessage = cleanedMessage
      } else {
        readableMessage = payload.error.replacingOccurrences(of: "_", with: " ").capitalized + "."
      }
      return SDEdgeFunctionHTTPError(
        statusCode: statusCode,
        code: payload.error,
        message: readableMessage
      )
    } catch {
      return SDEdgeFunctionHTTPError(
        statusCode: statusCode,
        code: "invalid_error_response",
        message: "The server rejected the request (HTTP \(statusCode))."
      )
    }
  }
}

struct SDMoney: Equatable, Sendable {
  let minorUnits: Int
  let currency: String

  func formatted(locale: Locale = .current) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .currency
    formatter.currencyCode = currency.uppercased()
    let amount = Decimal(minorUnits) / Decimal(100)
    return formatter.string(from: NSDecimalNumber(decimal: amount))
      ?? "\(currency.uppercased()) \(minorUnits)"
  }
}

struct SDPaymentRequestCreateDraft: Equatable, Sendable {
  static let maximumAmountCents = 10_000_000
  static let maximumTitleLength = 120
  static let maximumDescriptionLength = 1_000
  static let maximumPlayerCount = 100

  var selectedPlayerUserIds: Set<UUID> = []
  var title = ""
  var description = ""
  var amountDollars = ""
  var includesDueDate = false
  var dueDate = Date()
  private(set) var pendingOperation: SDPaymentRequestCreateOperation?

  var amountCents: Int? {
    Self.parseUSDCents(amountDollars)
  }

  var cleanedTitle: String {
    title.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var cleanedDescription: String? {
    let value = description.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }

  var validationError: String? {
    guard !selectedPlayerUserIds.isEmpty else { return "Select at least one player." }
    guard selectedPlayerUserIds.count <= Self.maximumPlayerCount else {
      return "Select no more than \(Self.maximumPlayerCount) players."
    }
    guard !cleanedTitle.isEmpty, cleanedTitle.count <= Self.maximumTitleLength else {
      return "Enter a title up to \(Self.maximumTitleLength) characters."
    }
    guard let amountCents, amountCents > 0 else {
      return "Enter a positive dollar amount with no more than two decimal places."
    }
    guard amountCents <= Self.maximumAmountCents else {
      return "The amount cannot exceed $100,000.00."
    }
    if let cleanedDescription, cleanedDescription.count > Self.maximumDescriptionLength {
      return "Description cannot exceed \(Self.maximumDescriptionLength) characters."
    }
    return nil
  }

  var isValid: Bool { validationError == nil }

  var pendingIdempotencyKey: UUID? { pendingOperation?.idempotencyKey }

  func dueDateString(calendar: Calendar = .current) -> String? {
    guard includesDueDate else { return nil }
    let components = calendar.dateComponents([.year, .month, .day], from: dueDate)
    guard let year = components.year, let month = components.month, let day = components.day else { return nil }
    return String(format: "%04d-%02d-%02d", year, month, day)
  }

  static func parseUSDCents(_ input: String) -> Int? {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty,
          value.range(of: "^(?:[0-9]+(?:\\.[0-9]{0,2})?|\\.[0-9]{1,2})$", options: .regularExpression) != nil else {
      return nil
    }
    let parts = value.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    let dollarsText = parts[0].isEmpty ? "0" : String(parts[0])
    guard let dollars = Int(dollarsText) else { return nil }
    let (base, overflow) = dollars.multipliedReportingOverflow(by: 100)
    guard !overflow else { return nil }
    let fraction = parts.count == 2 ? String(parts[1]) : ""
    let centsText = fraction.isEmpty ? "0" : fraction.count == 1 ? fraction + "0" : fraction
    guard let cents = Int(centsText) else { return nil }
    let (total, additionOverflow) = base.addingReportingOverflow(cents)
    return additionOverflow ? nil : total
  }

  mutating func prepareCreatePayload(
    orgId: UUID,
    calendar: Calendar = .current,
    makeUUID: () -> UUID = UUID.init
  ) -> SDPaymentRequestCreatePayload? {
    guard validationError == nil, let amountCents else { return nil }
    let material = SDPaymentRequestCreateMaterial(
      organizationId: orgId,
      playerIds: selectedPlayerUserIds.sorted { $0.uuidString < $1.uuidString },
      title: cleanedTitle,
      description: cleanedDescription,
      amountCents: amountCents,
      currency: "usd",
      dueDate: dueDateString(calendar: calendar)
    )
    let operation: SDPaymentRequestCreateOperation
    if let pendingOperation, pendingOperation.material == material {
      operation = pendingOperation
    } else {
      operation = SDPaymentRequestCreateOperation(idempotencyKey: makeUUID(), material: material)
      pendingOperation = operation
    }
    return SDPaymentRequestCreatePayload(operation: operation)
  }

  mutating func completeOperation(idempotencyKey: UUID) {
    guard pendingOperation?.idempotencyKey == idempotencyKey else { return }
    pendingOperation = nil
  }
}

struct SDPaymentRequestCreateMaterial: Equatable, Sendable {
  let organizationId: UUID
  let playerIds: [UUID]
  let title: String
  let description: String?
  let amountCents: Int
  let currency: String
  let dueDate: String?
}

struct SDPaymentRequestCreateOperation: Equatable, Sendable {
  let idempotencyKey: UUID
  let material: SDPaymentRequestCreateMaterial
}

struct SDPaymentRequestCreatePayload: Encodable, Equatable, Sendable {
  let action = "create"
  let org_id: UUID
  let player_ids: [UUID]
  let title: String
  let description: String?
  let amount_cents: Int
  let currency: String
  let due_date: String?
  let idempotency_key: UUID

  init(operation: SDPaymentRequestCreateOperation) {
    let material = operation.material
    org_id = material.organizationId
    player_ids = material.playerIds
    title = material.title
    description = material.description
    amount_cents = material.amountCents
    currency = material.currency
    due_date = material.dueDate
    idempotency_key = operation.idempotencyKey
  }
}

enum SDPaymentRequestAuthorization {
  /// Temporary MVP support override for lbaq27@gmail.com. Authorization is
  /// deliberately bound to the authenticated user's immutable UUID, not email.
  static let emergencySupportUserId = UUID(
    uuidString: "6e34ac24-0a94-4dbb-9941-3f0248493fbb"
  )!

  static func canManagePaymentRequests(
    selectedOrganizationIsActive: Bool,
    hasActiveOwnerOrAdminMembership: Bool,
    isPlatformAdmin: Bool,
    isPlatformSupportAuthorized: Bool,
    currentUserId: UUID?
  ) -> Bool {
    selectedOrganizationIsActive
      && (
        hasActiveOwnerOrAdminMembership
          || isPlatformAdmin
          || isPlatformSupportAuthorized
          || currentUserId == emergencySupportUserId
      )
  }

  static func createControlDisabledReason(
    canManagePaymentRequests: Bool,
    selectedOrganizationIsActive: Bool,
    hasMutationInFlight: Bool
  ) -> String? {
    guard selectedOrganizationIsActive else { return "No active organization selected" }
    guard canManagePaymentRequests else { return "Payment-request authorization denied" }
    if hasMutationInFlight { return "Payment request action in progress" }
    return nil
  }

  static func canSubmitCreateRequest(
    draftIsValid: Bool,
    eligibleSelectedPlayerCount: Int,
    isSubmitting: Bool
  ) -> Bool {
    draftIsValid
      && eligibleSelectedPlayerCount > 0
      && !isSubmitting
  }
}

enum SDPaymentRequestManagementLoadAction: String, Hashable, Sendable {
  case listManage = "list_manage"
  case listEligiblePlayers = "list_eligible_players"
}

@MainActor
enum SDPaymentRequestManagementLoadCoordinator {
  static func load(
    listManage: @escaping @MainActor () async -> Void,
    listEligiblePlayers: @escaping @MainActor () async -> Void
  ) async {
    async let managedRequests: Void = listManage()
    async let eligiblePlayers: Void = listEligiblePlayers()
    _ = await (managedRequests, eligiblePlayers)
  }
}

@MainActor
enum SDPaymentRequestSheetRosterLoadCoordinator {
  static func load(
    organizationId: UUID?,
    listEligiblePlayers: @escaping @MainActor () async -> Void
  ) async {
    guard organizationId != nil else { return }
    await listEligiblePlayers()
  }

  static func loadResponse(
    organizationId: UUID?,
    listEligiblePlayers: @escaping @MainActor (UUID) async throws
      -> SDPaymentRequestEligiblePlayersResponse
  ) async throws -> SDPaymentRequestEligiblePlayersResponse? {
    guard let organizationId else { return nil }
    return try await listEligiblePlayers(organizationId)
  }
}

enum SDPaymentRequestSheetRosterDiscardReason: String, Equatable, Sendable {
  case sheetDismissed = "sheet_dismissed"
  case organizationChanged = "organization_changed"
  case requestSuperseded = "request_superseded"
}

enum SDPaymentRequestSheetRosterResponseContext {
  static func discardReason(
    sheetIsPresented: Bool,
    requestedOrganizationId: UUID,
    selectedOrganizationId: UUID?,
    responseRequestId: UUID,
    currentRequestId: UUID
  ) -> SDPaymentRequestSheetRosterDiscardReason? {
    guard sheetIsPresented else { return .sheetDismissed }
    guard requestedOrganizationId == selectedOrganizationId else {
      return .organizationChanged
    }
    guard responseRequestId == currentRequestId else { return .requestSuperseded }
    return nil
  }
}

struct SDPaymentRequestCreatePresentationState: Equatable, Sendable {
  private(set) var isPresented = false

  mutating func present() {
    isPresented = true
  }

  mutating func dismiss() {
    isPresented = false
  }

  mutating func setPresented(_ presented: Bool) {
    isPresented = presented
  }
}

struct SDPaymentRequestListState: Equatable, Sendable {
  private(set) var organizationId: UUID?
  private(set) var requests: [SDPaymentRequest] = []
  private(set) var hasLoadedResponse = false

  mutating func beginLoading(organizationId: UUID) {
    self.organizationId = organizationId
    requests = []
    hasLoadedResponse = false
  }

  mutating func apply(_ loaded: [SDPaymentRequest], organizationId: UUID) {
    guard self.organizationId == organizationId else { return }
    requests = loaded
    hasLoadedResponse = true
  }

  func hasSuccessfulResponse(for organizationId: UUID?) -> Bool {
    self.organizationId == organizationId && hasLoadedResponse
  }

  mutating func clear() {
    organizationId = nil
    requests = []
    hasLoadedResponse = false
  }
}

struct SDParentInviteRequest: Identifiable, Decodable, Equatable {
  let id: UUID
  let email_norm: String
  let child_id: UUID
  let requested_by: UUID
  let relationship: String?
  let status: String
  let coach_note: String?
  let created_at: Date?
  let updated_at: Date?
}
