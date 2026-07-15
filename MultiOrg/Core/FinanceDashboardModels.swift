import Foundation

enum FinanceAuthorizationSource: String, Decodable, Equatable, Sendable {
  case organizationMembership = "organization_membership"
  case platformSupport = "platform_support"
}

enum FinanceDateRangePreset: String, CaseIterable, Codable, Identifiable, Sendable {
  case thisWeek = "this_week"
  case thisMonth = "this_month"
  case thisQuarter = "this_quarter"
  case thisYear = "this_year"
  case custom

  var id: String { rawValue }

  var title: String {
    switch self {
    case .thisWeek: return "This Week"
    case .thisMonth: return "This Month"
    case .thisQuarter: return "This Quarter"
    case .thisYear: return "This Year"
    case .custom: return "Custom"
    }
  }
}

enum FinancePaymentRequestFilter: String, CaseIterable, Codable, Identifiable, Sendable {
  case all
  case open
  case paid
  case canceled
  case overdue

  var id: String { rawValue }
  var title: String { rawValue.capitalized }
}

struct FinanceDateRangeSelection: Equatable, Hashable, Sendable {
  var preset: FinanceDateRangePreset = .thisMonth
  var customStart = Date()
  var customEnd = Date()

  var isValid: Bool {
    preset != .custom || customStart <= customEnd
  }

  func dateString(_ date: Date, calendar: Calendar = .current) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d",
      components.year ?? 0,
      components.month ?? 0,
      components.day ?? 0
    )
  }

  var customStartString: String? {
    preset == .custom ? dateString(customStart) : nil
  }

  var customEndString: String? {
    preset == .custom ? dateString(customEnd) : nil
  }
}

struct FinanceDashboardRequest: Encodable, Equatable, Sendable {
  let action: String
  let org_id: String
  let range: String
  let start_date: String?
  let end_date: String?
  let filter: String?
  let support_mode: Bool

  init(
    action: String,
    organizationId: UUID,
    range selection: FinanceDateRangeSelection,
    filter: FinancePaymentRequestFilter? = nil,
    supportMode: Bool
  ) {
    self.action = action
    org_id = organizationId.uuidString.lowercased()
    range = selection.preset.rawValue
    start_date = selection.customStartString
    end_date = selection.customEndString
    self.filter = filter?.rawValue
    support_mode = supportMode
  }
}

struct FinanceServerDateRange: Decodable, Equatable, Sendable {
  let preset: FinanceDateRangePreset
  let start: String
  let end: String
  let start_date: String
  let end_date: String
  let timezone: String
  let timezone_source: String
}

struct FinanceOverview: Decodable, Equatable, Sendable {
  let range: FinanceServerDateRange
  let currency: String
  let gross_revenue_cents: Int
  let successful_payment_count: Int
  let refunds_cents: Int
  let provider_fees_cents: Int
  let platform_fees_cents: Int
  let net_payment_revenue_cents: Int
  let expenses_cents: Int
  let estimated_profit_cents: Int
  let open_request_balance_cents: Int
  let overdue_request_balance_cents: Int
  let open_request_count: Int
  let paid_request_count: Int
  let canceled_request_count: Int
  let average_payment_cents: Int

  func money(_ cents: Int) -> SDMoney {
    SDMoney(minorUnits: cents, currency: currency)
  }
}

struct FinanceOverviewResponse: Decodable, Equatable, Sendable {
  let overview: FinanceOverview
  let authorization_source: FinanceAuthorizationSource
}

struct FinanceRecentPayment: Identifiable, Decodable, Equatable, Sendable {
  let id: UUID
  let org_id: UUID
  let payment_request_id: UUID?
  let player_id: UUID?
  let payer_id: UUID?
  let amount_cents: Int
  let processing_fee_cents: Int?
  let platform_fee_cents: Int?
  let net_to_organization_cents: Int?
  let currency: String
  let status: String
  let provider: String
  let paid_at: String?
  let created_at: String

  var grossMoney: SDMoney { SDMoney(minorUnits: amount_cents, currency: currency) }
  var netMoney: SDMoney {
    let calculated = amount_cents - (processing_fee_cents ?? 0) - (platform_fee_cents ?? 0)
    return SDMoney(
      minorUnits: net_to_organization_cents ?? calculated,
      currency: currency
    )
  }
}

struct FinanceRecentPaymentsResponse: Decodable, Equatable, Sendable {
  let range: FinanceServerDateRange
  let payments: [FinanceRecentPayment]
  let authorization_source: FinanceAuthorizationSource
}

struct FinancePaymentRequestItem: Identifiable, Decodable, Equatable, Sendable {
  let id: UUID
  let request_batch_id: UUID?
  let org_id: UUID
  let child_id: UUID
  let title: String
  let amount_cents: Int?
  let currency: String
  let status: String
  let due_date: String?
  let paid_at: String?
  let created_at: String

  var money: SDMoney? {
    amount_cents.map { SDMoney(minorUnits: $0, currency: currency) }
  }
}

struct FinancePaymentRequestsResponse: Decodable, Equatable, Sendable {
  let range: FinanceServerDateRange
  let filter: FinancePaymentRequestFilter
  let requests: [FinancePaymentRequestItem]
  let authorization_source: FinanceAuthorizationSource
}

struct FinanceExpense: Identifiable, Decodable, Equatable, Sendable {
  let id: UUID
  let org_id: UUID
  let category: String?
  let description: String?
  let amount_cents: Int
  let currency: String
  let expense_date: String
  let vendor: String?
  let notes: String?
  let created_at: String
  let updated_at: String
  let archived_at: String?
  let archived_by: UUID?

  var money: SDMoney { SDMoney(minorUnits: amount_cents, currency: currency) }
}

struct FinanceExpensesResponse: Decodable, Equatable, Sendable {
  let range: FinanceServerDateRange
  let expenses: [FinanceExpense]
  let authorization_source: FinanceAuthorizationSource
}

enum FinanceExpenseMutationAction: String, Encodable, Sendable {
  case create = "create_expense"
  case update = "update_expense"
  case archive = "archive_expense"
}

enum FinanceExpenseClientAuthorization {
  static func canMutate(
    authorizationSource: FinanceAuthorizationSource?,
    supportMode: Bool
  ) -> Bool {
    !supportMode && authorizationSource == .organizationMembership
  }
}

struct FinanceExpenseMutationRequest: Encodable, Equatable, Sendable {
  let action: FinanceExpenseMutationAction
  let org_id: String
  let expense_id: String?
  let category: String?
  let description: String?
  let amount_cents: Int?
  let currency: String?
  let expense_date: String?
  let vendor: String?
  let notes: String?
  let support_mode: Bool

  init(
    action: FinanceExpenseMutationAction,
    organizationId: UUID,
    expenseId: UUID? = nil,
    form: FinanceExpenseFormModel? = nil,
    supportMode: Bool
  ) {
    self.action = action
    org_id = organizationId.uuidString.lowercased()
    expense_id = expenseId?.uuidString.lowercased()
    category = form?.cleanedCategory
    description = form?.cleanedDescription
    amount_cents = form?.amountCents
    currency = form?.normalizedCurrency
    expense_date = form?.expenseDateString
    vendor = form?.cleanedVendor
    notes = form?.cleanedNotes
    support_mode = supportMode
  }
}

struct FinanceExpenseMutationResponse: Decodable, Equatable, Sendable {
  let expense: FinanceExpense
  let authorization_source: FinanceAuthorizationSource
}

struct FinanceExpenseFormModel: Equatable, Sendable {
  static let maximumAmountCents = 10_000_000
  static let maximumCategoryLength = 80
  static let maximumDescriptionLength = 200
  static let maximumVendorLength = 120
  static let maximumNotesLength = 2_000

  var category = ""
  var description = ""
  var amountText = ""
  var expenseDate = Date()
  var vendor = ""
  var notes = ""
  var currency: String

  init(currency: String, expenseDate: Date = Date()) {
    self.currency = currency.lowercased()
    self.expenseDate = expenseDate
  }

  init(expense: FinanceExpense) {
    category = expense.category ?? ""
    description = expense.description ?? ""
    amountText = Self.amountText(minorUnits: expense.amount_cents)
    expenseDate = Self.date(from: expense.expense_date) ?? Date()
    vendor = expense.vendor ?? ""
    notes = expense.notes ?? ""
    currency = expense.currency.lowercased()
  }

  var cleanedCategory: String {
    category.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var cleanedDescription: String {
    description.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var cleanedVendor: String? {
    let value = vendor.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }

  var cleanedNotes: String? {
    let value = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }

  var normalizedCurrency: String { currency.lowercased() }
  var amountCents: Int? { Self.parseMinorUnits(amountText) }

  var expenseDateString: String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let components = calendar.dateComponents([.year, .month, .day], from: expenseDate)
    return String(
      format: "%04d-%02d-%02d",
      components.year ?? 0,
      components.month ?? 0,
      components.day ?? 0
    )
  }

  var validationError: String? {
    guard !cleanedCategory.isEmpty,
          cleanedCategory.count <= Self.maximumCategoryLength else {
      return "Enter a category up to \(Self.maximumCategoryLength) characters."
    }
    guard !cleanedDescription.isEmpty,
          cleanedDescription.count <= Self.maximumDescriptionLength else {
      return "Enter a description up to \(Self.maximumDescriptionLength) characters."
    }
    guard let amountCents, amountCents > 0 else {
      return "Enter a positive amount with no more than two decimal places."
    }
    guard amountCents <= Self.maximumAmountCents else {
      return "The amount cannot exceed 100,000.00."
    }
    guard normalizedCurrency.range(
      of: "^[a-z]{3}$",
      options: .regularExpression
    ) != nil else {
      return "The organization currency is invalid."
    }
    if let cleanedVendor, cleanedVendor.count > Self.maximumVendorLength {
      return "Vendor cannot exceed \(Self.maximumVendorLength) characters."
    }
    if let cleanedNotes, cleanedNotes.count > Self.maximumNotesLength {
      return "Notes cannot exceed \(Self.maximumNotesLength) characters."
    }
    return nil
  }

  var isValid: Bool { validationError == nil }

  static func parseMinorUnits(_ input: String) -> Int? {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty,
          value.range(
            of: "^(?:[0-9]+(?:\\.[0-9]{0,2})?|\\.[0-9]{1,2})$",
            options: .regularExpression
          ) != nil else {
      return nil
    }
    let parts = value.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    let wholeText = parts[0].isEmpty ? "0" : String(parts[0])
    guard let whole = Int(wholeText) else { return nil }
    let (base, overflow) = whole.multipliedReportingOverflow(by: 100)
    guard !overflow else { return nil }
    let fraction = parts.count == 2 ? String(parts[1]) : ""
    let fractionText = fraction.isEmpty ? "0" : fraction.count == 1 ? fraction + "0" : fraction
    guard let minor = Int(fractionText) else { return nil }
    let (total, additionOverflow) = base.addingReportingOverflow(minor)
    return additionOverflow ? nil : total
  }

  static func amountText(minorUnits: Int) -> String {
    let whole = minorUnits / 100
    let fraction = abs(minorUnits % 100)
    return fraction == 0 ? "\(whole)" : String(format: "%d.%02d", whole, fraction)
  }

  private static func date(from value: String) -> Date? {
    let parts = value.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return calendar.date(from: DateComponents(
      year: parts[0],
      month: parts[1],
      day: parts[2]
    ))
  }
}

struct FinanceExpenseMutationGate: Equatable, Sendable {
  private(set) var organizationId: UUID?
  private(set) var isInFlight = false
  private var token: UUID?

  mutating func begin(
    organizationId: UUID,
    token: UUID = UUID()
  ) -> UUID? {
    guard !isInFlight else { return nil }
    self.organizationId = organizationId
    self.token = token
    isInFlight = true
    return token
  }

  func accepts(organizationId: UUID, token: UUID) -> Bool {
    isInFlight && self.organizationId == organizationId && self.token == token
  }

  mutating func finish(token: UUID) {
    guard self.token == token else { return }
    isInFlight = false
    self.token = nil
  }

  mutating func clear() {
    organizationId = nil
    isInFlight = false
    token = nil
  }
}

struct FinanceRefund: Identifiable, Decodable, Equatable, Sendable {
  let id: UUID
  let org_id: UUID
  let payment_id: UUID
  let amount_cents: Int
  let currency: String
  let status: String
  let reason: String?
  let created_at: String

  var money: SDMoney { SDMoney(minorUnits: amount_cents, currency: currency) }
}

struct FinanceRefundsResponse: Decodable, Equatable, Sendable {
  let range: FinanceServerDateRange
  let refunds: [FinanceRefund]
  let authorization_source: FinanceAuthorizationSource
}

struct FinanceDashboardSnapshot: Equatable, Sendable {
  let overview: FinanceOverviewResponse
  let recentPayments: FinanceRecentPaymentsResponse
  let paymentRequests: FinancePaymentRequestsResponse
  let expenses: FinanceExpensesResponse
  let refunds: FinanceRefundsResponse
}

struct FinanceDashboardLoadContext: Equatable, Sendable {
  let organizationId: UUID
  let range: FinanceDateRangeSelection
  let requestFilter: FinancePaymentRequestFilter
  let supportMode: Bool
  let token: UUID
}

struct FinanceDashboardDataState: Equatable, Sendable {
  private(set) var context: FinanceDashboardLoadContext?
  private(set) var snapshot: FinanceDashboardSnapshot?

  mutating func begin(
    organizationId: UUID,
    range: FinanceDateRangeSelection,
    requestFilter: FinancePaymentRequestFilter,
    supportMode: Bool,
    token: UUID = UUID()
  ) -> FinanceDashboardLoadContext {
    let next = FinanceDashboardLoadContext(
      organizationId: organizationId,
      range: range,
      requestFilter: requestFilter,
      supportMode: supportMode,
      token: token
    )
    context = next
    snapshot = nil
    return next
  }

  mutating func apply(
    _ loaded: FinanceDashboardSnapshot,
    for responseContext: FinanceDashboardLoadContext
  ) -> Bool {
    guard context == responseContext else { return false }
    snapshot = loaded
    return true
  }

  mutating func clear() {
    context = nil
    snapshot = nil
  }
}
