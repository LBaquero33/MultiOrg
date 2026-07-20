import SwiftUI

/// Parent-facing child profile:
/// - Read-only performance data
/// - Facilities booking requests on behalf of the child
/// - Manual payment request flow
struct ParentChildProfileView: View {
  @EnvironmentObject private var appState: AppState
  let child: Profile

  enum Tab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case calendar = "Calendar"
    case testing = "Testing"
    case program = "Program"
    case analysis = "Analysis"
    case facilities = "Facilities"
    case billing = "Billing"
    var id: String { rawValue }
  }

  @State private var tab: Tab = .overview

  var body: some View {
    content
      .background(HP.Color.bg)
      .toolbar {
#if os(macOS)
        ToolbarItem(placement: .automatic) {
          adaptiveTabPicker
        }
#else
        ToolbarItem(placement: .principal) {
          adaptiveTabPicker
        }
#endif
      }
      .navigationTitle(child.displayName)
      #if !os(macOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
  }

  @ViewBuilder
  private var adaptiveTabPicker: some View {
    ViewThatFits(in: .horizontal) {
      segmentedTabPicker
      menuTabPicker
    }
  }

  private var segmentedTabPicker: some View {
    Picker("Child profile section", selection: $tab) {
      ForEach(Tab.allCases) { option in
        Text(option.rawValue).tag(option)
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .fixedSize(horizontal: true, vertical: false)
    .accessibilityLabel("Child profile section")
  }

  private var menuTabPicker: some View {
    Picker("Child profile section", selection: $tab) {
      ForEach(Tab.allCases) { option in
        Text(option.rawValue).tag(option)
      }
    }
    .pickerStyle(.menu)
    .accessibilityLabel("Child profile section")
  }

  @ViewBuilder
  private var content: some View {
    switch tab {
    case .overview:
      CoachPlayerOverviewView(player: child)
    case .calendar:
      ParentChildCalendarView(child: child)
    case .testing:
      CoachPlayerTestingEntriesView(player: child)
    case .program:
      ParentChildProgramView(child: child)
    case .analysis:
      CoachPlayerAnalysisView(player: child)
    case .facilities:
      SDParentFacilitiesView(child: child)
    case .billing:
      SDParentBillingView(child: child)
    }
  }
}

private struct ParentChildProgramView: View {
  @EnvironmentObject private var appState: AppState
  let child: Profile

  @State private var assignment: SDProgramAssignment?
  @State private var template: SDProgramTemplate?
  @State private var isLoading = false
  @State private var errorText: String?

  var body: some View {
    HPDetailScreenLayout {
      HPWorkspaceHeader(
        "Program",
        context: "View-only · \(child.displayName)"
      ) {
        if isLoading {
          HPProgressIndicator(style: .spinner)
            .accessibilityLabel("Loading program")
        }
      }
    } metrics: {
      if let template {
        HPMetricCard(
          title: "Weeks",
          value: "\(template.weeks)",
          context: "Program duration"
        )
        HPMetricCard(
          title: "Days per week",
          value: "\(template.lift_weekdays.count)",
          context: "Scheduled training days"
        )
      }
    } details: {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Assignment")
          if let assignment, let template {
            VStack(alignment: .leading, spacing: 3) {
              Text("TEMPLATE")
                .font(HP.Font.eyebrow)
                .tracking(HP.Font.eyebrowTracking)
                .foregroundStyle(HP.Color.textMuted)
              Text(template.name)
                .font(HP.Font.headline)
                .foregroundStyle(HP.Color.text)
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            Divider().overlay(HP.Color.border)
            HPStatTile(label: "Start", value: assignment.start_date)
            HPStatTile(
              label: "Weekdays",
              value: weekdayLabel(template.lift_weekdays)
            )

            if let notes = assignment.notes,
               !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              Divider().overlay(HP.Color.border)
              VStack(alignment: .leading, spacing: HP.Space.xs) {
                Text("NOTES")
                  .font(HP.Font.eyebrow)
                  .tracking(HP.Font.eyebrowTracking)
                  .foregroundStyle(HP.Color.textMuted)
                Text(notes)
                  .font(HP.Font.callout)
                  .foregroundStyle(HP.Color.textMuted)
                  .fixedSize(horizontal: false, vertical: true)
              }
              .accessibilityElement(children: .combine)
            }
          } else {
            HPEmptyState(
              title: "No active program assigned.",
              systemImage: "figure.strengthtraining.traditional"
            )
          }
        }
      }
    } related: { _ in
      EmptyView()
    } primaryAction: {
      EmptyView()
    }
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .task { await reload() }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      assignment = try await supabase.fetchActiveAssignment(playerId: child.id)
      if let assignment {
        template = try await supabase.fetchTemplate(id: assignment.template_id)
      } else {
        template = nil
      }
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func weekdayLabel(_ days: [Int]) -> String {
    let map: [Int: String] = [1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 7: "Sun"]
    return days.compactMap { map[$0] }.joined(separator: ", ")
  }
}
