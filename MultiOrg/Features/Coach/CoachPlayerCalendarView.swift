import SwiftUI
import UniformTypeIdentifiers

/// Coach-facing calendar for a player (month grid + day tap -> view-only day details).
struct CoachPlayerCalendarView: View {
  @EnvironmentObject private var appState: AppState
  let player: Profile

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
    HPCalendarScreenLayout(compactPane: .calendar) { _ in
      HPWorkspaceHeader(
        "Calendar",
        orgLabel: activeOrganizationName,
        context: "\(player.displayName) • \(DateUtils.monthTitle(visibleMonth))"
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
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .task { await reload() }
    #if os(macOS)
    .dhdFloatingModal(item: $daySheet, width: 920, height: 680) { s in
      NavigationStack {
        CoachPlayerDayDetailView(player: player, date: s.date)
          .navigationTitle(DateUtils.toISODate(s.date))
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Close") { daySheet = nil }
                .keyboardShortcut(.cancelAction)
            }
          }
      }
    }
    #else
    .sheet(item: $daySheet) { s in
      NavigationStack {
        CoachPlayerDayDetailView(player: player, date: s.date)
          .navigationTitle(DateUtils.toISODate(s.date))
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Close") { daySheet = nil }
            }
          }
      }
    }
    #endif
  }

  private var activeOrganizationName: String {
    if let organizationId = appState.activeOrgId,
       let organization = appState.availableOrganizations.first(where: { $0.id == organizationId }) {
      return organization.displayName
    }
    return appState.activeOrgSettings?.display_name
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
    let selectedDates = dates.filter { DateUtils.toISODate($0) == selectedISO }
    return selectedDates.isEmpty ? Array(dates.prefix(1)) : selectedDates
  }

  private func eventLabels(for iso: String) -> [String] {
    var labels: [String] = []
    if scheduledLiftISOs.contains(iso) { labels.append("Scheduled lift") }
    if practiceISOs.contains(iso) { labels.append("BP or practice") }
    if gameISOs.contains(iso) { labels.append("Game reps") }
    return labels
  }

  private func agendaAccessibilityLabel(date: Date, events: [String]) -> String {
    let dateLabel = date.formatted(date: .long, time: .omitted)
    return events.isEmpty
      ? "\(dateLabel), no scheduled activity"
      : "\(dateLabel), \(events.joined(separator: ", "))"
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
    let startOfDay = DateUtils.startOfDayET(date)
    selectedDate = startOfDay
    daySheet = DaySheet(date: startOfDay)
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      assignment = try await supabase.fetchActiveAssignment(playerId: player.id)
      if let assignment {
        template = try await supabase.fetchTemplate(id: assignment.template_id)
      } else {
        template = nil
      }
      bpSessions = try await supabase.listBPSessions(playerId: player.id, limit: 365)
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

private struct CoachPlayerDayDetailView: View {
  let player: Profile
  let date: Date

  var body: some View {
    CoachPlayerDailyLogDetailView(player: player, dateISO: DateUtils.toISODate(date))
  }
}

private struct CoachPlayerDailyLogDetailView: View {
  @EnvironmentObject private var appState: AppState
  let player: Profile
  let dateISO: String

  @State private var log: SDDailyLog?
  @State private var strength: [SDStrengthLog] = []
  @State private var sessions: [SDBPSession] = []
  @State private var bpEvents: [SDBPEvent] = []
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var toastText: String?

  @State private var isImporting = false
  @State private var importSource = "rapsodo"
  @State private var importRepsType = "practice"

  var body: some View {
    HPDetailScreenLayout {
      HPWorkspaceHeader(
        "Day details",
        orgLabel: activeOrganizationName,
        context: "\(player.displayName) • \(dateISO)"
      ) {
        if isLoading {
          HPProgressIndicator(style: .spinner)
            .accessibilityLabel("Loading day details")
        }
      }
    } metrics: {
      HPMetricCard(
        title: "Strength logs",
        value: "\(strength.count)",
        context: dateISO
      )
      HPMetricCard(
        title: "BP sessions",
        value: "\(sessions.count)",
        context: dateISO
      )
      HPMetricCard(
        title: "BP events",
        value: "\(bpEvents.count)",
        context: "Loaded events"
      )
    } details: {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        if isLoading {
          HPCard {
            HPLoadingState(text: "Loading…")
          }
        }

        selfAssessmentCard

        if let comments = log?.comments, !comments.isEmpty || log?.feel != nil {
          liftNoteCard(comments: comments)
        }

        strengthLogsCard
      }
    } related: { context in
      bpSessionsCard(context)
    } primaryAction: {
      EmptyView()
    }
    .navigationTitle(dateISO)
    .dhdToast($toastText)
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .fileImporter(
      isPresented: $isImporting,
      allowedContentTypes: [UTType.commaSeparatedText, UTType.text, UTType.data],
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .failure(let err):
        isImporting = false
        errorText = err.localizedDescription
      case .success(let urls):
        isImporting = false
        guard let url = urls.first else { return }
        Task { await importCSV(url: url) }
      }
    }
    .task { await reload() }
  }

  private var activeOrganizationName: String {
    if let organizationId = appState.activeOrgId,
       let organization = appState.availableOrganizations.first(where: { $0.id == organizationId }) {
      return organization.displayName
    }
    return appState.activeOrgSettings?.display_name
      ?? appState.activeOrgSettings?.short_name
      ?? "Home Plate"
  }

  private var selfAssessmentCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Self assessment")
        row("Got video", log?.got_video)
        row("Ate breakfast", log?.ate_breakfast)
        row("Hit daily goals", log?.hit_daily_goals)
        row("Stuck to process", log?.stuck_to_process)
        if let fellShort = log?.fell_short, !fellShort.isEmpty {
          Text("Fell short: \(fellShort)")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.text)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let excelled = log?.excelled, !excelled.isEmpty {
          Text("Excelled: \(excelled)")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.text)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private func liftNoteCard(comments: String) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Lift note")
        if let feel = log?.feel {
          Text("Feel: \(feel)")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.text)
        }
        if !comments.isEmpty {
          Text(comments)
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.text)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private var strengthLogsCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Strength logs")
        if strength.isEmpty {
          Text("No strength logs for this day.")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
        } else {
          ForEach(strength) { strengthLog in
            VStack(alignment: .leading, spacing: 4) {
              Text(strengthLog.exercise_name)
                .font(HP.Font.headline)
                .foregroundStyle(HP.Color.text)
              if strengthLog.no_weight {
                Text("No weight • Sets completed: \(strengthLog.sets_completed ?? 0)")
                  .font(HP.Font.caption)
                  .foregroundStyle(HP.Color.textMuted)
              } else if let weights = strengthLog.set_weights_json, !weights.isEmpty {
                Text("Weights: " + weights.joined(separator: ", "))
                  .font(HP.Font.caption)
                  .foregroundStyle(HP.Color.textMuted)
                  .fixedSize(horizontal: false, vertical: true)
              } else {
                Text("No weights logged")
                  .font(HP.Font.caption)
                  .foregroundStyle(HP.Color.textMuted)
              }
              if let notes = strengthLog.notes, !notes.isEmpty {
                Text(notes)
                  .font(HP.Font.caption)
                  .foregroundStyle(HP.Color.textMuted)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
            .padding(.vertical, 4)
          }
        }
      }
    }
  }

  private func bpSessionsCard(_ context: HPScreenLayoutContext) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("BP sessions") {
          HPStatusBadge(text: "\(sessions.count)", kind: .neutral)
        }

        // Coach import UI (server-side), replaces events for the selected day/type.
        importControls(context)

        Divider().overlay(HP.Color.border)

        if sessions.isEmpty {
          Text("No BP session for this day.")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
        } else {
          ForEach(sessions) { session in
            VStack(alignment: .leading, spacing: 4) {
              Text("\(session.source.uppercased()) • \(session.reps_type)")
                .font(HP.Font.headline)
                .foregroundStyle(HP.Color.text)
              Text("Events: \(bpEvents.count)")
                .font(HP.Font.caption)
                .foregroundStyle(HP.Color.textMuted)
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func importControls(_ context: HPScreenLayoutContext) -> some View {
    VStack(alignment: .leading, spacing: HP.Space.sm) {
      if context.isAccessibilitySize || !context.isRegularWidth {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          importTypePicker
          importSourcePicker
          uploadButton(fullWidth: true)
        }
      } else {
        HStack(spacing: HP.Space.sm) {
          importTypePicker
          importSourcePicker
          Spacer(minLength: HP.Space.sm)
          uploadButton(fullWidth: false)
        }
      }

      Text("Upload Rapsodo, HitTrax, or TrackMan CSVs. The source is detected automatically when possible; importing replaces the selected day's events.")
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var importTypePicker: some View {
    Picker("Type", selection: $importRepsType) {
      Text("Practice").tag("practice")
      Text("Game").tag("game")
    }
    .pickerStyle(.menu)
    .tint(HP.Color.accent)
  }

  private var importSourcePicker: some View {
    Picker("Source", selection: $importSource) {
      ForEach(BPImportSource.allCases) { source in
        Text(source.label).tag(source.rawValue)
      }
    }
    .pickerStyle(.menu)
    .tint(HP.Color.accent)
  }

  private func uploadButton(fullWidth: Bool) -> some View {
    HPButton(
      title: "Upload CSV…",
      systemImage: "square.and.arrow.up",
      variant: .primary,
      size: .md,
      fullWidth: fullWidth,
      action: { isImporting = true }
    )
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      log = try await supabase.fetchDailyLog(playerId: player.id, dateISO: dateISO)
      strength = try await supabase.fetchStrengthLogs(playerId: player.id, dateISO: dateISO)
      let all = try await supabase.listBPSessions(playerId: player.id, limit: 365)
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

  private func importCSV(url: URL) async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let text = try CSVFileReader.readText(from: url)
      let result = try BPImportMapper.map(text: text, selectedSource: BPImportSource.parse(importSource))
      importSource = result.source.rawValue
      let creates: [SDBPEventCreate] = result.rows.enumerated().map { idx, row in
        SDBPEventCreate(
          session_id: UUID(), // The coach import endpoint assigns the real session ID.
          pitch_num: row.pitch_num ?? (idx + 1),
          exit_velo: row.exit_velo,
          distance: row.distance,
          launch_angle: row.launch_angle,
          strike_x: row.strike_x,
          strike_z: row.strike_z,
          raw: row.raw
        )
      }

      _ = try await supabase.coachReplaceBPEvents(
        playerId: player.id,
        dateISO: dateISO,
        source: result.source.rawValue,
        repsType: importRepsType,
        events: creates
      )
      toastText = "Imported \(creates.count) \(result.source.label) events."
      await reload()
    } catch {
      errorText = error.localizedDescription
    }
  }

  @ViewBuilder private func row(_ label: String, _ value: Bool?) -> some View {
    HStack {
      Text(label)
      Spacer()
      if value == true {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(HP.Color.success)
      } else if value == false {
        Image(systemName: "xmark.circle.fill").foregroundStyle(HP.Color.danger)
      } else {
        Text("—").foregroundStyle(HP.Color.textMuted)
      }
    }
  }
}
