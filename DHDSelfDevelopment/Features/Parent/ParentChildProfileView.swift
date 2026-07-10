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
      .background(DHDTheme.pageBackground)
      .toolbar {
#if os(macOS)
        ToolbarItem(placement: .automatic) {
          Picker("", selection: $tab) {
            ForEach(Tab.allCases) { t in
              Text(t.rawValue).tag(t)
            }
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 720)
        }
#else
        ToolbarItem(placement: .principal) {
          Picker("", selection: $tab) {
            ForEach(Tab.allCases) { t in
              Text(t.rawValue).tag(t)
            }
          }
          .pickerStyle(.segmented)
        }
#endif
      }
      .navigationTitle(child.displayName)
      #if !os(macOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
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
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        DHDHeaderCard {
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text("Program")
                .font(.title3.weight(.semibold))
              Text("View-only")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.85))
            }
            Spacer()
            if isLoading { ProgressView().tint(.white) }
          }
          .foregroundStyle(.white)
        }

        DHDCard {
          VStack(alignment: .leading, spacing: 10) {
            if let assignment, let template {
              DHDFormRow("Template") { Text(template.name) }
              DHDFormRow("Start") { Text(assignment.start_date) }
              DHDFormRow("Weeks") { Text("\(template.weeks)") }
              DHDFormRow("Days/week") { Text("\(template.lift_weekdays.count)") }
              DHDFormRow("Weekdays") { Text(weekdayLabel(template.lift_weekdays)) }
              if let notes = assignment.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider().overlay(DHDTheme.separator.opacity(0.35))
                Text(notes).foregroundStyle(DHDTheme.textSecondary)
              }
            } else {
              Text("No active program assigned.")
                .foregroundStyle(DHDTheme.textSecondary)
            }
          }
        }
      }
      .padding(DHDTheme.pagePadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(maxHeight: .infinity, alignment: .topLeading)
    }
    .background(DHDTheme.pageBackground)
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
