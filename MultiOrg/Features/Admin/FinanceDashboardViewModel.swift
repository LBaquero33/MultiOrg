import Combine
import Foundation

@MainActor
protocol FinanceDashboardServicing {
  func financeOverview(
    orgId: UUID,
    range: FinanceDateRangeSelection,
    supportMode: Bool
  ) async throws -> FinanceOverviewResponse
  func financeRecentPayments(
    orgId: UUID,
    range: FinanceDateRangeSelection,
    supportMode: Bool
  ) async throws -> FinanceRecentPaymentsResponse
  func financePaymentRequests(
    orgId: UUID,
    range: FinanceDateRangeSelection,
    filter: FinancePaymentRequestFilter,
    supportMode: Bool
  ) async throws -> FinancePaymentRequestsResponse
  func financeExpenses(
    orgId: UUID,
    range: FinanceDateRangeSelection,
    supportMode: Bool
  ) async throws -> FinanceExpensesResponse
  func financeRefunds(
    orgId: UUID,
    range: FinanceDateRangeSelection,
    supportMode: Bool
  ) async throws -> FinanceRefundsResponse
  func createFinanceExpense(
    _ request: FinanceExpenseMutationRequest
  ) async throws -> FinanceExpenseMutationResponse
  func updateFinanceExpense(
    _ request: FinanceExpenseMutationRequest
  ) async throws -> FinanceExpenseMutationResponse
  func archiveFinanceExpense(
    _ request: FinanceExpenseMutationRequest
  ) async throws -> FinanceExpenseMutationResponse
}

extension SupabaseService: FinanceDashboardServicing {}

@MainActor
final class FinanceDashboardViewModel: ObservableObject {
  @Published var rangeSelection = FinanceDateRangeSelection()
  @Published var requestFilter = FinancePaymentRequestFilter.all
  @Published private(set) var snapshot: FinanceDashboardSnapshot?
  @Published private(set) var isLoading = false
  @Published private(set) var errorMessage: String?
  @Published private(set) var isExpenseMutationInFlight = false
  @Published private(set) var expenseMutationError: String?
  @Published private(set) var expenseSuccessMessage: String?

  private var dataState = FinanceDashboardDataState()
  private var expenseMutationGate = FinanceExpenseMutationGate()

  var loadKey: String {
    [
      rangeSelection.preset.rawValue,
      rangeSelection.customStartString ?? "preset",
      rangeSelection.customEndString ?? "preset",
      requestFilter.rawValue,
    ].joined(separator: "|")
  }

  func refresh(
    organizationId: UUID,
    supportMode: Bool,
    service: (any FinanceDashboardServicing)?
  ) async {
    guard rangeSelection.isValid else {
      errorMessage = "The custom start date must not be after the end date."
      snapshot = nil
      isLoading = false
      return
    }
    guard let service else {
      errorMessage = "Finance data is unavailable because the session is not ready."
      snapshot = nil
      isLoading = false
      return
    }

    let context = dataState.begin(
      organizationId: organizationId,
      range: rangeSelection,
      requestFilter: requestFilter,
      supportMode: supportMode
    )
    snapshot = nil
    errorMessage = nil
    isLoading = true

    do {
      let overview = try await service.financeOverview(
        orgId: organizationId,
        range: context.range,
        supportMode: supportMode
      )
      guard dataState.context == context else { return }
      let recentPayments = try await service.financeRecentPayments(
        orgId: organizationId,
        range: context.range,
        supportMode: supportMode
      )
      guard dataState.context == context else { return }
      let paymentRequests = try await service.financePaymentRequests(
        orgId: organizationId,
        range: context.range,
        filter: context.requestFilter,
        supportMode: supportMode
      )
      guard dataState.context == context else { return }
      let expenses = try await service.financeExpenses(
        orgId: organizationId,
        range: context.range,
        supportMode: supportMode
      )
      guard dataState.context == context else { return }
      let refunds = try await service.financeRefunds(
        orgId: organizationId,
        range: context.range,
        supportMode: supportMode
      )
      guard dataState.context == context else { return }

      let loaded = FinanceDashboardSnapshot(
        overview: overview,
        recentPayments: recentPayments,
        paymentRequests: paymentRequests,
        expenses: expenses,
        refunds: refunds
      )
      guard dataState.apply(loaded, for: context) else { return }
      snapshot = loaded
      isLoading = false
    } catch {
      guard dataState.context == context else { return }
      errorMessage = error.localizedDescription
      isLoading = false
    }
  }

  func createExpense(
    form: FinanceExpenseFormModel,
    organizationId: UUID,
    supportMode: Bool,
    service: (any FinanceDashboardServicing)?
  ) async -> Bool {
    guard form.isValid else {
      expenseMutationError = form.validationError
      return false
    }
    return await mutateExpense(
      request: FinanceExpenseMutationRequest(
        action: .create,
        organizationId: organizationId,
        form: form,
        supportMode: supportMode
      ),
      successMessage: "Expense added.",
      organizationId: organizationId,
      supportMode: supportMode,
      service: service
    )
  }

  func updateExpense(
    _ expense: FinanceExpense,
    form: FinanceExpenseFormModel,
    organizationId: UUID,
    supportMode: Bool,
    service: (any FinanceDashboardServicing)?
  ) async -> Bool {
    guard form.isValid else {
      expenseMutationError = form.validationError
      return false
    }
    return await mutateExpense(
      request: FinanceExpenseMutationRequest(
        action: .update,
        organizationId: organizationId,
        expenseId: expense.id,
        form: form,
        supportMode: supportMode
      ),
      successMessage: "Expense updated.",
      organizationId: organizationId,
      supportMode: supportMode,
      service: service
    )
  }

  func archiveExpense(
    _ expense: FinanceExpense,
    organizationId: UUID,
    supportMode: Bool,
    service: (any FinanceDashboardServicing)?
  ) async -> Bool {
    await mutateExpense(
      request: FinanceExpenseMutationRequest(
        action: .archive,
        organizationId: organizationId,
        expenseId: expense.id,
        supportMode: supportMode
      ),
      successMessage: "Expense archived.",
      organizationId: organizationId,
      supportMode: supportMode,
      service: service
    )
  }

  func clearExpenseMessage() {
    expenseMutationError = nil
    expenseSuccessMessage = nil
  }

  func clear() {
    dataState.clear()
    expenseMutationGate.clear()
    snapshot = nil
    isLoading = false
    errorMessage = nil
    isExpenseMutationInFlight = false
    expenseMutationError = nil
    expenseSuccessMessage = nil
  }

  private func mutateExpense(
    request: FinanceExpenseMutationRequest,
    successMessage: String,
    organizationId: UUID,
    supportMode: Bool,
    service: (any FinanceDashboardServicing)?
  ) async -> Bool {
    guard !supportMode else {
      expenseMutationError = "Platform Support — read-only financial access"
      return false
    }
    guard let service else {
      expenseMutationError = "Expense management is unavailable because the session is not ready."
      return false
    }
    guard let token = expenseMutationGate.begin(organizationId: organizationId) else {
      return false
    }
    isExpenseMutationInFlight = true
    expenseMutationError = nil
    expenseSuccessMessage = nil

    do {
      let response: FinanceExpenseMutationResponse
      switch request.action {
      case .create:
        response = try await service.createFinanceExpense(request)
      case .update:
        response = try await service.updateFinanceExpense(request)
      case .archive:
        response = try await service.archiveFinanceExpense(request)
      }
      guard expenseMutationGate.accepts(
        organizationId: organizationId,
        token: token
      ) else { return false }
      guard response.authorization_source == .organizationMembership,
            response.expense.org_id == organizationId else {
        throw FinanceExpenseClientError.invalidMutationResponse
      }
      expenseMutationGate.finish(token: token)
      isExpenseMutationInFlight = false
      expenseSuccessMessage = successMessage
      await refresh(
        organizationId: organizationId,
        supportMode: supportMode,
        service: service
      )
      return true
    } catch {
      guard expenseMutationGate.accepts(
        organizationId: organizationId,
        token: token
      ) else { return false }
      expenseMutationGate.finish(token: token)
      isExpenseMutationInFlight = false
      expenseMutationError = error.localizedDescription
      return false
    }
  }
}

private enum FinanceExpenseClientError: LocalizedError {
  case invalidMutationResponse

  var errorDescription: String? {
    "The expense response did not match the selected organization."
  }
}
