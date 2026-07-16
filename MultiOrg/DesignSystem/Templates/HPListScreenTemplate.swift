import SwiftUI

/// Template 2 — **List / search / filter screen**.
///
/// Purpose: find one record among many. Anatomy: `HPWorkspaceHeader` →
/// `HPSearchBar` → `HPFilterBar` → result count → rows (`HPTable` on wide,
/// stacked cards on compact) → empty/loading/error.
///
/// Rule: filters are single-purpose pills; the result count is always visible so
/// an empty result never looks like a broken screen.
struct HPListScreenTemplate: View {
  @Environment(\.dynamicTypeSize) private var dts

  var isWide: Bool = false
  /// Drives the state matrix without any production data source.
  var state: HPTemplateState = .loaded

  @State private var query = ""
  @State private var active: Set<String> = ["Paid"]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPWorkspaceHeader("Payments",
                          orgLabel: HPSample.orgIdentity.name,
                          context: "All payment requests",
                          identity: HPSample.orgIdentity) {
          HPButton(title: "New request", systemImage: "plus", variant: .primary, size: .sm)
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSearchBar(text: $query, placeholder: "Search player or title")
            HPFilterBar(pills: HPSample.filterPills, active: $active)
            Text("\(HPSample.paymentRows.count) results")
              .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
          }
        }

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
                           actionIsPrimary: false)
            case .error:
              HPErrorState(message: "We couldn’t load payments. Check your connection and try again.",
                           onRetry: {})
            case .loaded:
              // HPTable auto-stacks on compact/AX3 — never a squeezed grid.
              HPTable(columns: HPSample.paymentColumns,
                      rows: HPSample.paymentRows,
                      layout: dts.isAccessibilitySize ? .stacked : (isWide ? .columns : .auto))
            }
          }
        }
      }
      .padding(HP.Space.md)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(HP.Color.bg)
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
