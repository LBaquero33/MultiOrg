import SwiftUI

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

  private var metricColumns: [GridItem] {
    if dts.isAccessibilitySize { return [GridItem(.flexible())] }
    return isWide
      ? [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
      : [GridItem(.flexible()), GridItem(.flexible())]
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        identityHeader

        LazyVGrid(columns: metricColumns, spacing: HP.Space.sm) {
          ForEach(HPSample.playerMetrics) { m in
            HPMetricCard(title: m.title, value: m.value, unit: m.unit,
                         delta: m.delta, trend: m.trend, context: m.context,
                         valueColor: m.valueColor)
          }
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Details")
            HPStatTile(label: "Team", value: "14U National")
            HPStatTile(label: "Position", value: "SS / RHP")
            HPStatTile(label: "Joined", value: "Mar 2, 2026")
            HPStatTile(label: "Program", value: "Rotational Power")
          }
        }

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
                    layout: dts.isAccessibilitySize ? .stacked : .auto)
          }
        }

        HPCard {
          HPButton(title: "Assign program", variant: .primary, size: .lg, fullWidth: true)
        }
      }
      .padding(HP.Space.md)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(HP.Color.bg)
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
