import SwiftUI

struct SDPlayerCalendarView: View {
  @EnvironmentObject private var appState: AppState

  @State private var assignment: SDProgramAssignment?
  @State private var template: SDProgramTemplate?
  @State private var bpSessions: [SDBPSession] = []
  @State private var isLoading = false
  @State private var errorText: String?

  @State private var visibleMonth: Date = DateUtils.startOfMonthET(Date())
  @State private var scheduledLiftISOs: Set<String> = []
  @State private var practiceISOs: Set<String> = []
  @State private var gameISOs: Set<String> = []
  @State private var selectedDate: Date = DateUtils.startOfDayET(Date())
  @State private var navPath = NavigationPath()

  var body: some View {
    NavigationStack(path: $navPath) {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          DHDMonthGridView(
            visibleMonth: $visibleMonth,
            selectedDate: $selectedDate,
            scheduledLiftISOs: scheduledLiftISOs,
            practiceISOs: practiceISOs,
            gameISOs: gameISOs,
            isLoading: isLoading,
            onPrev: {
              visibleMonth = DateUtils.startOfMonthET(DateUtils.addMonthsET(visibleMonth, value: -1))
              rebuildMonthGrid()
            },
            onNext: {
              visibleMonth = DateUtils.startOfMonthET(DateUtils.addMonthsET(visibleMonth, value: 1))
              rebuildMonthGrid()
            },
            onSelect: { date in
              // Ensure the navigation push happens reliably even during grid/layout updates.
              let sd = DateUtils.startOfDayET(date)
              selectedDate = sd
              DispatchQueue.main.async {
                navPath.append(sd)
              }
            }
          )

          Text("Green = scheduled lift day. Blue = BP/practice. Red = game reps.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
        .padding(DHDTheme.pagePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
      }
      .navigationTitle("Calendar")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Menu {
            Button {
              Task { await reload() }
            } label: {
              Label("Refresh", systemImage: "arrow.clockwise")
            }
            Button(role: .destructive) {
              Task { await appState.signOut() }
            } label: {
              Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
        }
      }
      .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorText ?? "")
      }
      .task {
        await reload()
      }
      .navigationDestination(for: Date.self) { d in
        SDPlayerDayDetailView(initialDate: d)
      }
    }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let session = try await supabase.client.auth.session
      let uid = session.user.id
      assignment = try await supabase.fetchActiveAssignment(playerId: uid)
      if let assignment {
        template = try await supabase.fetchTemplate(id: assignment.template_id)
      } else {
        template = nil
      }
      bpSessions = try await supabase.listBPSessions(playerId: uid, limit: 180)
      rebuildMonthGrid()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func rebuildMonthGrid() {
    scheduledLiftISOs = scheduledLiftSet(for: visibleMonth)
    practiceISOs = Set(bpSessions.filter { $0.reps_type == "practice" }.map(\.session_date))
    gameISOs = Set(bpSessions.filter { $0.reps_type == "game" }.map(\.session_date))
  }

  private func scheduledLiftSet(for monthStart: Date) -> Set<String> {
    guard let assignment, let template else { return [] }
    let first = DateUtils.startOfMonthET(monthStart)
    let days = DateUtils.daysInMonthET(first)
    var out: Set<String> = []
    for i in 0..<days {
      guard let d = DateUtils.calendarET.date(byAdding: .day, value: i, to: first) else { continue }
      if SDProgramSchedule.context(for: d, assignment: assignment, template: template).isScheduled {
        out.insert(DateUtils.toISODate(d))
      }
    }
    return out
  }
}

// A dedicated screen for editing/viewing a chosen day.
// Uses the same UI as Today, just pre-seeded with the selected date.
private struct SDPlayerDayDetailView: View {
  let initialDate: Date
  var body: some View {
    SDPlayerTodayViewWrapper(initialDate: initialDate)
  }
}

// Wrapper around SDPlayerTodayView to seed the initial date cleanly.
private struct SDPlayerTodayViewWrapper: View {
  let initialDate: Date
  var body: some View {
    SDPlayerTodayViewSeeded(initialDate: initialDate)
  }
}

// Separate type so SwiftUI treats it as distinct and keeps state isolated per navigation.
private struct SDPlayerTodayViewSeeded: View {
  let initialDate: Date
  var body: some View {
    SDPlayerTodayViewInternal(initialDate: initialDate)
  }
}
