import XCTest
import SwiftUI
@testable import MultiOrg
#if canImport(UIKit)
import UIKit
#endif

/// EVIDENCE-ONLY, TEST-ONLY render harness for the Finance Overview pilot.
/// Renders the real Finance content subviews and filter controls with
/// representative **mock model data** — no network, no `AppState`, not connected
/// to production navigation. Captures via `layer.render`.
///
/// Split into several short test methods so each stays well under the per-test
/// execution timeout (a single all-configs method exceeds it). Safe to delete.
@MainActor
final class FinanceRenderTests: XCTestCase {
  #if canImport(UIKit)
  private struct Spec {
    let name: String
    let width: CGFloat
    let dts: DynamicTypeSize
    let state: FinanceHarness.State
  }

  func testRenderFinanceLoaded() throws {
    try render([
      Spec(name: "iphone-loaded",     width: 393,  dts: .large,          state: .loaded),
      Spec(name: "ipad-loaded",       width: 834,  dts: .large,          state: .loaded),
      Spec(name: "macos-loaded",      width: 1200, dts: .large,          state: .loaded),
      Spec(name: "iphone-ax3-loaded", width: 393,  dts: .accessibility3, state: .loaded),
    ])
  }

  func testRenderFinanceStates() throws {
    try render([
      Spec(name: "iphone-loading",    width: 393, dts: .large, state: .loading),
      Spec(name: "iphone-empty",      width: 393, dts: .large, state: .empty),
      Spec(name: "iphone-error",      width: 393, dts: .large,          state: .error),
      Spec(name: "iphone-ax3-error",  width: 393, dts: .accessibility3, state: .error),
      Spec(name: "iphone-refreshing", width: 393, dts: .large,          state: .refreshing),
      Spec(name: "iphone-support",    width: 393, dts: .large,          state: .support),
    ])
  }

  func testRenderFinanceControls() throws {
    try render([
      Spec(name: "iphone-controls",     width: 393, dts: .large,          state: .controls),
      Spec(name: "iphone-ax3-controls", width: 393, dts: .accessibility3, state: .controls),
    ])
  }

  private func render(_ specs: [Spec]) throws {
    let dir = FileManager.default.temporaryDirectory

    for spec in specs {
      try autoreleasepool {
        // Accessibility renders are very tall; use 1x there to stay within the
        // simulator's memory budget when this runs inside the full test suite.
        let format = UIGraphicsImageRendererFormat()
        format.scale = spec.dts.isAccessibilitySize ? 1 : 2
        let view = FinanceHarness(state: spec.state)
          .environment(\.dynamicTypeSize, spec.dts)
          .frame(width: spec.width)
          .background(HP.Color.bg)
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = .dark
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: spec.width, height: 2000))
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let fitted = host.sizeThatFits(in: CGSize(width: spec.width, height: .greatestFiniteMagnitude))
        window.frame = CGRect(x: 0, y: 0, width: spec.width, height: ceil(fitted.height))
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        let renderer = UIGraphicsImageRenderer(size: host.view.bounds.size, format: format)
        let image = renderer.image { ctx in host.view.layer.render(in: ctx.cgContext) }
        let url = dir.appendingPathComponent("fin-\(spec.name).png")
        if let data = image.pngData() { try data.write(to: url) }
        print("FIN_PNG \(url.path) size=\(Int(host.view.bounds.width))x\(Int(host.view.bounds.height))")

        window.isHidden = true
        window.rootViewController = nil
      }
    }
  }
  #else
  func testRenderFinanceLoaded() throws { throw XCTSkip("UIKit required") }
  #endif
}

#if canImport(UIKit)
/// Test-only host composing the Finance content subviews with mock data.
struct FinanceHarness: View {
  enum State { case loaded, loading, empty, error, refreshing, support, controls }
  let state: State

  var body: some View {
    if state == .controls { controls } else { dashboard }
  }

  // Production Finance filter controls: date-range preset menu (selected),
  // custom start/end date controls, and the five single-select request pills.
  private var controls: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      sectionLabel("Date range — selected preset (menu)")
      FinanceDateRangePicker(selection: .constant(FinanceMock.presetSelection),
                             serverRange: FinanceMock.range, isLoading: false)

      sectionLabel("Date range — custom start / end")
      FinanceDateRangePicker(selection: .constant(FinanceMock.customSelection),
                             serverRange: nil, isLoading: false)

      sectionLabel("Request filter — five single-select pills (Open selected)")
      FinancePaymentRequestsView(requests: FinanceMock.requests, filter: .constant(.open),
                                 isLoading: false, onRefresh: {})
    }
    .padding(HP.Space.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(HP.Color.bg)
  }

  private func sectionLabel(_ text: String) -> some View {
    Text(text.uppercased())
      .font(HP.Font.eyebrow).tracking(HP.Font.eyebrowTracking).foregroundStyle(HP.Color.accent)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var dashboard: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      HPWorkspaceHeader("Finance", orgLabel: "Diamond Baseball Academy",
                        context: "2026-07-01 – 2026-07-31") {
        HPButton(title: "Refresh", systemImage: "arrow.clockwise", variant: .secondary, size: .sm)
      }
      if state == .refreshing {
        HStack(spacing: HP.Space.xs) {
          HPProgressIndicator(style: .spinner)
          Text("Refreshing…").font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        }
      }
      if state == .support {
        HPCard {
          HStack(alignment: .top, spacing: HP.Space.sm) {
            Image(systemName: "person.badge.shield.checkmark").font(.title3).foregroundStyle(HP.Color.accent)
            VStack(alignment: .leading, spacing: 4) {
              HStack(spacing: HP.Space.xs) {
                Text("Platform Support").font(HP.Font.headline).foregroundStyle(HP.Color.text)
                HPStatusBadge(text: "Read-only", kind: .gold)
              }
              Text("Viewing finance for Diamond Baseball Academy. This does not make you an organization owner or member.")
                .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
          }
        }
      }
      if state == .error {
        // One page-level error card (mirrors the production container) — no
        // per-section error cards are rendered beneath it.
        HPCard {
          HPErrorState(message: "The finance service is temporarily unavailable.", onRetry: {})
        }
      } else {
        FinanceOverviewView(overview: overview, isLoading: loading, onRefresh: {})
        RecentPaymentsView(payments: payments, isLoading: loading, onRefresh: {})
        FinancePaymentRequestsView(requests: requests, filter: .constant(.all), isLoading: loading, onRefresh: {})
        FinanceRefundsView(refunds: refunds, isLoading: loading, onRefresh: {})
      }
    }
    .padding(HP.Space.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(HP.Color.bg)
  }

  private var loading: Bool { state == .loading }
  private var hasData: Bool { state == .loaded || state == .refreshing || state == .support }

  private var overview: FinanceOverview? { hasData ? FinanceMock.overview : nil }
  private var payments: [FinanceRecentPayment]? {
    switch state { case .loaded, .refreshing, .support: FinanceMock.payments; case .empty: []; default: nil }
  }
  private var requests: [FinancePaymentRequestItem]? {
    switch state { case .loaded, .refreshing, .support: FinanceMock.requests; case .empty: []; default: nil }
  }
  private var refunds: [FinanceRefund]? {
    switch state { case .loaded, .refreshing, .support: FinanceMock.refunds; case .empty: []; default: nil }
  }
}

/// Local mock finance data (no network).
enum FinanceMock {
  static let range = FinanceServerDateRange(
    preset: .thisMonth, start: "2026-07-01T00:00:00Z", end: "2026-07-31T23:59:59Z",
    start_date: "2026-07-01", end_date: "2026-07-31", timezone: "UTC", timezone_source: "default")

  static let overview = FinanceOverview(
    range: range, currency: "usd",
    gross_revenue_cents: 1_824_000, successful_payment_count: 128, refunds_cents: 12_000,
    provider_fees_cents: 52_800, platform_fees_cents: 0, net_payment_revenue_cents: 1_591_000,
    expenses_cents: 691_000, estimated_profit_cents: 800_000,
    open_request_balance_cents: 432_000, overdue_request_balance_cents: 96_000,
    open_request_count: 12, paid_request_count: 76, canceled_request_count: 4,
    average_payment_cents: 14_250)

  static let payments: [FinanceRecentPayment] = [
    payment(amount: 14_900, net: 14_412, status: "succeeded", date: "2026-07-14"),
    payment(amount: 9_900, net: 9_579, status: "succeeded", date: "2026-07-13"),
    payment(amount: 6_000, net: 5_786, status: "refunded", date: "2026-07-12"),
  ]

  static let requests: [FinancePaymentRequestItem] = [
    request(title: "14U Summer Program", amount: 14_900, status: "open", due: "2026-07-20"),
    request(title: "Cage rental — July", amount: 6_000, status: "paid", due: nil),
    request(title: "Tournament fee", amount: 12_000, status: "overdue", due: "2026-07-05"),
  ]

  static let refunds: [FinanceRefund] = [
    FinanceRefund(id: UUID(), org_id: UUID(), payment_id: UUID(), amount_cents: 6_000,
                  currency: "usd", status: "succeeded", reason: "requested_by_customer", created_at: "2026-07-12"),
  ]

  static var presetSelection: FinanceDateRangeSelection {
    var selection = FinanceDateRangeSelection()
    selection.preset = .thisMonth
    return selection
  }

  static var customSelection: FinanceDateRangeSelection {
    var selection = FinanceDateRangeSelection()
    selection.preset = .custom
    let calendar = Calendar(identifier: .gregorian)
    selection.customStart = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)) ?? Date()
    selection.customEnd = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15)) ?? Date()
    return selection
  }

  private static func payment(amount: Int, net: Int, status: String, date: String) -> FinanceRecentPayment {
    FinanceRecentPayment(id: UUID(), org_id: UUID(), payment_request_id: nil, player_id: nil, payer_id: nil,
                         amount_cents: amount, processing_fee_cents: amount - net, platform_fee_cents: 0,
                         net_to_organization_cents: net, currency: "usd", status: status, provider: "stripe",
                         paid_at: date, created_at: date)
  }
  private static func request(title: String, amount: Int, status: String, due: String?) -> FinancePaymentRequestItem {
    FinancePaymentRequestItem(id: UUID(), request_batch_id: nil, org_id: UUID(), child_id: UUID(),
                              title: title, amount_cents: amount, currency: "usd", status: status,
                              due_date: due, paid_at: nil, created_at: "2026-07-10")
  }
}
#endif
