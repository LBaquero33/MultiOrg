import SwiftUI

/// Reusable presentation anatomy for a Home Plate workspace dashboard.
///
/// Callers inject every feature-specific view and retain ownership of data,
/// actions, navigation, authorization, and lifecycle. The layout owns only the
/// standard screen scaffold and deterministic responsive metric grid.
struct HPWorkspaceScreenLayout<Header: View, Attention: View, Metrics: View, Supporting: View>: View {
  private let widthMode: HPScreenWidthMode
  private let header: Header
  private let attention: Attention
  private let metrics: Metrics
  private let supporting: Supporting

  init(
    widthMode: HPScreenWidthMode = .automatic,
    @ViewBuilder header: () -> Header,
    @ViewBuilder attention: () -> Attention,
    @ViewBuilder metrics: () -> Metrics,
    @ViewBuilder supporting: () -> Supporting
  ) {
    self.widthMode = widthMode
    self.header = header()
    self.attention = attention()
    self.metrics = metrics()
    self.supporting = supporting()
  }

  var body: some View {
    HPScreenScaffold(widthMode: widthMode) { context in
      VStack(alignment: .leading, spacing: HP.Space.md) {
        header
        attention
        LazyVGrid(
          columns: context.gridColumns(compact: 2, regular: 3),
          spacing: HP.Space.sm
        ) {
          metrics
        }
        supporting
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// Template 1 — **Workspace dashboard**.
///
/// Purpose: orient the user, surface what needs attention, offer one primary
/// action. Anatomy: `HPWorkspaceHeader` → attention row → metric grid →
/// supporting cards.
///
/// Responsive: iPhone = single column stack; iPad/macOS = 2/3-column metric
/// grid; AX3 = forced single column (grid collapses).
struct HPWorkspaceScreenTemplate: View {
  @Environment(\.dynamicTypeSize) private var dts

  /// Width buckets drive layout without depending on production navigation.
  var isWide: Bool = false

  var body: some View {
    HPWorkspaceScreenLayout(widthMode: isWide ? .automatic : .compact) {
      HPWorkspaceHeader("Overview",
                        orgLabel: HPSample.orgIdentity.name,
                        context: "Tuesday, July 14 · 3 items need you",
                        identity: HPSample.orgIdentity) {
        HPButton(title: "New request", systemImage: "plus", variant: .primary, size: .sm)
      }
    } attention: {
      // Attention row — 0…3 items, never more. Each is one tap to the item.
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Needs attention") {
            HPStatusBadge(text: "3", kind: .warning)
          }
          attentionRow(icon: "creditcard", title: "2 overdue payment requests", kind: .danger, badge: "Overdue")
          attentionRow(icon: "calendar.badge.exclamationmark", title: "Booking conflict — Cage 2", kind: .warning, badge: "Conflict")
          attentionRow(icon: "person.badge.plus", title: "1 membership request", kind: .info, badge: "Review")
        }
      }
    } metrics: {
      // Metric grid — context over raw numbers.
      ForEach(HPSample.financeMetrics) { m in
        HPMetricCard(title: m.title, value: m.value, unit: m.unit,
                     delta: m.delta, trend: m.trend, context: m.context,
                     valueColor: m.valueColor)
      }
    } supporting: {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Today") {
            HPButton(title: "Open", variant: .tertiary, size: .sm)
          }
          ForEach(HPSample.recentPayments) { p in
            HPStatTile(label: "\(p.provider) · \(p.date)", value: p.amount,
                       systemImage: "clock", valueColor: p.kind.color)
          }
        }
      }
    }
  }

  private func attentionRow(icon: String, title: String, kind: HPStatusKind, badge: String) -> some View {
    // AX3: stack the badge under the label instead of truncating either.
    let layout = dts.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
      : AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.sm))
    return layout {
      HStack(spacing: HP.Space.sm) {
        Image(systemName: icon).foregroundStyle(kind.color)
        Text(title)
          .font(HP.Font.callout).foregroundStyle(HP.Color.text)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      HPStatusBadge(text: badge, kind: kind)
    }
    .padding(.vertical, 4)
  }
}

#Preview("Workspace — iPhone") {
  HPWorkspaceScreenTemplate()
}

#Preview("Workspace — iPad/macOS") {
  HPWorkspaceScreenTemplate(isWide: true)
}
