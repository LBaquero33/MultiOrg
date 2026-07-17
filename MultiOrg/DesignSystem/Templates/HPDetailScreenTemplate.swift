import SwiftUI

enum HPDetailMetricGridPolicy {
  static func columnCount(for context: HPScreenLayoutContext) -> Int {
    context.gridColumnCount(compact: 2, regular: 4, wide: 4)
  }

  static func columns(for context: HPScreenLayoutContext) -> [GridItem] {
    Array(
      repeating: GridItem(.flexible(), spacing: HP.Space.sm),
      count: columnCount(for: context)
    )
  }
}

/// Reusable presentation anatomy for a single record's detail workspace.
///
/// The layout standardizes identity, metric, detail, related-record, and action
/// placement while leaving every value and behavior with the feature caller.
struct HPDetailScreenLayout<
  Identity: View,
  Metrics: View,
  Details: View,
  Related: View,
  PrimaryAction: View
>: View {
  private let widthMode: HPScreenWidthMode
  private let identity: Identity
  private let metrics: Metrics
  private let details: Details
  private let related: (HPScreenLayoutContext) -> Related
  private let primaryAction: PrimaryAction

  init(
    widthMode: HPScreenWidthMode = .automatic,
    @ViewBuilder identity: () -> Identity,
    @ViewBuilder metrics: () -> Metrics,
    @ViewBuilder details: () -> Details,
    @ViewBuilder related: @escaping (HPScreenLayoutContext) -> Related,
    @ViewBuilder primaryAction: () -> PrimaryAction
  ) {
    self.widthMode = widthMode
    self.identity = identity()
    self.metrics = metrics()
    self.details = details()
    self.related = related
    self.primaryAction = primaryAction()
  }

  var body: some View {
    HPScreenScaffold(widthMode: widthMode) { context in
      VStack(alignment: .leading, spacing: HP.Space.md) {
        identity
        LazyVGrid(
          columns: HPDetailMetricGridPolicy.columns(for: context),
          spacing: HP.Space.sm
        ) {
          metrics
        }
        details
        related(context)
        primaryAction
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// Template 3 — **Record detail screen**.
///
/// Purpose: everything about one record + its actions. Anatomy:
/// identity header (`HPAvatar` + name + status) → key metrics → detail sections
/// → related records → one primary action.
///
/// Rule: exactly one `.primary` action (the thing you came here to do); every
/// other action is `.secondary`/`.tertiary`.
struct HPDetailScreenTemplate: View {
  @Environment(\.dynamicTypeSize) private var dts

  var isWide: Bool = false

  var body: some View {
    HPDetailScreenLayout(widthMode: isWide ? .automatic : .compact) {
      identityHeader
    } metrics: {
      ForEach(HPSample.playerMetrics) { m in
        HPMetricCard(title: m.title, value: m.value, unit: m.unit,
                     delta: m.delta, trend: m.trend, context: m.context,
                     valueColor: m.valueColor)
      }
    } details: {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Details")
          HPStatTile(label: "Team", value: "14U National")
          HPStatTile(label: "Position", value: "SS / RHP")
          HPStatTile(label: "Joined", value: "Mar 2, 2026")
          HPStatTile(label: "Program", value: "Rotational Power")
        }
      }
    } related: { context in
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Recent testing") {
            HPButton(title: "View all", variant: .tertiary, size: .sm)
          }
          HPTable(columns: [HPColumn(title: "Date"),
                            HPColumn(title: "Max EV", alignment: .trailing, numeric: true),
                            HPColumn(title: "Status", alignment: .trailing)],
                  rows: [HPTableRow(cells: ["Jul 10", "88.4", ""], badge: ("Verified", .success)),
                         HPTableRow(cells: ["Jun 12", "86.1", ""], badge: ("Verified", .success)),
                         HPTableRow(cells: ["May 08", "84.0", ""], badge: ("Unverified", .neutral))],
                  layout: context.tableLayout)
        }
      }
    } primaryAction: {
      HPCard {
        HPButton(title: "Assign program", variant: .primary, size: .lg, fullWidth: true)
      }
    }
  }

  private var identityHeader: some View {
    HPCard {
      // AX3: identity block stacks so the name never truncates next to chips.
      let layout = dts.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
        : AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.md))
      layout {
        HStack(spacing: HP.Space.md) {
          HPAvatar(name: "Jose Alvarez", size: .lg)
          VStack(alignment: .leading, spacing: 2) {
            Text("Jose Alvarez")
              .font(HP.Font.title).tracking(HP.Font.titleTracking)
              .foregroundStyle(HP.Color.text)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityAddTraits(.isHeader)
            Text("14U National · SS / RHP")
              .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
          }
          if !dts.isAccessibilitySize { Spacer(minLength: HP.Space.sm) }
        }
        HStack(spacing: HP.Space.xs) {
          HPStatusBadge(text: "Active", kind: .success)
          HPStatusBadge(text: "Subscribed", kind: .gold)
        }
      }
    }
  }
}

#Preview("Detail — iPhone") { HPDetailScreenTemplate() }
#Preview("Detail — iPad/macOS") { HPDetailScreenTemplate(isWide: true) }
