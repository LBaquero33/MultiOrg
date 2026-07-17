import SwiftUI

/// Reusable presentation anatomy for a searchable, filterable record list.
///
/// Feature code injects the header, controls, and results. The results builder
/// receives the resolved layout context so production tables deterministically
/// stack on compact widths and at accessibility Dynamic Type sizes.
struct HPListScreenLayout<Header: View, Controls: View, Results: View>: View {
  private let widthMode: HPScreenWidthMode
  private let header: Header
  private let controls: Controls
  private let results: (HPScreenLayoutContext) -> Results

  init(
    widthMode: HPScreenWidthMode = .automatic,
    @ViewBuilder header: () -> Header,
    @ViewBuilder controls: () -> Controls,
    @ViewBuilder results: @escaping (HPScreenLayoutContext) -> Results
  ) {
    self.widthMode = widthMode
    self.header = header()
    self.controls = controls()
    self.results = results
  }

  var body: some View {
    HPScreenScaffold(widthMode: widthMode) { context in
      VStack(alignment: .leading, spacing: HP.Space.md) {
        header
        controls
        results(context)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// Template 2 — **List / search / filter screen**.
///
/// Purpose: find one record among many. Anatomy: `HPWorkspaceHeader` →
/// `HPSearchBar` → `HPFilterBar` → result count → rows (`HPTable` on wide,
/// stacked cards on compact) → empty/loading/error.
///
/// Rule: filters are single-purpose pills; the result count is always visible so
/// an empty result never looks like a broken screen.
struct HPListScreenTemplate: View {
  var isWide: Bool = false
  /// Drives the state matrix without any production data source.
  var state: HPTemplateState = .loaded

  @State private var query = ""
  @State private var active: Set<String> = ["Paid"]

  var body: some View {
    HPListScreenLayout(widthMode: isWide ? .automatic : .compact) {
      HPWorkspaceHeader("Payments",
                        orgLabel: HPSample.orgIdentity.name,
                        context: "All payment requests",
                        identity: HPSample.orgIdentity) {
        HPButton(title: "New request", systemImage: "plus", variant: .primary, size: .sm)
      }
    } controls: {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSearchBar(text: $query, placeholder: "Search player or title")
          HPFilterBar(pills: HPSample.filterPills, active: $active)
          Text("\(HPSample.paymentRows.count) results")
            .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        }
      }
    } results: { context in
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Results")
          switch state {
          case .loading:
            HPLoadingState(text: "Loading payments…")
          case .empty:
            HPEmptyState(title: "No payments match",
                         message: "Try clearing a filter or searching a different player.",
                         systemImage: "magnifyingglass",
                         actionTitle: "Clear filters",
                         actionIsPrimary: false,
                         action: clearFilters)
          case .error:
            HPErrorState(message: "We couldn’t load payments. Check your connection and try again.",
                         onRetry: {})
          case .loaded:
            HPTable(columns: HPSample.paymentColumns,
                    rows: HPSample.paymentRows,
                    layout: context.tableLayout)
          }
        }
      }
    }
  }

  private func clearFilters() {
    query = ""
    active.removeAll()
  }
}

/// Shared state matrix for template previews — every template must be able to
/// show each of these without inventing new visuals.
enum HPTemplateState: String, CaseIterable, Identifiable {
  case loaded, loading, empty, error
  var id: String { rawValue }
}

#Preview("List — iPhone") { HPListScreenTemplate() }
#Preview("List — iPad/macOS") { HPListScreenTemplate(isWide: true) }
#Preview("List — empty") { HPListScreenTemplate(state: .empty) }
