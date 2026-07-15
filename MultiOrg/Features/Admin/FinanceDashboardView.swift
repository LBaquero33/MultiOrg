import SwiftUI

// Finance Overview — Home Plate OS pilot (Stage 4).
//
// Presentation-layer redesign only. Preserves the public initializer,
// embedded/standalone behavior, the `.task/.onChange/.onDisappear` lifecycle,
// authorization/platform-support semantics, every ViewModel call, integer-cent
// and currency formatting (via `SDMoney.formatted()`), and the embedded
// `ExpenseManagementView` (unchanged). No trends/deltas/margins are invented —
// only values already provided by `FinanceDashboardModels` are displayed.

struct FinanceDashboardView: View {
  let organizationId: UUID
  let organizationName: String
  let platformSupportMode: Bool
  var embedded = false

  @EnvironmentObject private var appState: AppState
  @StateObject private var viewModel = FinanceDashboardViewModel()

  var body: some View {
    Group {
      if embedded {
        dashboardContent
      } else {
        ScrollView { dashboardContent }
          .background(HP.Color.bg)
          .navigationTitle("Finance")
      }
    }
    .task(id: "\(organizationId.uuidString)|\(viewModel.loadKey)|\(platformSupportMode)") {
      await refresh()
    }
    .onChange(of: organizationId) { _, _ in viewModel.clear() }
    .onDisappear { viewModel.clear() }
  }

  private var dashboardContent: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      HPWorkspaceHeader("Finance", orgLabel: headerOrgLabel, context: headerContext) {
        HPButton(title: "Refresh", systemImage: "arrow.clockwise", variant: .secondary, size: .sm) {
          Task { await refresh() }
        }
      }

      // Refresh-in-progress over existing data (stale/refreshing) — non-blocking.
      if viewModel.isLoading, viewModel.snapshot != nil {
        HStack(spacing: HP.Space.xs) {
          HPProgressIndicator(style: .spinner)
          Text("Refreshing…").font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        }
        .padding(.horizontal, HP.Space.xs)
        .accessibilityElement(children: .combine)
      }

      if platformSupportMode { supportBanner }

      FinanceDateRangePicker(
        selection: $viewModel.rangeSelection,
        serverRange: viewModel.snapshot?.overview.overview.range,
        isLoading: viewModel.isLoading
      )
      FinanceOverviewView(
        overview: viewModel.snapshot?.overview.overview,
        isLoading: viewModel.isLoading,
        errorMessage: viewModel.errorMessage,
        onRefresh: { Task { await refresh() } }
      )
      RecentPaymentsView(
        payments: viewModel.snapshot?.recentPayments.payments,
        isLoading: viewModel.isLoading,
        errorMessage: viewModel.errorMessage,
        onRefresh: { Task { await refresh() } }
      )
      FinancePaymentRequestsView(
        requests: viewModel.snapshot?.paymentRequests.requests,
        filter: $viewModel.requestFilter,
        isLoading: viewModel.isLoading,
        errorMessage: viewModel.errorMessage,
        onRefresh: { Task { await refresh() } }
      )
      // Embedded, UNCHANGED — expense mutation behavior preserved.
      ExpenseManagementView(
        organizationId: organizationId,
        supportMode: platformSupportMode,
        defaultCurrency: viewModel.snapshot?.overview.overview.currency ?? "usd",
        expenses: viewModel.snapshot?.expenses.expenses,
        authorizationSource: viewModel.snapshot?.expenses.authorization_source,
        isLoading: viewModel.isLoading,
        errorMessage: viewModel.errorMessage,
        viewModel: viewModel,
        service: appState.supabase,
        onRefresh: { Task { await refresh() } }
      )
      FinanceRefundsView(
        refunds: viewModel.snapshot?.refunds.refunds,
        isLoading: viewModel.isLoading,
        errorMessage: viewModel.errorMessage,
        onRefresh: { Task { await refresh() } }
      )
    }
    .padding(embedded ? 0 : HP.Space.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(HP.Color.bg)
  }

  private var headerOrgLabel: String {
    let trimmed = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Home Plate" : trimmed
  }

  private var headerContext: String {
    if let range = viewModel.snapshot?.overview.overview.range {
      return "\(range.start_date) – \(range.end_date)"
    }
    return viewModel.rangeSelection.preset.title
  }

  private var supportBanner: some View {
    HPCard {
      HStack(alignment: .top, spacing: HP.Space.sm) {
        Image(systemName: "person.badge.shield.checkmark")
          .font(.title3).foregroundStyle(HP.Color.accent)
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: HP.Space.xs) {
            Text("Platform Support").font(HP.Font.headline).foregroundStyle(HP.Color.text)
            HPStatusBadge(text: "Read-only", kind: .gold)
          }
          Text("Viewing finance for \(organizationName). This does not make you an organization owner or member.")
            .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }
    }
  }

  private func refresh() async {
    await viewModel.refresh(
      organizationId: organizationId,
      supportMode: platformSupportMode,
      service: appState.supabase
    )
  }
}

// MARK: - Date range (HP-styled menu — 5 presets, no truncation)

struct FinanceDateRangePicker: View {
  @Binding var selection: FinanceDateRangeSelection
  let serverRange: FinanceServerDateRange?
  let isLoading: Bool

  var body: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Date range")

        Menu {
          ForEach(FinanceDateRangePreset.allCases) { preset in
            Button {
              selection.preset = preset
            } label: {
              if selection.preset == preset {
                Label(preset.title, systemImage: "checkmark")
              } else {
                Text(preset.title)
              }
            }
          }
        } label: {
          HStack {
            Text(selection.preset.title).font(HP.Font.body).foregroundStyle(HP.Color.text)
            Spacer(minLength: HP.Space.sm)
            Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(HP.Color.textMuted)
          }
          .padding(.horizontal, HP.Space.sm).padding(.vertical, 10)
          .background(RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous).fill(HP.Color.input))
          .overlay(RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous).strokeBorder(HP.Color.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isLoading && serverRange == nil)
        .accessibilityLabel("Date range preset")

        if selection.preset == .custom {
          VStack(alignment: .leading, spacing: HP.Space.xs) {
            DatePicker("Start", selection: $selection.customStart, displayedComponents: .date)
            DatePicker("End", selection: $selection.customEnd, displayedComponents: .date)
            if !selection.isValid {
              Text("Start must not be after end.").font(HP.Font.caption).foregroundStyle(HP.Color.danger)
            }
          }
          .font(HP.Font.callout)
          .foregroundStyle(HP.Color.text)
          .tint(HP.Color.accent)
        }

        if let serverRange {
          Text("\(serverRange.start_date) – \(serverRange.end_date) · \(serverRange.timezone)")
            .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }
}

// MARK: - Overview metrics

struct FinanceOverviewView: View {
  let overview: FinanceOverview?
  let isLoading: Bool
  let errorMessage: String?
  let onRefresh: () -> Void

  @Environment(\.dynamicTypeSize) private var dts

  private var columns: [GridItem] {
    dts.isAccessibilitySize
      ? [GridItem(.flexible(), spacing: HP.Space.sm)]
      : [GridItem(.adaptive(minimum: 150), spacing: HP.Space.sm)]
  }

  var body: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("Overview")
        if isLoading, overview == nil {
          HPLoadingState(text: "Loading finance overview…")
        } else if let errorMessage, overview == nil {
          HPErrorState(message: errorMessage, onRetry: onRefresh)
        } else if let overview {
          metricGrid(overview)
          feesAndActivity(overview)
          Text("Net revenue = gross − successful refunds − provider fees − Home Plate application fees. Estimated profit also subtracts recorded expenses.")
            .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        } else {
          HPEmptyState(title: "No finance data",
                       message: "No finance overview has been loaded for this range.",
                       systemImage: "chart.bar")
        }
      }
    }
  }

  private func metricGrid(_ o: FinanceOverview) -> some View {
    LazyVGrid(columns: columns, spacing: HP.Space.sm) {
      HPMetricCard(title: "Gross Revenue", value: o.money(o.gross_revenue_cents).formatted(),
                   context: "\(o.successful_payment_count) payments")
      HPMetricCard(title: "Net Revenue", value: o.money(o.net_payment_revenue_cents).formatted(),
                   context: "After fees & refunds", valueColor: HP.Color.success)
      HPMetricCard(title: "Estimated Profit", value: o.money(o.estimated_profit_cents).formatted(),
                   context: "Gross − fees − refunds − expenses",
                   valueColor: o.estimated_profit_cents >= 0 ? HP.Color.success : HP.Color.danger)
      HPMetricCard(title: "Outstanding", value: o.money(o.open_request_balance_cents).formatted(),
                   context: "\(o.open_request_count) open", valueColor: HP.Color.warning)
      HPMetricCard(title: "Overdue", value: o.money(o.overdue_request_balance_cents).formatted(),
                   context: "Past due",
                   valueColor: o.overdue_request_balance_cents > 0 ? HP.Color.danger : HP.Color.textMuted)
      HPMetricCard(title: "Expenses", value: o.money(o.expenses_cents).formatted(), context: "Recorded",
                   valueColor: HP.Color.danger)
      HPMetricCard(title: "Refunds", value: o.money(o.refunds_cents).formatted(), context: "Issued",
                   valueColor: HP.Color.danger)
    }
  }

  private func feesAndActivity(_ o: FinanceOverview) -> some View {
    VStack(alignment: .leading, spacing: HP.Space.xs) {
      Text("FEES & ACTIVITY")
        .font(HP.Font.eyebrow).tracking(HP.Font.eyebrowTracking).foregroundStyle(HP.Color.textMuted)
      VStack(spacing: 0) {
        statRow("Provider fees", o.money(o.provider_fees_cents).formatted())
        rowDivider
        statRow("Platform fees", o.money(o.platform_fees_cents).formatted())
        rowDivider
        statRow("Average payment", o.money(o.average_payment_cents).formatted())
        rowDivider
        statRow("Open requests", "\(o.open_request_count)")
        rowDivider
        statRow("Paid / Canceled", "\(o.paid_request_count) / \(o.canceled_request_count)")
      }
    }
  }

  private func statRow(_ label: String, _ value: String) -> some View {
    HPStatTile(label: label, value: value)
  }

  private var rowDivider: some View { Divider().overlay(HP.Color.border.opacity(0.5)) }
}

// MARK: - Recent payments (HP-styled rich rows — preserves per-record detail)

struct RecentPaymentsView: View {
  let payments: [FinanceRecentPayment]?
  let isLoading: Bool
  let errorMessage: String?
  let onRefresh: () -> Void

  var body: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Recent payments")
        if isLoading, payments == nil {
          HPLoadingState(text: "Loading recent payments…")
        } else if let errorMessage, payments == nil {
          HPErrorState(message: errorMessage, onRetry: onRefresh)
        } else if let payments, !payments.isEmpty {
          ForEach(Array(payments.enumerated()), id: \.element.id) { index, payment in
            row(payment)
            if index < payments.count - 1 { Divider().overlay(HP.Color.border.opacity(0.5)) }
          }
        } else {
          HPEmptyState(title: "No payments",
                       message: "No successful payments in this date range.",
                       systemImage: "creditcard")
        }
      }
    }
  }

  private func row(_ payment: FinanceRecentPayment) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: HP.Space.sm) {
      VStack(alignment: .leading, spacing: 2) {
        Text(payment.grossMoney.formatted()).font(HP.Font.headline).foregroundStyle(HP.Color.text)
        Text("Net \(payment.netMoney.formatted()) · \(payment.provider.capitalized)")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        Text(financeDisplayDate(payment.paid_at ?? payment.created_at))
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
      }
      Spacer(minLength: HP.Space.sm)
      HPStatusBadge(text: payment.status.capitalized, kind: financeStatusKind(payment.status))
    }
    .padding(.vertical, 6)
  }
}

// MARK: - Payment requests (single-select filter pills + rich rows)

struct FinancePaymentRequestsView: View {
  let requests: [FinancePaymentRequestItem]?
  @Binding var filter: FinancePaymentRequestFilter
  let isLoading: Bool
  let errorMessage: String?
  let onRefresh: () -> Void

  var body: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Payment requests")

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: HP.Space.sm) {
            ForEach(FinancePaymentRequestFilter.allCases) { option in
              HPDataPill(label: option.title, isActive: filter == option)
                .onTapGesture { filter = option }
            }
          }
          .padding(.vertical, 2)
        }

        if isLoading, requests == nil {
          HPLoadingState(text: "Loading payment requests…")
        } else if let errorMessage, requests == nil {
          HPErrorState(message: errorMessage, onRetry: onRefresh)
        } else if let requests, !requests.isEmpty {
          ForEach(Array(requests.enumerated()), id: \.element.id) { index, request in
            row(request)
            if index < requests.count - 1 { Divider().overlay(HP.Color.border.opacity(0.5)) }
          }
        } else {
          HPEmptyState(title: "No requests",
                       message: "No \(filter.title.lowercased()) payment requests in this date range.",
                       systemImage: "doc.text")
        }
      }
    }
  }

  private func row(_ request: FinancePaymentRequestItem) -> some View {
    HStack(alignment: .top, spacing: HP.Space.sm) {
      VStack(alignment: .leading, spacing: 3) {
        Text(request.title).font(HP.Font.headline).foregroundStyle(HP.Color.text)
          .fixedSize(horizontal: false, vertical: true)
        Text("Player \(request.child_id.uuidString.lowercased().suffix(6))")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        if let dueDate = request.due_date {
          Text("Due \(dueDate)").font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        }
      }
      Spacer(minLength: HP.Space.sm)
      VStack(alignment: .trailing, spacing: 4) {
        Text(request.money?.formatted() ?? "Amount unavailable")
          .font(HP.Font.callout.weight(.semibold)).foregroundStyle(HP.Color.text)
          .lineLimit(1)
        HPStatusBadge(text: request.status.capitalized, kind: financeStatusKind(request.status))
      }
    }
    .padding(.vertical, 6)
  }
}

// MARK: - Refunds (HP-styled rich rows)

struct FinanceRefundsView: View {
  let refunds: [FinanceRefund]?
  let isLoading: Bool
  let errorMessage: String?
  let onRefresh: () -> Void

  var body: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Refunds")
        if isLoading, refunds == nil {
          HPLoadingState(text: "Loading refunds…")
        } else if let errorMessage, refunds == nil {
          HPErrorState(message: errorMessage, onRetry: onRefresh)
        } else if let refunds, !refunds.isEmpty {
          ForEach(Array(refunds.enumerated()), id: \.element.id) { index, refund in
            row(refund)
            if index < refunds.count - 1 { Divider().overlay(HP.Color.border.opacity(0.5)) }
          }
        } else {
          HPEmptyState(title: "No refunds",
                       message: "No refund records in this date range.",
                       systemImage: "arrow.uturn.backward")
        }
      }
    }
  }

  private func row(_ refund: FinanceRefund) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: HP.Space.sm) {
      VStack(alignment: .leading, spacing: 3) {
        Text(refund.reason?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Refund")
          .font(HP.Font.headline).foregroundStyle(HP.Color.text)
          .fixedSize(horizontal: false, vertical: true)
        Text(financeDisplayDate(refund.created_at))
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
      }
      Spacer(minLength: HP.Space.sm)
      VStack(alignment: .trailing, spacing: 4) {
        Text(refund.money.formatted()).font(HP.Font.callout.weight(.semibold)).foregroundStyle(HP.Color.text)
        HPStatusBadge(text: refund.status.capitalized, kind: financeStatusKind(refund.status))
      }
    }
    .padding(.vertical, 6)
  }
}

// MARK: - Helpers

private func financeDisplayDate(_ value: String) -> String {
  String(value.prefix(10))
}

private func financeStatusKind(_ status: String) -> HPStatusKind {
  switch status.lowercased() {
  case "succeeded", "paid", "completed": .success
  case "open", "pending": .warning
  case "failed", "canceled": .danger
  default: .neutral
  }
}
