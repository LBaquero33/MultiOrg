import Foundation
import Testing
@testable import HomePlate

@Suite("Finance expense management")
struct ExpenseManagementTests {
  private let orgId = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
  private let otherOrgId = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!

  @Test("Amount input converts exactly to integer cents")
  func integerCentParsing() {
    #expect(FinanceExpenseFormModel.parseMinorUnits("12") == 1_200)
    #expect(FinanceExpenseFormModel.parseMinorUnits("12.3") == 1_230)
    #expect(FinanceExpenseFormModel.parseMinorUnits("12.34") == 1_234)
    #expect(FinanceExpenseFormModel.parseMinorUnits(".05") == 5)
    #expect(FinanceExpenseFormModel.parseMinorUnits("12.345") == nil)
    #expect(FinanceExpenseFormModel.parseMinorUnits("-1") == nil)
    #expect(FinanceExpenseFormModel.parseMinorUnits("1,000") == nil)
    #expect(FinanceExpenseFormModel.amountText(minorUnits: 1_234) == "12.34")
  }

  @Test("Expense form enforces required fields and bounded optional text")
  func formValidation() {
    var form = validForm()
    #expect(form.isValid)
    form.amountText = "0"
    #expect(!form.isValid)
    form = validForm()
    form.category = " "
    #expect(!form.isValid)
    form = validForm()
    form.description = " "
    #expect(!form.isValid)
    form = validForm()
    form.vendor = String(repeating: "v", count: 121)
    #expect(!form.isValid)
    form = validForm()
    form.notes = String(repeating: "n", count: 2_001)
    #expect(!form.isValid)
    form = validForm()
    form.currency = "US"
    #expect(!form.isValid)
  }

  @Test("Create request contains business input but no actor or server timestamps")
  func createRequestContract() throws {
    let request = FinanceExpenseMutationRequest(
      action: .create,
      organizationId: orgId,
      form: validForm(),
      supportMode: false
    )
    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
    )
    #expect(object["action"] as? String == "create_expense")
    #expect(object["org_id"] as? String == orgId.uuidString.lowercased())
    #expect(object["amount_cents"] as? Int == 2_500)
    #expect(object["currency"] as? String == "usd")
    #expect(object["actor_id"] == nil)
    #expect(object["created_by"] == nil)
    #expect(object["created_at"] == nil)
    #expect(object["updated_at"] == nil)
    #expect(object["archived_at"] == nil)
  }

  @Test("Archive request contains only organization, expense, action, and support context")
  func archiveRequestContract() throws {
    let request = FinanceExpenseMutationRequest(
      action: .archive,
      organizationId: orgId,
      expenseId: sampleExpense().id,
      supportMode: false
    )
    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
    )
    #expect(object["expense_id"] as? String == sampleExpense().id.uuidString.lowercased())
    #expect(object["amount_cents"] == nil)
    #expect(object["category"] == nil)
    #expect(object["notes"] == nil)
  }

  @Test("Exact mutation JSON decodes archived and audit-safe fields")
  func mutationResponseDecodes() throws {
    let response = try JSONDecoder().decode(
      FinanceExpenseMutationResponse.self,
      from: Data(mutationJSON.utf8)
    )
    #expect(response.authorization_source == .organizationMembership)
    #expect(response.expense.id == sampleExpense().id)
    #expect(response.expense.amount_cents == 2_500)
    #expect(response.expense.archived_at == nil)
    #expect(response.expense.archived_by == nil)
  }

  @Test("Platform support is read-only in the expense UI permission")
  func supportPermissionIsReadOnly() {
    #expect(FinanceExpenseClientAuthorization.canMutate(
      authorizationSource: .organizationMembership,
      supportMode: false
    ))
    #expect(!FinanceExpenseClientAuthorization.canMutate(
      authorizationSource: .platformSupport,
      supportMode: true
    ))
    #expect(!FinanceExpenseClientAuthorization.canMutate(
      authorizationSource: .organizationMembership,
      supportMode: true
    ))
  }

  @Test("Mutation gate prevents double Save and rejects stale organization tokens")
  func mutationGate() throws {
    var gate = FinanceExpenseMutationGate()
    let firstToken = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    let secondToken = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    let started = gate.begin(organizationId: orgId, token: firstToken)
    #expect(started == firstToken)
    #expect(gate.begin(organizationId: orgId, token: secondToken) == nil)
    gate.clear()
    #expect(!gate.accepts(organizationId: orgId, token: firstToken))
    #expect(gate.begin(organizationId: otherOrgId, token: secondToken) == secondToken)
    #expect(!gate.accepts(organizationId: orgId, token: secondToken))
    #expect(gate.accepts(organizationId: otherOrgId, token: secondToken))
  }

  @Test("Create refreshes expenses and authoritative overview exactly once")
  @MainActor
  func createRefreshesDashboard() async {
    let service = MockFinanceDashboardService(orgId: orgId)
    let viewModel = FinanceDashboardViewModel()
    let succeeded = await viewModel.createExpense(
      form: validForm(),
      organizationId: orgId,
      supportMode: false,
      service: service
    )
    #expect(succeeded)
    #expect(service.createRequests.count == 1)
    #expect(service.readActions == ["overview", "payments", "requests", "expenses", "refunds"])
    #expect(viewModel.snapshot?.overview.overview.expenses_cents == 2_500)
  }

  @Test("Update and archive each refresh expenses and overview")
  @MainActor
  func updateAndArchiveRefreshDashboard() async {
    let service = MockFinanceDashboardService(orgId: orgId)
    service.currentExpense = sampleExpense()
    let viewModel = FinanceDashboardViewModel()
    var form = validForm()
    form.amountText = "30.00"
    let updated = await viewModel.updateExpense(
      sampleExpense(),
      form: form,
      organizationId: orgId,
      supportMode: false,
      service: service
    )
    #expect(updated)
    #expect(service.updateRequests.count == 1)
    #expect(viewModel.snapshot?.overview.overview.expenses_cents == 3_000)
    service.readActions.removeAll()
    let archived = await viewModel.archiveExpense(
      service.currentExpense!,
      organizationId: orgId,
      supportMode: false,
      service: service
    )
    #expect(archived)
    #expect(service.archiveRequests.count == 1)
    #expect(service.readActions.first == "overview")
    #expect(service.readActions.contains("expenses"))
    #expect(viewModel.snapshot?.overview.overview.expenses_cents == 0)
    #expect(viewModel.snapshot?.expenses.expenses.isEmpty == true)
  }

  @Test("View model prevents concurrent duplicate expense submissions")
  @MainActor
  func doubleSaveIsPrevented() async throws {
    let service = MockFinanceDashboardService(orgId: orgId)
    service.mutationDelayNanoseconds = 80_000_000
    let viewModel = FinanceDashboardViewModel()
    let first = Task { @MainActor in
      await viewModel.createExpense(
        form: validForm(),
        organizationId: orgId,
        supportMode: false,
        service: service
      )
    }
    try await Task.sleep(nanoseconds: 10_000_000)
    let second = await viewModel.createExpense(
      form: validForm(),
      organizationId: orgId,
      supportMode: false,
      service: service
    )
    #expect(!second)
    let firstSucceeded = await first.value
    #expect(firstSucceeded)
    #expect(service.createRequests.count == 1)
  }

  @Test("Platform support mutation is rejected before the service call")
  @MainActor
  func supportMutationDoesNotCallService() async {
    let service = MockFinanceDashboardService(orgId: orgId)
    let viewModel = FinanceDashboardViewModel()
    let succeeded = await viewModel.createExpense(
      form: validForm(),
      organizationId: orgId,
      supportMode: true,
      service: service
    )
    #expect(!succeeded)
    #expect(service.createRequests.isEmpty)
    #expect(viewModel.expenseMutationError == "Platform Support — read-only financial access")
  }

  @Test("Date-range changes issue a new expense and overview refresh")
  @MainActor
  func dateRangeRefreshes() async {
    let service = MockFinanceDashboardService(orgId: orgId)
    let viewModel = FinanceDashboardViewModel()
    await viewModel.refresh(organizationId: orgId, supportMode: false, service: service)
    viewModel.rangeSelection.preset = .thisYear
    await viewModel.refresh(organizationId: orgId, supportMode: false, service: service)
    #expect(service.overviewRanges.map(\.preset) == [.thisMonth, .thisYear])
    #expect(service.expenseRanges.map(\.preset) == [.thisMonth, .thisYear])
  }

  private func validForm() -> FinanceExpenseFormModel {
    var form = FinanceExpenseFormModel(currency: "USD")
    form.category = "Equipment"
    form.description = "Baseballs"
    form.amountText = "25.00"
    form.vendor = "Diamond Sports"
    form.notes = "Practice inventory"
    return form
  }

  private func sampleExpense() -> FinanceExpense {
    FinanceExpense(
      id: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-000000000301")!,
      org_id: orgId,
      category: "Facilities",
      description: "Cage rental",
      amount_cents: 1_500,
      currency: "usd",
      expense_date: "2026-07-14",
      vendor: "Marist",
      notes: nil,
      created_at: "2026-07-14T10:00:00.000Z",
      updated_at: "2026-07-14T10:00:00.000Z",
      archived_at: nil,
      archived_by: nil
    )
  }

  private var mutationJSON: String {
    """
    {
      "expense": {
        "id": "aaaaaaaa-aaaa-4aaa-8aaa-000000000301",
        "org_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        "category": "Equipment",
        "description": "Baseballs",
        "amount_cents": 2500,
        "currency": "usd",
        "expense_date": "2026-07-15",
        "vendor": null,
        "notes": null,
        "created_at": "2026-07-15T12:00:00.000Z",
        "updated_at": "2026-07-15T12:00:00.000Z",
        "archived_at": null,
        "archived_by": null
      },
      "authorization_source": "organization_membership"
    }
    """
  }
}

private final class MockFinanceDashboardService: FinanceDashboardServicing {
  let orgId: UUID
  var currentExpense: FinanceExpense?
  var createRequests: [FinanceExpenseMutationRequest] = []
  var updateRequests: [FinanceExpenseMutationRequest] = []
  var archiveRequests: [FinanceExpenseMutationRequest] = []
  var readActions: [String] = []
  var overviewRanges: [FinanceDateRangeSelection] = []
  var expenseRanges: [FinanceDateRangeSelection] = []
  var mutationDelayNanoseconds: UInt64 = 0

  init(orgId: UUID) { self.orgId = orgId }

  func financeOverview(
    orgId: UUID,
    range: FinanceDateRangeSelection,
    supportMode: Bool
  ) async throws -> FinanceOverviewResponse {
    readActions.append("overview")
    overviewRanges.append(range)
    let cents = currentExpense?.archived_at == nil ? currentExpense?.amount_cents ?? 0 : 0
    return FinanceOverviewResponse(
      overview: FinanceOverview(
        range: serverRange(preset: range.preset),
        currency: "usd",
        gross_revenue_cents: 0,
        successful_payment_count: 0,
        refunds_cents: 0,
        provider_fees_cents: 0,
        platform_fees_cents: 0,
        net_payment_revenue_cents: 0,
        expenses_cents: cents,
        estimated_profit_cents: -cents,
        open_request_balance_cents: 0,
        overdue_request_balance_cents: 0,
        open_request_count: 0,
        paid_request_count: 0,
        canceled_request_count: 0,
        average_payment_cents: 0
      ),
      authorization_source: supportMode ? .platformSupport : .organizationMembership
    )
  }

  func financeRecentPayments(
    orgId: UUID,
    range: FinanceDateRangeSelection,
    supportMode: Bool
  ) async throws -> FinanceRecentPaymentsResponse {
    readActions.append("payments")
    return FinanceRecentPaymentsResponse(
      range: serverRange(preset: range.preset),
      payments: [],
      authorization_source: supportMode ? .platformSupport : .organizationMembership
    )
  }

  func financePaymentRequests(
    orgId: UUID,
    range: FinanceDateRangeSelection,
    filter: FinancePaymentRequestFilter,
    supportMode: Bool
  ) async throws -> FinancePaymentRequestsResponse {
    readActions.append("requests")
    return FinancePaymentRequestsResponse(
      range: serverRange(preset: range.preset),
      filter: filter,
      requests: [],
      authorization_source: supportMode ? .platformSupport : .organizationMembership
    )
  }

  func financeExpenses(
    orgId: UUID,
    range: FinanceDateRangeSelection,
    supportMode: Bool
  ) async throws -> FinanceExpensesResponse {
    readActions.append("expenses")
    expenseRanges.append(range)
    let rows = currentExpense.map { $0.archived_at == nil ? [$0] : [] } ?? []
    return FinanceExpensesResponse(
      range: serverRange(preset: range.preset),
      expenses: rows,
      authorization_source: supportMode ? .platformSupport : .organizationMembership
    )
  }

  func financeRefunds(
    orgId: UUID,
    range: FinanceDateRangeSelection,
    supportMode: Bool
  ) async throws -> FinanceRefundsResponse {
    readActions.append("refunds")
    return FinanceRefundsResponse(
      range: serverRange(preset: range.preset),
      refunds: [],
      authorization_source: supportMode ? .platformSupport : .organizationMembership
    )
  }

  func createFinanceExpense(
    _ request: FinanceExpenseMutationRequest
  ) async throws -> FinanceExpenseMutationResponse {
    createRequests.append(request)
    if mutationDelayNanoseconds > 0 {
      try await Task.sleep(nanoseconds: mutationDelayNanoseconds)
    }
    currentExpense = expense(from: request, id: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-000000000399")!)
    return FinanceExpenseMutationResponse(
      expense: currentExpense!,
      authorization_source: .organizationMembership
    )
  }

  func updateFinanceExpense(
    _ request: FinanceExpenseMutationRequest
  ) async throws -> FinanceExpenseMutationResponse {
    updateRequests.append(request)
    currentExpense = expense(from: request, id: currentExpense?.id ?? UUID())
    return FinanceExpenseMutationResponse(
      expense: currentExpense!,
      authorization_source: .organizationMembership
    )
  }

  func archiveFinanceExpense(
    _ request: FinanceExpenseMutationRequest
  ) async throws -> FinanceExpenseMutationResponse {
    archiveRequests.append(request)
    let archived = FinanceExpense(
      id: currentExpense?.id ?? UUID(uuidString: request.expense_id ?? "")!,
      org_id: orgId,
      category: currentExpense?.category,
      description: currentExpense?.description,
      amount_cents: currentExpense?.amount_cents ?? 0,
      currency: currentExpense?.currency ?? "usd",
      expense_date: currentExpense?.expense_date ?? "2026-07-15",
      vendor: currentExpense?.vendor,
      notes: currentExpense?.notes,
      created_at: currentExpense?.created_at ?? "2026-07-15T12:00:00.000Z",
      updated_at: "2026-07-15T12:01:00.000Z",
      archived_at: "2026-07-15T12:01:00.000Z",
      archived_by: UUID(uuidString: "11111111-1111-4111-8111-111111111111")
    )
    currentExpense = archived
    return FinanceExpenseMutationResponse(
      expense: archived,
      authorization_source: .organizationMembership
    )
  }

  private func expense(
    from request: FinanceExpenseMutationRequest,
    id: UUID
  ) -> FinanceExpense {
    FinanceExpense(
      id: id,
      org_id: orgId,
      category: request.category,
      description: request.description,
      amount_cents: request.amount_cents ?? 0,
      currency: request.currency ?? "usd",
      expense_date: request.expense_date ?? "2026-07-15",
      vendor: request.vendor,
      notes: request.notes,
      created_at: currentExpense?.created_at ?? "2026-07-15T12:00:00.000Z",
      updated_at: "2026-07-15T12:00:00.000Z",
      archived_at: nil,
      archived_by: nil
    )
  }

  private func serverRange(preset: FinanceDateRangePreset) -> FinanceServerDateRange {
    FinanceServerDateRange(
      preset: preset,
      start: "2026-07-01T00:00:00.000Z",
      end: "2026-08-01T00:00:00.000Z",
      start_date: "2026-07-01",
      end_date: "2026-07-31",
      timezone: "UTC",
      timezone_source: "utc_fallback"
    )
  }
}
