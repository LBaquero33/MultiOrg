import SwiftUI

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
          .background(DHDTheme.pageBackground)
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
    VStack(alignment: .leading, spacing: 14) {
      if platformSupportMode {
        DHDCard {
          VStack(alignment: .leading, spacing: 5) {
            Label(
              "Platform Support — viewing finance for \(organizationName)",
              systemImage: "person.badge.shield.checkmark"
            )
            .font(.headline)
            Text("This does not make you an organization owner or member.")
              .font(.footnote)
              .foregroundStyle(DHDTheme.textSecondary)
          }
        }
      }

      FinanceDateRangePicker(
        selection: $viewModel.rangeSelection,
        serverRange: viewModel.snapshot?.overview.overview.range,
        isLoading: viewModel.isLoading,
        onRefresh: { Task { await refresh() } }
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
    .padding(embedded ? 0 : DHDTheme.pagePadding)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func refresh() async {
    await viewModel.refresh(
      organizationId: organizationId,
      supportMode: platformSupportMode,
      service: appState.supabase
    )
  }
}

struct FinanceDateRangePicker: View {
  @Binding var selection: FinanceDateRangeSelection
  let serverRange: FinanceServerDateRange?
  let isLoading: Bool
  let onRefresh: () -> Void

  var body: some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 10) {
        DHDSectionHeader("Finance Date Range") {
          Button(action: onRefresh) {
            Label("Refresh", systemImage: "arrow.clockwise")
          }
          .disabled(isLoading)
        }
        Picker("Date range", selection: $selection.preset) {
          ForEach(FinanceDateRangePreset.allCases) { preset in
            Text(preset.title).tag(preset)
          }
        }
        #if os(macOS)
        .pickerStyle(.segmented)
        #else
        .pickerStyle(.menu)
        #endif

        if selection.preset == .custom {
          HStack {
            DatePicker("Start", selection: $selection.customStart, displayedComponents: .date)
            DatePicker("End", selection: $selection.customEnd, displayedComponents: .date)
          }
          if !selection.isValid {
            Text("Start must not be after end.")
              .font(.footnote)
              .foregroundStyle(.red)
          }
        }

        if let serverRange {
          Text("\(serverRange.start_date) through \(serverRange.end_date) • \(serverRange.timezone)")
            .font(.footnote)
            .foregroundStyle(DHDTheme.textSecondary)
        }
        Text("Organization settings do not currently store a timezone, so Phase 8A uses UTC date boundaries.")
          .font(.caption)
          .foregroundStyle(DHDTheme.textSecondary)
      }
    }
  }
}

struct FinanceOverviewView: View {
  let overview: FinanceOverview?
  let isLoading: Bool
  let errorMessage: String?
  let onRefresh: () -> Void

  var body: some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        FinanceSectionHeader(title: "Overview", isLoading: isLoading, onRefresh: onRefresh)
        if isLoading, overview == nil {
          FinanceLoadingState(text: "Loading finance overview…")
        } else if let errorMessage {
          FinanceErrorState(message: errorMessage, onRefresh: onRefresh)
        } else if let overview {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
            FinanceMetricCard(title: "Gross Revenue", money: overview.money(overview.gross_revenue_cents), color: .blue)
            FinanceMetricCard(title: "Net Revenue", money: overview.money(overview.net_payment_revenue_cents), color: .green)
            FinanceMetricCard(title: "Outstanding", money: overview.money(overview.open_request_balance_cents), color: .orange)
            FinanceMetricCard(title: "Expenses", money: overview.money(overview.expenses_cents), color: .red)
            FinanceMetricCard(title: "Estimated Profit", money: overview.money(overview.estimated_profit_cents), color: .mint)
          }
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 8) {
            FinanceCompactMetric(title: "Payments", value: "\(overview.successful_payment_count)")
            FinanceCompactMetric(title: "Average Payment", value: overview.money(overview.average_payment_cents).formatted())
            FinanceCompactMetric(title: "Refunds", value: overview.money(overview.refunds_cents).formatted())
            FinanceCompactMetric(title: "Open Requests", value: "\(overview.open_request_count)")
            FinanceCompactMetric(title: "Overdue", value: overview.money(overview.overdue_request_balance_cents).formatted())
            FinanceCompactMetric(title: "Paid / Canceled", value: "\(overview.paid_request_count) / \(overview.canceled_request_count)")
          }
          Text("Net revenue = gross − successful refunds − provider fees − Home Plate application fees. Estimated profit also subtracts recorded expenses.")
            .font(.caption)
            .foregroundStyle(DHDTheme.textSecondary)
        } else {
          FinanceEmptyState(text: "No finance overview has been loaded.")
        }
      }
    }
  }
}

struct FinanceMetricCard: View {
  let title: String
  let money: SDMoney
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.caption).foregroundStyle(DHDTheme.textSecondary)
      Text(money.formatted()).font(.title3.weight(.bold)).foregroundStyle(color)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(DHDTheme.cardSurface.opacity(0.72))
    .clipShape(RoundedRectangle(cornerRadius: DHDTheme.innerCornerRadius))
  }
}

private struct FinanceCompactMetric: View {
  let title: String
  let value: String

  var body: some View {
    HStack {
      Text(title).font(.caption).foregroundStyle(DHDTheme.textSecondary)
      Spacer()
      Text(value).font(.caption.weight(.semibold))
    }
    .padding(.vertical, 5)
  }
}

struct RecentPaymentsView: View {
  let payments: [FinanceRecentPayment]?
  let isLoading: Bool
  let errorMessage: String?
  let onRefresh: () -> Void

  var body: some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 10) {
        FinanceSectionHeader(title: "Recent Payments", isLoading: isLoading, onRefresh: onRefresh)
        if isLoading, payments == nil {
          FinanceLoadingState(text: "Loading recent payments…")
        } else if let errorMessage {
          FinanceErrorState(message: errorMessage, onRefresh: onRefresh)
        } else if let payments, !payments.isEmpty {
          ForEach(payments) { payment in
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text(payment.grossMoney.formatted()).font(.headline)
                Spacer()
                DHDStatusBadge(text: payment.status.capitalized, color: .green)
              }
              Text("Net \(payment.netMoney.formatted()) • \(payment.provider.capitalized)")
                .font(.caption)
                .foregroundStyle(DHDTheme.textSecondary)
              Text(financeDisplayDate(payment.paid_at ?? payment.created_at))
                .font(.caption2)
                .foregroundStyle(DHDTheme.textSecondary)
            }
            Divider().overlay(DHDTheme.separator.opacity(0.3))
          }
        } else {
          FinanceEmptyState(text: "No successful payments in this date range.")
        }
      }
    }
  }
}

struct FinancePaymentRequestsView: View {
  let requests: [FinancePaymentRequestItem]?
  @Binding var filter: FinancePaymentRequestFilter
  let isLoading: Bool
  let errorMessage: String?
  let onRefresh: () -> Void

  var body: some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 10) {
        FinanceSectionHeader(title: "Payment Requests", isLoading: isLoading, onRefresh: onRefresh)
        Picker("Request filter", selection: $filter) {
          ForEach(FinancePaymentRequestFilter.allCases) { option in
            Text(option.title).tag(option)
          }
        }
        .pickerStyle(.segmented)
        if isLoading, requests == nil {
          FinanceLoadingState(text: "Loading payment requests…")
        } else if let errorMessage {
          FinanceErrorState(message: errorMessage, onRefresh: onRefresh)
        } else if let requests, !requests.isEmpty {
          ForEach(requests) { request in
            HStack(alignment: .top, spacing: 10) {
              VStack(alignment: .leading, spacing: 3) {
                Text(request.title).font(.headline)
                Text("Player \(request.child_id.uuidString.lowercased().suffix(6))")
                  .font(.caption)
                  .foregroundStyle(DHDTheme.textSecondary)
                if let dueDate = request.due_date {
                  Text("Due \(dueDate)").font(.caption2).foregroundStyle(DHDTheme.textSecondary)
                }
              }
              Spacer()
              VStack(alignment: .trailing, spacing: 4) {
                Text(request.money?.formatted() ?? "Amount unavailable").font(.subheadline.weight(.semibold))
                DHDStatusBadge(text: request.status.capitalized, color: financeStatusColor(request.status))
              }
            }
            Divider().overlay(DHDTheme.separator.opacity(0.3))
          }
        } else {
          FinanceEmptyState(text: "No \(filter.title.lowercased()) payment requests in this date range.")
        }
      }
    }
  }
}

struct FinanceRefundsView: View {
  let refunds: [FinanceRefund]?
  let isLoading: Bool
  let errorMessage: String?
  let onRefresh: () -> Void

  var body: some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 10) {
        FinanceSectionHeader(title: "Refunds", isLoading: isLoading, onRefresh: onRefresh)
        if isLoading, refunds == nil {
          FinanceLoadingState(text: "Loading refunds…")
        } else if let errorMessage {
          FinanceErrorState(message: errorMessage, onRefresh: onRefresh)
        } else if let refunds, !refunds.isEmpty {
          ForEach(refunds) { refund in
            HStack {
              VStack(alignment: .leading, spacing: 3) {
                Text(refund.reason?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Refund")
                  .font(.headline)
                Text(financeDisplayDate(refund.created_at))
                  .font(.caption)
                  .foregroundStyle(DHDTheme.textSecondary)
              }
              Spacer()
              VStack(alignment: .trailing, spacing: 4) {
                Text(refund.money.formatted()).font(.subheadline.weight(.semibold))
                DHDStatusBadge(text: refund.status.capitalized, color: financeStatusColor(refund.status))
              }
            }
            Divider().overlay(DHDTheme.separator.opacity(0.3))
          }
        } else {
          FinanceEmptyState(text: "No refund records in this date range.")
        }
      }
    }
  }
}

private struct FinanceSectionHeader: View {
  let title: String
  let isLoading: Bool
  let onRefresh: () -> Void

  var body: some View {
    DHDSectionHeader(title) {
      Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }
        .buttonStyle(.borderless)
        .disabled(isLoading)
        .accessibilityLabel("Refresh \(title)")
    }
  }
}

private struct FinanceLoadingState: View {
  let text: String
  var body: some View { HStack { ProgressView(); Text(text).foregroundStyle(DHDTheme.textSecondary) } }
}

private struct FinanceEmptyState: View {
  let text: String
  var body: some View { Text(text).foregroundStyle(DHDTheme.textSecondary) }
}

private struct FinanceErrorState: View {
  let message: String
  let onRefresh: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(message).font(.footnote).foregroundStyle(.red)
      Button("Try Again", action: onRefresh).buttonStyle(.bordered)
    }
  }
}

private func financeDisplayDate(_ value: String) -> String {
  String(value.prefix(10))
}

private func financeStatusColor(_ status: String) -> Color {
  switch status.lowercased() {
  case "succeeded", "paid", "completed": return .green
  case "open", "pending": return .orange
  case "failed", "canceled": return .red
  default: return DHDTheme.accent
  }
}
