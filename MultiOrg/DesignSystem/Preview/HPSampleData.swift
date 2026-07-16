import SwiftUI

/// Local mock data for design-system previews only. **No network, no Supabase,
/// no production models.** Used exclusively by `HPComponentGallery`.
enum HPSample {

  /// Example organization identity (brand color drives chrome only).
  static let orgIdentity = HPIdentity(
    name: "Diamond Baseball Academy",
    shortName: "Diamond BA",
    primary: HP.Color.exampleOrg,
    secondary: HP.Color.exampleOrg2
  )

  struct Metric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    var unit: String? = nil
    var delta: String? = nil
    var trend: HPTrendDirection? = nil
    var context: String? = nil
    var valueColor: Color = HP.Color.text
  }

  /// Player-development metrics — value + context.
  static let playerMetrics: [Metric] = [
    Metric(title: "Max Exit Velo", value: "88.4", unit: "mph",
           delta: "3.2 mph / 30 days", trend: .up, context: "Personal best"),
    Metric(title: "Avg Exit Velo", value: "81.6", unit: "mph",
           delta: "1.1 mph / 30 days", trend: .up),
    Metric(title: "Strength Total", value: "545", unit: "lb",
           delta: "10 lb / 30 days", trend: .up, context: "Squat + Bench + DL"),
    Metric(title: "Program", value: "72", unit: "%",
           delta: "Week 4 · Day 2", trend: .flat, context: "Rotational Power"),
  ]

  /// Finance metrics — money with semantic colors.
  static let financeMetrics: [Metric] = [
    Metric(title: "Gross Revenue", value: "$18,240", valueColor: HP.Color.text),
    Metric(title: "Net Revenue", value: "$15,910",
           delta: "vs. $14,200 last period", trend: .up, valueColor: HP.Color.success),
    Metric(title: "Outstanding", value: "$4,320",
           delta: "12 open invoices", trend: .flat, valueColor: HP.Color.warning),
    Metric(title: "Expenses", value: "$6,910",
           delta: "vs. $5,400 last period", trend: .down, valueColor: HP.Color.danger),
    Metric(title: "Est. Profit", value: "$8,000",
           delta: "44% margin", trend: .up, valueColor: HP.Color.success),
  ]

  struct Payment: Identifiable {
    let id = UUID()
    let amount: String
    let net: String
    let provider: String
    let date: String
    let status: String
    let kind: HPStatusKind
  }

  static let recentPayments: [Payment] = [
    Payment(amount: "$149.00", net: "$144.12", provider: "Stripe", date: "Jul 14, 2026", status: "Succeeded", kind: .success),
    Payment(amount: "$99.00", net: "$95.79", provider: "Stripe", date: "Jul 13, 2026", status: "Succeeded", kind: .success),
    Payment(amount: "$60.00", net: "$57.86", provider: "Stripe", date: "Jul 12, 2026", status: "Refunded", kind: .danger),
  ]

  // Charts
  static let trendPoints: [HPChartPoint] = [
    .init(x: "W1", y: 82), .init(x: "W2", y: 83.5), .init(x: "W3", y: 84.1),
    .init(x: "W4", y: 86), .init(x: "W5", y: 87.2), .init(x: "W6", y: 88.4),
  ]
  static let revenuePoints: [HPChartPoint] = [
    .init(x: "Apr", y: 12.4), .init(x: "May", y: 14.2), .init(x: "Jun", y: 15.9), .init(x: "Jul", y: 18.2),
  ]

  // Table (payments)
  static let paymentColumns: [HPColumn] = [
    HPColumn(title: "Player", alignment: .leading),
    HPColumn(title: "Amount", alignment: .trailing, numeric: true),
    HPColumn(title: "Status", alignment: .trailing),
  ]
  static let paymentRows: [HPTableRow] = [
    HPTableRow(cells: ["J. Alvarez", "$149.00", ""], badge: ("Paid", .success)),
    HPTableRow(cells: ["M. Chen", "$99.00", ""], badge: ("Paid", .success)),
    HPTableRow(cells: ["D. Whitfield", "$60.00", ""], badge: ("Overdue", .warning)),
    HPTableRow(cells: ["R. Ortiz", "$60.00", ""], badge: ("Failed", .danger)),
  ]

  // Filters
  static let filterPills = ["All", "Paid", "Overdue", "Refunded", "This month", "Last 90 days"]

  // Navigation (mock role/entitlement configuration)
  static func navGroups(for role: HPRole) -> [HPNavGroup] {
    switch role {
    case .player:
      return [
        HPNavGroup(title: nil, items: [
          HPWorkspaceItem(title: "Overview", icon: "square.grid.2x2"),
          HPWorkspaceItem(title: "Development", icon: "figure.strengthtraining.traditional"),
        ]),
        HPNavGroup(title: "Explore", items: [
          HPWorkspaceItem(title: "Analytics", icon: "chart.xyaxis.line"),
          HPWorkspaceItem(title: "AI", icon: "sparkles", preview: true),
          HPWorkspaceItem(title: "Recruiting", icon: "graduationcap", locked: true),
        ]),
        HPNavGroup(title: "Manage", items: [
          HPWorkspaceItem(title: "Settings", icon: "gearshape"),
        ]),
      ]
    case .coach:
      return [
        HPNavGroup(title: nil, items: [
          HPWorkspaceItem(title: "Overview", icon: "square.grid.2x2"),
          HPWorkspaceItem(title: "Development", icon: "figure.strengthtraining.traditional"),
          HPWorkspaceItem(title: "Game Day", icon: "baseball", preview: true),
          HPWorkspaceItem(title: "Analytics", icon: "chart.xyaxis.line"),
        ]),
        HPNavGroup(title: "Run", items: [
          HPWorkspaceItem(title: "Communication", icon: "bubble.left.and.bubble.right"),
          HPWorkspaceItem(title: "Scheduling", icon: "calendar"),
          HPWorkspaceItem(title: "Facilities", icon: "building.2"),
        ]),
        HPNavGroup(title: "Manage", items: [
          HPWorkspaceItem(title: "Settings", icon: "gearshape"),
        ]),
      ]
    case .owner:
      return [
        HPNavGroup(title: nil, items: [
          HPWorkspaceItem(title: "Overview", icon: "square.grid.2x2"),
        ]),
        HPNavGroup(title: "Run", items: [
          HPWorkspaceItem(title: "Finance", icon: "dollarsign.circle"),
          HPWorkspaceItem(title: "Communication", icon: "bubble.left.and.bubble.right"),
          HPWorkspaceItem(title: "Scheduling", icon: "calendar"),
          HPWorkspaceItem(title: "Facilities", icon: "building.2"),
        ]),
        HPNavGroup(title: "Manage", items: [
          HPWorkspaceItem(title: "Organization", icon: "person.3"),
          HPWorkspaceItem(title: "Advanced Reports", icon: "chart.bar.doc.horizontal", locked: true),
          HPWorkspaceItem(title: "Settings", icon: "gearshape"),
        ]),
      ]
    }
  }
}

/// Mock role for sidebar / directory previews (not the production role model).
enum HPRole: String, CaseIterable, Identifiable {
  case player = "Player"
  case coach = "Coach"
  case owner = "Owner/Admin"
  var id: String { rawValue }
}

/// Mock workspace destination. `locked` = entitlement-gated; `preview` = an
/// intentionally-marked future feature.
struct HPWorkspaceItem: Identifiable, Hashable {
  let id = UUID()
  let title: String
  let icon: String
  var locked: Bool = false
  var preview: Bool = false
}

struct HPNavGroup: Identifiable {
  let id = UUID()
  let title: String?
  let items: [HPWorkspaceItem]
}
