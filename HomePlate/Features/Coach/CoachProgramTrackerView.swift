import SwiftUI

struct CoachProgramTrackerView: View {
  @EnvironmentObject private var appState: AppState

  @State private var selectedTeamId: UUID?
  @State private var selectedPlayerId: UUID?
  @State private var assignments: [SDProgramAssignment] = []
  @State private var templates: [UUID: SDProgramTemplate] = [:]
  @State private var programDays: [UUID: [SDProgramDay]] = [:]
  @State private var strengthLogs: [SDStrengthLog] = []
  @State private var selectedDay: CoachProgramTrackerDay?
  @State private var isLoading = false
  @State private var errorText: String?

  var body: some View {
    HPListScreenLayout {
      HPWorkspaceHeader(
        "Player Program Tracker",
        orgLabel: activeOrganizationName,
        context: selectedPlayer?.displayName ?? "Select a player"
      )
    } controls: {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          Text("TEAM")
            .font(HP.Font.eyebrow)
            .tracking(HP.Font.eyebrowTracking)
            .foregroundStyle(HP.Color.textMuted)
          Picker("Team", selection: $selectedTeamId) {
            Text("All players").tag(UUID?.none)
            ForEach(availableTeams) { team in
              Text(team.name).tag(Optional(team.id))
            }
          }
          .pickerStyle(.menu)
          .tint(HP.Color.accent)
        }
      }
    } results: { _ in
      playerList
    }
    .navigationTitle("Player Program Tracker")
    .task(id: appState.activeOrgId) {
      await prepareOrganizationContext()
    }
    .onChange(of: appState.teamContextToken) { _, _ in
      synchronizeGlobalTeamScope()
      repairPlayerSelection(clearSelection: true)
    }
    .onChange(of: selectedTeamId) { _, newValue in
      if newValue != appState.selectedTeamId {
        if let newValue {
          appState.selectTeam(newValue)
        } else {
          appState.selectAllTeams()
        }
      }
      repairPlayerSelection()
    }
    .onChange(of: selectedPlayerId) { _, _ in
      Task { await reloadPlayerData() }
    }
    .sheet(isPresented: Binding(
      get: { selectedPlayerId != nil },
      set: { if !$0 { selectedPlayerId = nil } }
    )) {
      NavigationStack {
        ScrollView {
          assignmentList
            .padding(HP.Space.md)
        }
        .background(HP.Color.bg)
        .navigationTitle(selectedPlayer?.displayName ?? "Program Tracker")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Close") { selectedPlayerId = nil }
          }
        }
        .sheet(item: $selectedDay) { day in
          CoachProgramDayDetailView(day: day)
            .environmentObject(appState)
        }
      }
    }
    .alert("Program Tracker", isPresented: Binding(
      get: { errorText != nil },
      set: { if !$0 { errorText = nil } }
    )) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorText ?? "")
    }
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

  private var availableTeams: [SDTeamOperationsTeam] {
    appState.teamOperationsContext?.teams
      .filter(\.is_active)
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
      ?? []
  }

  private var visiblePlayers: [Profile] {
    guard let context = appState.teamOperationsContext else { return [] }
    let players: [Profile]
    if let selectedTeamId {
      players = context.players(for: selectedTeamId)
    } else {
      players = context.people.filter(\.isPlayer)
    }
    return players.sorted {
      $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
    }
  }

  private var selectedPlayer: Profile? {
    guard let selectedPlayerId else { return nil }
    return appState.teamOperationsContext?.people.first(where: { $0.id == selectedPlayerId })
  }

  private var playerList: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Players") {
          HPStatusBadge(text: "\(visiblePlayers.count)", kind: .neutral)
        }

        if visiblePlayers.isEmpty {
          HPEmptyState(
            title: "No players",
            message: "No active players are assigned to this team.",
            systemImage: "person.2"
          )
        } else {
          ForEach(visiblePlayers) { player in
            Button {
              selectedPlayerId = player.id
            } label: {
              HStack(spacing: HP.Space.sm) {
                VStack(alignment: .leading, spacing: 3) {
                  Text(player.displayName)
                    .font(HP.Font.headline)
                    .foregroundStyle(HP.Color.text)
                  Text(playerAssignmentSummary(player.id))
                    .font(HP.Font.caption)
                    .foregroundStyle(HP.Color.textMuted)
                }
                Spacer(minLength: HP.Space.sm)
                Image(systemName: selectedPlayerId == player.id ? "checkmark.circle.fill" : "chevron.right")
                  .foregroundStyle(selectedPlayerId == player.id ? HP.Color.accent : HP.Color.textMuted)
                  .accessibilityHidden(true)
              }
              .frame(minHeight: 48)
              .padding(.horizontal, selectedPlayerId == player.id ? HP.Space.xs : 0)
              .background(selectedPlayerId == player.id ? HP.Color.accent.opacity(0.12) : .clear)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var assignmentList: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("Assignments") {
          if selectedPlayer != nil {
            HPStatusBadge(text: "\(assignments.count)", kind: .neutral)
          }
        }

        if isLoading {
          HPLoadingState(text: "Loading program history…")
        } else if selectedPlayer == nil {
          HPEmptyState(
            title: "Select a player",
            message: "Choose a player to inspect assigned programs and submitted work.",
            systemImage: "list.clipboard"
          )
        } else if assignments.isEmpty {
          HPEmptyState(
            title: "No program assignments",
            message: "This player has no active or ended program assignments.",
            systemImage: "rectangle.stack"
          )
        } else {
          ForEach(assignments) { assignment in
            assignmentCard(assignment)
          }
        }
      }
    }
  }

  private func assignmentCard(_ assignment: SDProgramAssignment) -> some View {
    let template = templates[assignment.template_id]
    let scheduledDays = schedule(for: assignment, template: template)
    return VStack(alignment: .leading, spacing: HP.Space.sm) {
      HStack(alignment: .top, spacing: HP.Space.sm) {
        VStack(alignment: .leading, spacing: 3) {
          Text(template?.name ?? "Program")
            .font(HP.Font.headline)
            .foregroundStyle(HP.Color.text)
          Text(assignmentDateRange(assignment, template: template))
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
        }
        Spacer(minLength: HP.Space.sm)
        HPStatusBadge(
          text: assignment.ended_at == nil ? "Active" : "Ended",
          kind: assignment.ended_at == nil ? .success : .neutral
        )
      }

      if scheduledDays.isEmpty {
        Text("No scheduled program days are available for this assignment.")
          .font(HP.Font.callout)
          .foregroundStyle(HP.Color.textMuted)
      } else {
        ForEach(scheduledDays) { day in
          Button {
            selectedDay = day
          } label: {
            HStack(spacing: HP.Space.sm) {
              VStack(alignment: .leading, spacing: 3) {
                Text(day.displayDate)
                  .font(HP.Font.callout.weight(.semibold))
                  .foregroundStyle(HP.Color.text)
                Text("Week \(day.week) • Day \(day.dayIndex)")
                  .font(HP.Font.caption)
                  .foregroundStyle(HP.Color.textMuted)
              }
              Spacer(minLength: HP.Space.sm)
              HPStatusBadge(text: day.state.title, kind: day.state.badgeKind)
              Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(HP.Color.textMuted)
                .accessibilityHidden(true)
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }

      if let notes = assignment.notes, !notes.isEmpty {
        Text(notes)
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.vertical, HP.Space.xs)
  }

  private func prepareOrganizationContext() async {
    selectedTeamId = appState.selectedTeamId
    selectedPlayerId = nil
    assignments = []
    templates = [:]
    programDays = [:]
    strengthLogs = []
    selectedDay = nil
    if appState.teamOperationsContext == nil {
      await appState.refreshTeamOperationsContext()
    }
    repairPlayerSelection(clearSelection: true)
  }

  private func synchronizeGlobalTeamScope() {
    selectedTeamId = appState.selectedTeamId
  }

  private func repairPlayerSelection(clearSelection: Bool = false) {
    if clearSelection {
      selectedPlayerId = nil
      return
    }
    let ids = Set(visiblePlayers.map(\.id))
    if let selectedPlayerId, ids.contains(selectedPlayerId) { return }
    selectedPlayerId = nil
  }

  private func reloadPlayerData() async {
    guard let playerId = selectedPlayerId,
          let organizationId = appState.activeOrgId,
          let supabase = appState.supabase else {
      assignments = []
      templates = [:]
      programDays = [:]
      strengthLogs = []
      return
    }

    isLoading = true
    defer { isLoading = false }
    do {
      let loadedAssignments = try await supabase.fetchProgramAssignments(
        playerId: playerId,
        orgId: organizationId
      )
      let templateRows = try await supabase.fetchProgramTemplates(
        ids: loadedAssignments.map(\.template_id)
      )
      let loadedTemplates = Dictionary(uniqueKeysWithValues: templateRows.map { ($0.id, $0) })
      var loadedDays: [UUID: [SDProgramDay]] = [:]
      var missingDayDetails = 0
      for templateId in loadedTemplates.keys {
        do {
          loadedDays[templateId] = try await supabase.fetchProgramDays(templateId: templateId)
        } catch {
          missingDayDetails += 1
        }
      }
      let loadedLogs = try await supabase.listStrengthLogs(playerId: playerId)

      guard selectedPlayerId == playerId else { return }
      assignments = loadedAssignments
      templates = loadedTemplates
      programDays = loadedDays
      strengthLogs = loadedLogs
      let missingTemplates = Set(loadedAssignments.map(\.template_id)).subtracting(loadedTemplates.keys).count
      if missingTemplates > 0 || missingDayDetails > 0 {
        errorText = "Some older program details are unavailable, but every valid assignment and submission remains visible."
      }
    } catch {
      let message = SDApplicationErrorClassifier.alertMessage(for: error) ?? "Please try again."
      errorText = "The latest program activity could not be loaded. Existing results remain visible. \(message)"
    }
  }

  private func playerAssignmentSummary(_ playerId: UUID) -> String {
    guard playerId == selectedPlayerId else { return "View program activity" }
    let active = assignments.filter { $0.ended_at == nil }.count
    return active == 0 ? "No active program" : "\(active) active program\(active == 1 ? "" : "s")"
  }

  private func schedule(
    for assignment: SDProgramAssignment,
    template: SDProgramTemplate?
  ) -> [CoachProgramTrackerDay] {
    guard let template,
          let startDate = DateUtils.fromISODate(assignment.start_date) else { return [] }

    let weekdays = Array(Set(template.lift_weekdays.filter { (1...7).contains($0) })).sorted()
    guard !weekdays.isEmpty else { return [] }
    let targetCount = max(1, template.weeks) * weekdays.count
    let endDate = assignment.ended_at.map(DateUtils.startOfDayET)
    let daysBySlot = Dictionary(uniqueKeysWithValues: (programDays[template.id] ?? []).map {
      ("\($0.week)-\($0.day_index)", $0)
    })
    var result: [CoachProgramTrackerDay] = []
    var cursor = DateUtils.startOfDayET(startDate)
    var index = 0
    var safety = 0

    while index < targetCount, safety < 500 {
      defer {
        cursor = DateUtils.calendarET.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        safety += 1
      }
      guard weekdays.contains(DateUtils.weekdayIndexMonToSun(cursor)) else { continue }
      if let endDate, cursor > endDate { break }

      let week = (index / weekdays.count) + 1
      let dayIndex = (index % weekdays.count) + 1
      let dateISO = DateUtils.toISODate(cursor)
      let matchingLogs = strengthLogs.filter { log in
        guard log.log_date == dateISO else { return false }
        if log.assignment_id == assignment.id { return true }
        return log.assignment_id == nil
          && log.template_id == assignment.template_id
          && log.week == week
          && log.day_index == dayIndex
      }
      let state: CoachProgramTrackerDay.State
      if !matchingLogs.isEmpty {
        state = .submitted
      } else if cursor > DateUtils.startOfDayET(Date()) {
        state = .upcoming
      } else {
        state = .noSubmission
      }
      result.append(CoachProgramTrackerDay(
        assignmentId: assignment.id,
        templateName: template.name,
        playerName: selectedPlayer?.displayName ?? "Player",
        dateISO: dateISO,
        week: week,
        dayIndex: dayIndex,
        state: state,
        plannedExercises: daysBySlot["\(week)-\(dayIndex)"]?.exercises ?? [],
        logs: matchingLogs
      ))
      index += 1
    }
    return result
  }

  private func assignmentDateRange(
    _ assignment: SDProgramAssignment,
    template: SDProgramTemplate?
  ) -> String {
    let endISO: String
    if let endedAt = assignment.ended_at {
      endISO = DateUtils.toISODate(endedAt)
    } else if let start = DateUtils.fromISODate(assignment.start_date) {
      let days = max(1, template?.weeks ?? 1) * 7 - 1
      endISO = DateUtils.toISODate(DateUtils.calendarET.date(byAdding: .day, value: days, to: start) ?? start)
    } else {
      endISO = "—"
    }
    return "\(assignment.start_date) – \(endISO)"
  }
}

private struct CoachProgramTrackerDay: Identifiable {
  enum State: Equatable {
    case submitted
    case upcoming
    case noSubmission

    var title: String {
      switch self {
      case .submitted: "Submitted"
      case .upcoming: "Upcoming"
      case .noSubmission: "No Submission"
      }
    }

    var badgeKind: HPStatusKind {
      switch self {
      case .submitted: .success
      case .upcoming: .info
      case .noSubmission: .warning
      }
    }
  }

  let assignmentId: UUID
  let templateName: String
  let playerName: String
  let dateISO: String
  let week: Int
  let dayIndex: Int
  let state: State
  let plannedExercises: [SDExercise]
  let logs: [SDStrengthLog]

  var id: String { "\(assignmentId.uuidString)-\(dateISO)-\(week)-\(dayIndex)" }

  var displayDate: String {
    guard let date = DateUtils.fromISODate(dateISO) else { return dateISO }
    return DateUtils.prettyDateTitle(date)
  }
}

private struct CoachProgramDayDetailView: View {
  @Environment(\.dismiss) private var dismiss
  let day: CoachProgramTrackerDay

  var body: some View {
    NavigationStack {
      HPDetailScreenLayout {
        HPWorkspaceHeader(
          day.templateName,
          context: "\(day.playerName) • \(day.displayDate)"
        )
      } metrics: {
        HPCard {
          HStack(spacing: HP.Space.sm) {
            HPStatusBadge(text: day.state.title, kind: day.state.badgeKind)
            Text("Week \(day.week) • Day \(day.dayIndex)")
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.textMuted)
          }
        }
      } details: {
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.md) {
            HPSectionHeader("Submitted exercises") {
              HPStatusBadge(text: "\(day.logs.count)", kind: .neutral)
            }
            if day.logs.isEmpty {
              HPEmptyState(
                title: day.state == .upcoming ? "Upcoming program day" : "No submission",
                message: day.state == .upcoming
                  ? "The player can submit this work when the program day arrives."
                  : "The player did not submit exercise results for this date.",
                systemImage: "list.clipboard"
              )
            } else {
              ForEach(day.logs) { log in
                submittedExercise(log)
              }
            }
          }
        }
      } related: { _ in
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Planned exercises") {
              HPStatusBadge(text: "\(day.plannedExercises.count)", kind: .neutral)
            }
            if day.plannedExercises.isEmpty {
              Text("No exercises were saved for this program day.")
                .font(HP.Font.callout)
                .foregroundStyle(HP.Color.textMuted)
            } else {
              ForEach(day.plannedExercises) { exercise in
                VStack(alignment: .leading, spacing: 3) {
                  Text(exercise.name)
                    .font(HP.Font.headline)
                    .foregroundStyle(HP.Color.text)
                  Text(plannedExerciseSummary(exercise))
                    .font(HP.Font.caption)
                    .foregroundStyle(HP.Color.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
          }
        }
      } primaryAction: {
        EmptyView()
      }
      .navigationTitle(day.displayDate)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  private func submittedExercise(_ log: SDStrengthLog) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(log.exercise_name)
        .font(HP.Font.headline)
        .foregroundStyle(HP.Color.text)

      if let setsCompleted = log.sets_completed {
        detailRow("Sets completed", value: String(setsCompleted))
      }
      if log.no_weight {
        detailRow("Weight", value: "No weight")
      } else if let weights = log.set_weights_json, !weights.isEmpty {
        detailRow("Set weights", value: weights.joined(separator: ", "))
      }
      if let results = log.result_values {
        ForEach(results.keys.sorted(), id: \.self) { key in
          if let value = results[key]?.stringValue {
            detailRow(displayLabel(key), value: value)
          }
        }
      }
      if let notes = log.notes, !notes.isEmpty {
        detailRow("Notes", value: notes)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, HP.Space.xs)
  }

  private func detailRow(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label.uppercased())
        .font(HP.Font.eyebrow)
        .tracking(HP.Font.eyebrowTracking)
        .foregroundStyle(HP.Color.textMuted)
      Text(value)
        .font(HP.Font.callout)
        .foregroundStyle(HP.Color.text)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func plannedExerciseSummary(_ exercise: SDExercise) -> String {
    var parts: [String] = []
    if let sets = exercise.sets { parts.append("\(sets) sets") }
    if let reps = exercise.reps, !reps.isEmpty { parts.append(reps) }
    if let unit = exercise.unit, !unit.isEmpty { parts.append(unit) }
    if let notes = exercise.notes, !notes.isEmpty { parts.append(notes) }
    return parts.isEmpty ? "No prescription details" : parts.joined(separator: " • ")
  }

  private func displayLabel(_ raw: String) -> String {
    raw.replacingOccurrences(of: "_", with: " ").capitalized
  }
}
