import SwiftUI

struct SDPlayerCalendarView: View {
  @EnvironmentObject private var appState: AppState

  @State private var assignment: SDProgramAssignment?
  @State private var template: SDProgramTemplate?
  @State private var bpSessions: [SDBPSession] = []
  @State private var teamEvents: [SDTeamEvent] = []
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
      HPCalendarScreenLayout(compactPane: .calendar) { _ in
        HPWorkspaceHeader(
          "Calendar",
          orgLabel: activeOrganizationName,
          context: DateUtils.monthTitle(visibleMonth)
        )
      } scopeControl: { context in
        if context.isAccessibilitySize {
          DHDCalendarMonthHeader(
            title: DateUtils.monthTitle(visibleMonth),
            subtitle: "Choose a day from the agenda",
            onPrevious: showPreviousMonth,
            onNext: showNextMonth
          )
        }
      } calendar: { _ in
        calendarPane
      } agenda: { context in
        agendaPane(context)
      } stateContent: { _ in
        EmptyView()
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

  private var activeOrganizationName: String {
    appState.availableOrganizations.first(where: { $0.id == appState.activeOrgId })?.name
      ?? appState.activeOrgSettings?.display_name
      ?? appState.activeOrgSettings?.short_name
      ?? "Home Plate"
  }

  private var calendarPane: some View {
    VStack(alignment: .leading, spacing: HP.Space.sm) {
      DHDMonthGridView(
        visibleMonth: $visibleMonth,
        selectedDate: $selectedDate,
        scheduledLiftISOs: scheduledLiftISOs,
        practiceISOs: practiceISOs,
        gameISOs: gameISOs,
        isLoading: isLoading,
        onPrev: showPreviousMonth,
        onNext: showNextMonth,
        onSelect: openDay
      )

      Text("Green = scheduled lift day. Blue = BP/practice. Red = game reps.")
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func agendaPane(_ context: HPScreenLayoutContext) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader(context.isAccessibilitySize ? "Month agenda" : "Scheduled days")

        if isLoading {
          HPLoadingState(text: "Loading calendar…")
        } else {
          ForEach(agendaDates(includeEveryDay: context.isAccessibilitySize), id: \.self) { date in
            agendaRow(date)
          }
        }
      }
    }
  }

  private func agendaRow(_ date: Date) -> some View {
    let iso = DateUtils.toISODate(date)
    let events = eventLabels(for: iso)

    return Button {
      openDay(date)
    } label: {
      HStack(alignment: .center, spacing: HP.Space.sm) {
        VStack(alignment: .leading, spacing: 2) {
          Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            .font(HP.Font.callout.weight(.semibold))
            .foregroundStyle(HP.Color.text)
            .fixedSize(horizontal: false, vertical: true)
          Text(events.isEmpty ? "No scheduled activity" : events.joined(separator: " · "))
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: HP.Space.sm)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(HP.Color.textMuted)
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(agendaAccessibilityLabel(date: date, events: events))
  }

  private func agendaDates(includeEveryDay: Bool) -> [Date] {
    let first = DateUtils.startOfMonthET(visibleMonth)
    let dates = (0..<DateUtils.daysInMonthET(first)).compactMap {
      DateUtils.calendarET.date(byAdding: .day, value: $0, to: first)
    }
    guard !includeEveryDay else { return dates }

    let scheduled = dates.filter { !eventLabels(for: DateUtils.toISODate($0)).isEmpty }
    if !scheduled.isEmpty { return scheduled }

    let selectedISO = DateUtils.toISODate(selectedDate)
    return dates.filter { DateUtils.toISODate($0) == selectedISO }.isEmpty
      ? Array(dates.prefix(1))
      : dates.filter { DateUtils.toISODate($0) == selectedISO }
  }

  private func eventLabels(for iso: String) -> [String] {
    var labels: [String] = []
    if scheduledLiftISOs.contains(iso) { labels.append("Scheduled lift") }
    if practiceISOs.contains(iso) { labels.append("BP or practice") }
    if gameISOs.contains(iso) { labels.append("Game reps") }
    labels.append(contentsOf: teamEvents.filter { DateUtils.toISODate($0.startDate) == iso }.map(teamEventLabel))
    return labels
  }

  private func agendaAccessibilityLabel(date: Date, events: [String]) -> String {
    let dateLabel = date.formatted(date: .long, time: .omitted)
    return events.isEmpty ? "\(dateLabel), no scheduled activity" : "\(dateLabel), \(events.joined(separator: ", "))"
  }

  private func teamEventLabel(_ event: SDTeamEvent) -> String {
    let start = event.startDate.formatted(date: .omitted, time: .shortened)
    var details = "\(event.title) at \(start)"
    if let arrival = event.arrivalDate {
      details += ", arrive \(arrival.formatted(date: .omitted, time: .shortened))"
    }
    if let location = event.location_name, !location.isEmpty { details += ", \(location)" }
    if let attire = event.uniformOrDressCode, !attire.isEmpty { details += ", \(attire)" }
    return details
  }

  private func showPreviousMonth() {
    visibleMonth = DateUtils.startOfMonthET(DateUtils.addMonthsET(visibleMonth, value: -1))
    rebuildMonthGrid()
  }

  private func showNextMonth() {
    visibleMonth = DateUtils.startOfMonthET(DateUtils.addMonthsET(visibleMonth, value: 1))
    rebuildMonthGrid()
  }

  private func openDay(_ date: Date) {
    // Preserve the asynchronous push so grid/layout updates cannot race the
    // NavigationStack path mutation.
    let startOfDay = DateUtils.startOfDayET(date)
    selectedDate = startOfDay
    DispatchQueue.main.async {
      navPath.append(startOfDay)
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
      if let organizationId = appState.activeOrgId {
        let start = Calendar.current.date(byAdding: .month, value: -6, to: Date())!
        let end = Calendar.current.date(byAdding: .month, value: 12, to: Date())!
        teamEvents = try await supabase.listTeamEvents(organizationId: organizationId, teamId: nil, playerId: uid, rangeStart: start, rangeEnd: end)
      }
      rebuildMonthGrid()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func rebuildMonthGrid() {
    scheduledLiftISOs = scheduledLiftSet(for: visibleMonth)
    practiceISOs = Set(bpSessions.filter { $0.reps_type == "practice" }.map(\.session_date))
    gameISOs = Set(bpSessions.filter { $0.reps_type == "game" }.map(\.session_date))
      .union(teamEvents.filter { $0.event_type == .game }.map { DateUtils.toISODate($0.startDate) })
    practiceISOs.formUnion(teamEvents.filter { $0.event_type == .practice }.map { DateUtils.toISODate($0.startDate) })
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
