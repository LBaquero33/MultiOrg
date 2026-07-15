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
}
