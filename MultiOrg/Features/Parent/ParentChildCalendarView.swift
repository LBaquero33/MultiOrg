import SwiftUI

/// Month grid + day tap → view-only day details (no CSV upload for parents).
struct ParentChildCalendarView: View {
  @EnvironmentObject private var appState: AppState
  let child: Profile

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
  @State private var daySheet: DaySheet?

  var body: some View {
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
          onSelect: { d in
            let sd = DateUtils.startOfDayET(d)
            selectedDate = sd
            daySheet = DaySheet(date: sd)
          }
        )

        Text("Green = scheduled lift day. Blue = BP/practice. Red = game reps.")
          .font(.footnote)
          .foregroundStyle(DHDTheme.textSecondary)
          .padding(.top, 2)
      }
      .padding(DHDTheme.pagePadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(maxHeight: .infinity, alignment: .topLeading)
    }
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .task { await reload() }
    #if os(macOS)
    .dhdFloatingModal(item: $daySheet, width: 920, height: 640) { s in
      NavigationStack {
        ParentChildDayDetailView(child: child, date: s.date)
          .navigationTitle(DateUtils.toISODate(s.date))
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Close") { daySheet = nil }
            }
          }
      }
    }
    #else
    .sheet(item: $daySheet) { s in
      NavigationStack {
        ParentChildDayDetailView(child: child, date: s.date)
          .navigationTitle(DateUtils.toISODate(s.date))
          .navigationBarTitleDisplayMode(.inline)
      }
    }
    #endif
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
      bpSessions = try await supabase.listBPSessions(playerId: child.id, limit: 365)
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

private struct DaySheet: Identifiable {
  let id = UUID()
  let date: Date
}

private struct ParentChildDayDetailView: View {
  @EnvironmentObject private var appState: AppState
  let child: Profile
  let date: Date

  @State private var log: SDDailyLog?
  @State private var strength: [SDStrengthLog] = []
  @State private var sessions: [SDBPSession] = []
  @State private var bpEvents: [SDBPEvent] = []
  @State private var isLoading = false
  @State private var errorText: String?

  private var dateISO: String { DateUtils.toISODate(date) }

  var body: some View {
    List {
      if isLoading {
        HStack(spacing: 10) { ProgressView(); Text("Loading…").foregroundStyle(DHDTheme.textSecondary) }
      }

      Section("Self assessment") {
        row("Got video", log?.got_video)
        row("Ate breakfast", log?.ate_breakfast)
        row("Hit daily goals", log?.hit_daily_goals)
        row("Stuck to process", log?.stuck_to_process)
        if let t = log?.fell_short, !t.isEmpty { Text("Fell short: \(t)") }
        if let t = log?.excelled, !t.isEmpty { Text("Excelled: \(t)") }
      }

      if let c = log?.comments, !c.isEmpty || log?.feel != nil {
        Section("Lift note") {
          if let f = log?.feel { Text("Feel: \(f)") }
          if let c = log?.comments, !c.isEmpty { Text(c) }
        }
      }

      Section("Strength logs") {
        if strength.isEmpty {
          Text("No strength logs for this day.").foregroundStyle(DHDTheme.textSecondary)
        } else {
          ForEach(strength) { s in
            VStack(alignment: .leading, spacing: 4) {
              Text(s.exercise_name).font(.headline)
              if s.no_weight {
                Text("No weight • Sets completed: \(s.sets_completed ?? 0)")
                  .font(.caption)
                  .foregroundStyle(DHDTheme.textSecondary)
              } else if let w = s.set_weights_json, !w.isEmpty {
                Text("Weights: " + w.joined(separator: ", "))
                  .font(.caption)
                  .foregroundStyle(DHDTheme.textSecondary)
              } else {
                Text("No weights logged").font(.caption).foregroundStyle(DHDTheme.textSecondary)
              }
              if let n = s.notes, !n.isEmpty {
                Text(n).font(.caption).foregroundStyle(DHDTheme.textSecondary)
              }
            }
            .padding(.vertical, 4)
          }
        }
      }

      Section("BP sessions") {
        if sessions.isEmpty {
          Text("No BP session for this day.").foregroundStyle(DHDTheme.textSecondary)
        } else {
          ForEach(sessions) { s in
            VStack(alignment: .leading, spacing: 4) {
              Text("\(s.source.uppercased()) • \(s.reps_type)")
                .font(.headline)
              Text("Events: \(bpEvents.count)")
                .font(.caption)
                .foregroundStyle(DHDTheme.textSecondary)
            }
          }
        }
      }
    }
    .dhdPageBackground()
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
      log = try await supabase.fetchDailyLog(playerId: child.id, dateISO: dateISO)
      strength = try await supabase.fetchStrengthLogs(playerId: child.id, dateISO: dateISO)
      let all = try await supabase.listBPSessions(playerId: child.id, limit: 365)
      sessions = all.filter { $0.session_date == dateISO }
      bpEvents = []
      for s in sessions {
        let ev = try await supabase.fetchBPEvents(sessionId: s.id)
        bpEvents.append(contentsOf: ev)
      }
    } catch {
      errorText = error.localizedDescription
    }
  }

  @ViewBuilder private func row(_ label: String, _ value: Bool?) -> some View {
    HStack {
      Text(label)
      Spacer()
      if value == true {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
      } else if value == false {
        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
      } else {
        Text("—").foregroundStyle(DHDTheme.textSecondary)
      }
    }
  }
}
