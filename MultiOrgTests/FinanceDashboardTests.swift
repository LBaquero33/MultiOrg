import Foundation
import Testing
@testable import MultiOrg

@Suite("Finance dashboard foundation")
struct FinanceDashboardTests {
  private let orgId = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
  private let otherOrgId = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!

  @Test("Exact finance overview JSON decodes integer-cent metrics")
  func overviewDecodes() throws {
    let response = try JSONDecoder().decode(
      FinanceOverviewResponse.self,
      from: Data(overviewJSON.utf8)
    )
    #expect(response.authorization_source == .organizationMembership)
    #expect(response.overview.currency == "usd")
    #expect(response.overview.gross_revenue_cents == 15_000)
    #expect(response.overview.net_payment_revenue_cents == 12_400)
    #expect(response.overview.estimated_profit_cents == 11_400)
    #expect(response.overview.money(12_400).minorUnits == 12_400)
    #expect(response.overview.range.timezone_source == "utc_fallback")
  }

  @Test("Finance request sends organization and range but no actor, role, or totals")
  func requestContractExcludesServerAuthority() throws {
    let request = FinanceDashboardRequest(
      action: "overview",
      organizationId: orgId,
      range: FinanceDateRangeSelection(preset: .thisMonth),
      supportMode: false
    )
    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
    )
    #expect(object["org_id"] as? String == orgId.uuidString.lowercased())
    #expect(object["range"] as? String == "this_month")
    #expect(object["support_mode"] as? Bool == false)
    #expect(object["actor_id"] == nil)
    #expect(object["role"] == nil)
    #expect(object["is_platform_admin"] == nil)
    #expect(object["gross_revenue_cents"] == nil)
  }

  @Test("Platform support is explicit without sending an actor or membership")
  func supportRequestIsExplicit() throws {
    let request = FinanceDashboardRequest(
      action: "recent_payments",
      organizationId: orgId,
      range: FinanceDateRangeSelection(preset: .thisYear),
      supportMode: true
    )
    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
    )
    #expect(object["support_mode"] as? Bool == true)
    #expect(object["actor_id"] == nil)
    #expect(object["membership"] == nil)
  }

  @Test("Custom date selection emits stable calendar date strings")
  func customDatesEncode() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10))!
    let end = calendar.date(from: DateComponents(year: 2026, month: 6, day: 12))!
    let selection = FinanceDateRangeSelection(
      preset: .custom,
      customStart: start,
      customEnd: end
    )
    #expect(selection.isValid)
    #expect(selection.dateString(start, calendar: calendar) == "2026-06-10")
    #expect(selection.dateString(end, calendar: calendar) == "2026-06-12")
  }

  @Test("Organization switching ignores a stale finance response")
  func organizationSwitchRejectsStaleResponse() throws {
    var state = FinanceDashboardDataState()
    let first = state.begin(
      organizationId: orgId,
      range: FinanceDateRangeSelection(preset: .thisMonth),
      requestFilter: .all,
      supportMode: false,
      token: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    )
    let second = state.begin(
      organizationId: otherOrgId,
      range: FinanceDateRangeSelection(preset: .thisMonth),
      requestFilter: .all,
      supportMode: false,
      token: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    )
    let snapshot = try makeSnapshot()
    let acceptedFirst = state.apply(snapshot, for: first)
    #expect(!acceptedFirst)
    #expect(state.snapshot == nil)
    let acceptedSecond = state.apply(snapshot, for: second)
    #expect(acceptedSecond)
    #expect(state.snapshot == snapshot)
  }

  @Test("Date-range changes ignore superseded finance responses")
  func dateRangeChangeRejectsStaleResponse() throws {
    var state = FinanceDashboardDataState()
    let month = state.begin(
      organizationId: orgId,
      range: FinanceDateRangeSelection(preset: .thisMonth),
      requestFilter: .all,
      supportMode: false,
      token: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    )
    let year = state.begin(
      organizationId: orgId,
      range: FinanceDateRangeSelection(preset: .thisYear),
      requestFilter: .all,
      supportMode: false,
      token: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
    )
    let snapshot = try makeSnapshot()
    let acceptedMonth = state.apply(snapshot, for: month)
    let acceptedYear = state.apply(snapshot, for: year)
    #expect(!acceptedMonth)
    #expect(acceptedYear)
  }

  @Test("Typed empty finance sections decode safely")
  func emptySectionsDecode() throws {
    let payments = try JSONDecoder().decode(
      FinanceRecentPaymentsResponse.self,
      from: Data(listJSON(key: "payments").utf8)
    )
    let expenses = try JSONDecoder().decode(
      FinanceExpensesResponse.self,
      from: Data(listJSON(key: "expenses").utf8)
    )
    let refunds = try JSONDecoder().decode(
      FinanceRefundsResponse.self,
      from: Data(listJSON(key: "refunds").utf8)
    )
    #expect(payments.payments.isEmpty)
    #expect(expenses.expenses.isEmpty)
    #expect(refunds.refunds.isEmpty)
  }

  private func makeSnapshot() throws -> FinanceDashboardSnapshot {
    let decoder = JSONDecoder()
    return FinanceDashboardSnapshot(
      overview: try decoder.decode(FinanceOverviewResponse.self, from: Data(overviewJSON.utf8)),
      recentPayments: try decoder.decode(
        FinanceRecentPaymentsResponse.self,
        from: Data(listJSON(key: "payments").utf8)
      ),
      paymentRequests: try decoder.decode(
        FinancePaymentRequestsResponse.self,
        from: Data(requestListJSON.utf8)
      ),
      expenses: try decoder.decode(
        FinanceExpensesResponse.self,
        from: Data(listJSON(key: "expenses").utf8)
      ),
      refunds: try decoder.decode(
        FinanceRefundsResponse.self,
        from: Data(listJSON(key: "refunds").utf8)
      )
    )
  }

  private var overviewJSON: String {
    """
    {
      "overview": {
        "range": {
          "preset": "this_month",
          "start": "2026-07-01T00:00:00.000Z",
          "end": "2026-08-01T00:00:00.000Z",
          "start_date": "2026-07-01",
          "end_date": "2026-07-31",
          "timezone": "UTC",
          "timezone_source": "utc_fallback"
        },
        "currency": "usd",
        "gross_revenue_cents": 15000,
        "successful_payment_count": 2,
        "refunds_cents": 2000,
        "provider_fees_cents": 450,
        "platform_fees_cents": 150,
        "net_payment_revenue_cents": 12400,
        "expenses_cents": 1000,
        "estimated_profit_cents": 11400,
        "open_request_balance_cents": 10000,
        "overdue_request_balance_cents": 7000,
        "open_request_count": 2,
        "paid_request_count": 1,
        "canceled_request_count": 1,
        "average_payment_cents": 7500
      },
      "authorization_source": "organization_membership"
    }
    """
  }

  private func listJSON(key: String) -> String {
    """
    {
      "range": {
        "preset": "this_month",
        "start": "2026-07-01T00:00:00.000Z",
        "end": "2026-08-01T00:00:00.000Z",
        "start_date": "2026-07-01",
        "end_date": "2026-07-31",
        "timezone": "UTC",
        "timezone_source": "utc_fallback"
      },
      "\(key)": [],
      "authorization_source": "organization_membership"
    }
    """
  }

  private var requestListJSON: String {
    """
    {
      "range": {
        "preset": "this_month",
        "start": "2026-07-01T00:00:00.000Z",
        "end": "2026-08-01T00:00:00.000Z",
        "start_date": "2026-07-01",
        "end_date": "2026-07-31",
        "timezone": "UTC",
        "timezone_source": "utc_fallback"
      },
      "filter": "all",
      "requests": [],
      "authorization_source": "organization_membership"
    }
    """
  }
}
