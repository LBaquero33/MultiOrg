import SwiftUI

enum WARTrainingWorkspaceMode: String, CaseIterable, Identifiable {
  case athletes = "Athletes"
  case trainers = "Trainers"
  case lessons = "Lessons & Sessions"
  case testing = "Testing"
  case dataLab = "WAR Data Lab"
  var id: String { rawValue }
  var symbol: String {
    switch self {
    case .athletes: "figure.run"
    case .trainers: "person.2.badge.gearshape"
    case .lessons: "calendar.badge.clock"
    case .testing: "testtube.2"
    case .dataLab: "chart.xyaxis.line"
    }
  }
  var context: String {
    switch self {
    case .athletes: "Direct athlete affiliations and trainer assignments"
    case .trainers: "Services, disciplines, availability, and assigned athletes"
    case .lessons: "Athlete, trainer, service, location, resource, and payment in one appointment"
    case .testing: "WAR assessments and imported provider sessions"
    case .dataLab: "Blast, Rapsodo, 4D Motion, combined performance, trends, and source coverage"
    }
  }
}

struct WARTrainingOperationsView: View {
  @EnvironmentObject private var appState: AppState
  @State private var dataLabTab = "Overview"
  let mode: WARTrainingWorkspaceMode

  var body: some View {
    HPListScreenLayout {
      HPWorkspaceHeader(mode.rawValue, context: mode.context)
    } controls: {
      if mode == .dataLab {
        HPSegmentedControl(
          options: ["Overview", "Blast", "Rapsodo", "4D", "Combined"].map { (value: $0, label: $0) },
          selection: $dataLabTab
        )
      } else {
        EmptyView()
      }
    } results: { _ in
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            Label(mode.rawValue, systemImage: mode.symbol)
              .font(.headline)
            Text(mode.context)
              .foregroundStyle(DHDTheme.textSecondary)
            if let experience = appState.activeOrganizationExperience {
              Text("Connected as \(experience.current_role.replacingOccurrences(of: "_", with: " ").capitalized)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DHDTheme.accent)
            }
          }
        }

        if mode == .dataLab {
          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              HPSectionHeader("Shared analytics contract")
              ForEach(["Athlete Overview", "Session Detail", "Blast", "Rapsodo", "4D Motion", "Combined Performance", "Trends", "Athlete Comparison", "Reports", "Source Files"], id: \.self) { item in
                Label(item, systemImage: "checkmark.circle")
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
          }
        } else {
          HPCard {
            HPEmptyState(
              title: "No \(mode.rawValue.lowercased()) loaded",
              message: "This workspace is ready for reconciled WAR records from the shared Home Plate service.",
              systemImage: mode.symbol
            )
          }
        }
      }
    }
    .navigationTitle(mode.rawValue)
  }
}
