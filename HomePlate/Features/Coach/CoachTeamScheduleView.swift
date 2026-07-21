import SwiftUI

struct CoachTeamScheduleView: View {
  @EnvironmentObject private var appState: AppState
  @State private var mode: SDTeamScheduleMode = .upcoming
  @State private var filter: SDTeamScheduleFilter = .all
  @State private var anchorDate = Date()
  @State private var events: [SDTeamEvent] = []
  @State private var facilities: [SDFacility] = []
  @State private var seasonFilterId: UUID?
  @State private var facilityFilterId: UUID?
  @State private var teamFilterId: UUID?
  @State private var selectionInitialized = false
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var filterRepairNotice: String?
  @State private var loadToken: UUID?
  @State private var editor: EventEditorPresentation?
  @State private var planningEvent: SDTeamEvent?
  @State private var detailEvent: SDTeamEvent?

  var body: some View {
    NavigationStack {
      HPListScreenLayout {
        HPWorkspaceHeader(
          "Schedule",
          orgLabel: selectedSeasonName,
          context: scheduleScopeLabel
        )
      } controls: {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          Picker("View", selection: $mode) {
            ForEach(SDTeamScheduleMode.allCases) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented)
          ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: HP.Space.sm) {
            if appState.canAdminActiveOrg {
              Menu {
                ForEach(scheduleSeasons) { season in
                  Button(season.name) { seasonFilterId = season.id }
                }
              } label: {
                Label(selectedSeasonName, systemImage: "calendar.badge.clock")
              }
              .frame(minHeight: 44)
            }
            if seasonTeams.count > 1 {
              Menu {
                Button(allTeamsLabel) { teamFilterId = nil }
                ForEach(seasonTeams) { team in
                  Button(team.name) { teamFilterId = team.id }
                }
              } label: {
                Label(selectedTeamFilterName, systemImage: "person.3")
              }
              .frame(minHeight: 44)
            } else if let onlyTeam = seasonTeams.first {
              Label(onlyTeam.name, systemImage: "person.3")
                .frame(minHeight: 44)
                .accessibilityLabel("Schedule team filter. \(onlyTeam.name)")
            }
            Menu {
              Picker("Event type", selection: $filter) {
                ForEach(SDTeamScheduleFilter.mvpCases) { Text($0.rawValue).tag($0) }
              }
            } label: {
              Label(filter.rawValue, systemImage: "line.3.horizontal.decrease.circle")
            }
            .frame(minHeight: 44)
            Menu {
              Button("All Facilities") { facilityFilterId = nil }
              ForEach(facilities) { facility in
                Button(facility.name) { facilityFilterId = facility.id }
              }
            } label: {
              Label(selectedFacilityName, systemImage: "building.2")
            }
            .frame(minHeight: 44)
            Spacer()
            Button { moveAnchor(backward: true) } label: {
              Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous date")
            Button("Today") { anchorDate = Date() }
            Button { moveAnchor(backward: false) } label: {
              Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next date")
          }
          }
        }
      } results: { _ in
        scheduleResults
      }
      .navigationTitle("Schedule")
      .toolbar {
        if canCreate, let scheduleSeasonId = selectedSeasonId, !creationTeams.isEmpty {
          ToolbarItem(placement: .primaryAction) {
            Button {
              editor = EventEditorPresentation(
                teams: creationTeams,
                seasonId: scheduleSeasonId,
                preselectedTeamId: editorPreselectedTeamId
              )
            } label: {
              Label("New Event", systemImage: "plus")
            }
          }
        }
      }
      .task(id: reloadKey) { await reload() }
      .task(id: appState.activeOrgId) { await loadFacilities() }
      .refreshable { await reload() }
      .sheet(item: $editor) { presentation in
        TeamEventEditorView(
          teams: presentation.teams,
          seasonId: presentation.seasonId,
          event: presentation.event,
          preselectedTeamId: presentation.preselectedTeamId,
          isDuplicate: presentation.isDuplicate,
          editsFuture: presentation.editsFuture
        ) {
          editor = nil
          Task { await reload() }
        }
      }
      .sheet(item: $planningEvent) { planningEvent in
        NavigationStack {
          CoachEventOperationView(event: planningEvent, teamName: teamName(planningEvent.team_id))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { self.planningEvent = nil } } }
        }
      }
      .sheet(item: $detailEvent) { event in
        NavigationStack {
          TeamEventDetailView(event: event, teamName: teamName(event.team_id))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { detailEvent = nil } } }
        }
      }
    }
  }

  @ViewBuilder private var scheduleResults: some View {
    if selectedSeasonId == nil {
      HPCard {
        HPEmptyState(
          title: "No active season",
          message: "Activate a season before creating or viewing its team schedule.",
          systemImage: "calendar.badge.exclamationmark"
        )
      }
    } else if seasonTeams.isEmpty {
      let issue = appState.teamOperationsIssue ?? .noAuthorizedTeams
      HPCard { HPEmptyState(title: issue.title, message: issue.message, systemImage: "calendar.badge.exclamationmark") }
    } else if isLoading && events.isEmpty {
      HPCard { HPLoadingState(text: "Loading team schedule…") }
    } else if let errorText, events.isEmpty {
      HPCard {
        HPErrorState(
          title: scheduleErrorTitle,
          message: errorText,
          onRetry: { Task { await reload() } }
        )
      }
    } else if filteredEvents.isEmpty {
      if let filterRepairNotice {
        HPCard {
          Label(filterRepairNotice, systemImage: "arrow.triangle.2.circlepath")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
        }
      }
      HPCard {
        VStack(spacing: HP.Space.sm) {
          HPEmptyState(
            title: "No scheduled events",
            message: "No \(filter.rawValue.lowercased()) match this \(mode.rawValue.lowercased()) view.",
            systemImage: "calendar"
          )
          if canCreate, let scheduleSeasonId = selectedSeasonId {
            HPButton(
              title: "Create First Event",
              systemImage: "plus",
              variant: .primary,
              size: .md,
              action: {
                editor = EventEditorPresentation(
                  teams: creationTeams,
                  seasonId: scheduleSeasonId,
                  preselectedTeamId: editorPreselectedTeamId
                )
              }
            )
          }
        }
      }
    } else {
      if let filterRepairNotice {
        HPCard {
          Label(filterRepairNotice, systemImage: "arrow.triangle.2.circlepath")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
        }
      }
      if let errorText {
        HPCard {
          HPErrorState(title: "Schedule may be out of date", message: errorText, onRetry: { Task { await reload() } })
        }
      }
      ForEach(groupedDays, id: \.day) { group in
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader(group.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            ForEach(group.events) { event in
              HStack(alignment: .top, spacing: HP.Space.xs) {
                Button { detailEvent = event } label: {
                  TeamEventRow(event: event, teamName: teamName(event.team_id))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens event details")
                if canMutate(event) || canOpenPlan(event) {
                  Menu {
                    if canOpenPlan(event) {
                      Button { planningEvent = event } label: {
                        Label(event.event_type == .game ? "Open Game Plan" : "Open Practice Plan", systemImage: "list.number")
                      }
                    }
                    if canEdit(event) {
                      Button { editor = EventEditorPresentation(teams: teams(for: event), seasonId: event.season_id, event: event) } label: {
                        Label("Edit or Reschedule", systemImage: "pencil")
                      }
                      if event.series_id != nil {
                        Button { editor = EventEditorPresentation(teams: teams(for: event), seasonId: event.season_id, event: event, editsFuture: true) } label: {
                          Label("Edit This and Future", systemImage: "calendar.badge.clock")
                        }
                      }
                      if event.status != .draft && event.status != .cancelled && event.status != .postponed {
                        Button { Task { await mutate(event, action: "update", status: .postponed) } } label: {
                          Label("Postpone", systemImage: "calendar.badge.clock")
                        }
                      }
                      if event.status == .draft {
                        Button(role: .destructive) { Task { await mutate(event, action: "delete_draft") } } label: {
                          Label("Delete Draft", systemImage: "trash")
                        }
                      }
                    }
                    if canDuplicate(event) {
                      Button { editor = EventEditorPresentation(teams: teams(for: event), seasonId: event.season_id, event: event, isDuplicate: true) } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                      }
                    }
                    if canCancel(event) && event.status != .draft && event.status != .cancelled {
                      Button(role: .destructive) { Task { await mutate(event, action: "cancel") } } label: {
                        Label("Cancel Event", systemImage: "calendar.badge.minus")
                      }
                      if event.series_id != nil {
                        Button(role: .destructive) { Task { await mutate(event, action: "cancel_series") } } label: {
                          Label("Cancel This and Future", systemImage: "xmark.circle")
                        }
                      }
                    }
                  } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                  .accessibilityLabel("Actions for \(event.title)")
                }
              }
              if event.id != group.events.last?.id { Divider() }
            }
          }
        }
      }
    }
  }

  private var canCreate: Bool {
    !creationTeams.isEmpty
  }

  private var creationTeams: [SDTeamOperationsTeam] {
    appState.canAdminActiveOrg
      ? seasonTeams
      : seasonTeams.filter { $0.capabilitySet.contains(.createTeamEvent) }
  }

  private func canMutate(_ event: SDTeamEvent) -> Bool {
    canEdit(event) || canDuplicate(event) || canCancel(event)
  }

  private func canOpenPlan(_ event: SDTeamEvent) -> Bool {
    guard event.event_type == .practice || event.event_type == .game else { return false }
    if appState.canAdminActiveOrg { return true }
    guard let eventTeam = team(for: event.team_id) else { return false }
    return event.event_type == .practice
      ? eventTeam.capabilitySet.contains(.viewPracticePlan)
      : eventTeam.capabilitySet.contains(.viewGamePlan)
  }

  private func canEdit(_ event: SDTeamEvent) -> Bool {
    appState.canAdminActiveOrg || team(for: event.team_id)?.capabilitySet.contains(.editTeamEvent) == true
  }

  private func canDuplicate(_ event: SDTeamEvent) -> Bool {
    appState.canAdminActiveOrg || team(for: event.team_id)?.capabilitySet.contains(.createTeamEvent) == true
  }

  private func canCancel(_ event: SDTeamEvent) -> Bool {
    appState.canAdminActiveOrg || team(for: event.team_id)?.capabilitySet.contains(.cancelTeamEvent) == true
  }

  private func teams(for event: SDTeamEvent) -> [SDTeamOperationsTeam] {
    appState.authorizedScheduleTeams.filter { $0.id == event.team_id }
  }

  private var filteredEvents: [SDTeamEvent] {
    events.filter {
      filter.includes($0.event_type)
        && (facilityFilterId == nil || $0.facility_id == facilityFilterId)
        && (teamFilterId == nil || $0.team_id == teamFilterId)
    }
  }

  private var selectedTeamFilterName: String {
    guard let teamFilterId else { return allTeamsLabel }
    return seasonTeams.first(where: { $0.id == teamFilterId })?.name ?? "Team"
  }

  private var allTeamsLabel: String {
    appState.canAdminActiveOrg ? "All Teams" : "All My Teams"
  }

  private var scheduleScopeLabel: String {
    "Visible filter: \(selectedTeamFilterName)"
  }

  private var effectiveTeamFilterId: UUID? {
    teamFilterId
  }

  private var editorPreselectedTeamId: UUID? {
    teamFilterId ?? (creationTeams.count == 1 ? creationTeams[0].id : nil)
  }

  private var selectedFacilityName: String {
    guard let facilityFilterId else { return "All Facilities" }
    return facilities.first(where: { $0.id == facilityFilterId })?.name ?? "Facility"
  }

  private var selectedSeasonId: UUID? {
    scheduleSelection.seasonId
  }

  private var scheduleSeasons: [SDSeason] {
    (appState.teamOperationsContext?.seasons ?? []).filter {
      $0.status == .active || $0.status == .playoffs
    }
  }

  private var scheduleSelection: SDTeamScheduleSelection {
    guard let organizationId = appState.activeOrgId else {
      return SDTeamScheduleSelection(
        seasonId: nil,
        teamId: nil,
        repairedSeason: seasonFilterId != nil,
        repairedTeam: teamFilterId != nil
      )
    }
    return SDTeamScheduleSelectionResolver.resolve(
      organizationId: organizationId,
      selectedSeasonId: selectionInitialized ? seasonFilterId : seasonFilterId ?? appState.selectedSeason?.id,
      selectedTeamId: teamFilterId,
      seasons: appState.teamOperationsContext?.seasons ?? [],
      teams: appState.authorizedScheduleTeams
    )
  }

  private var selectedSeasonName: String {
    guard let selectedSeasonId else { return "All Seasons" }
    return appState.teamOperationsContext?.seasons.first(where: { $0.id == selectedSeasonId })?.name ?? "Season"
  }

  private var seasonTeams: [SDTeamOperationsTeam] {
    guard let selectedSeasonId else { return appState.authorizedScheduleTeams }
    return appState.authorizedScheduleTeams.filter { $0.season_id == selectedSeasonId }
  }

  private var groupedDays: [(day: Date, events: [SDTeamEvent])] {
    Dictionary(grouping: filteredEvents) { Calendar.current.startOfDay(for: $0.startDate) }
      .map { ($0.key, $0.value.sorted { $0.startDate < $1.startDate }) }
      .sorted { $0.day < $1.day }
  }

  private var reloadKey: String {
    "\(teamFilterId?.uuidString ?? "all"):\(selectedSeasonId?.uuidString ?? "all-seasons"):\(mode.rawValue):\(filter.rawValue):\(DateUtils.toISODate(anchorDate))"
  }

  private func teamName(_ id: UUID) -> String {
    team(for: id)?.name ?? "Team"
  }

  private func team(for id: UUID) -> SDTeamOperationsTeam? {
    appState.authorizedScheduleTeams.first(where: { $0.id == id })
  }

  private func range() -> (Date, Date) {
    let calendar = Calendar.current
    switch mode {
    case .upcoming:
      return (calendar.startOfDay(for: Date()), calendar.date(byAdding: .day, value: 90, to: Date())!)
    case .day:
      let start = calendar.startOfDay(for: anchorDate)
      return (start, calendar.date(byAdding: .day, value: 1, to: start)!)
    case .week:
      let interval = calendar.dateInterval(of: .weekOfYear, for: anchorDate)!
      return (interval.start, interval.end)
    case .month:
      let interval = calendar.dateInterval(of: .month, for: anchorDate)!
      return (interval.start, interval.end)
    }
  }

  private func moveAnchor(backward: Bool) {
    let component: Calendar.Component
    switch mode {
    case .upcoming, .day: component = .day
    case .week: component = .weekOfYear
    case .month: component = .month
    }
    anchorDate = Calendar.current.date(
      byAdding: component,
      value: backward ? -1 : 1,
      to: anchorDate
    ) ?? anchorDate
  }

  private func reload() async {
    guard let service = appState.supabase, let organizationId = appState.activeOrgId else { return }
    let resolution = scheduleSelection
    if resolution.repairedSeason || resolution.repairedTeam {
      selectionInitialized = true
      seasonFilterId = resolution.seasonId
      teamFilterId = resolution.teamId
      filterRepairNotice = "Schedule filters were updated to the current active season and available teams."
      return
    }
    guard resolution.hasActiveSeason else {
      selectionInitialized = true
      events = []
      errorText = nil
      isLoading = false
      seasonFilterId = nil
      teamFilterId = nil
      return
    }
    selectionInitialized = true
    let context = scheduleContextIdentity
    let token = UUID()
    loadToken = token
    isLoading = true
    errorText = nil
    do {
      let limits = range()
      let loadedEvents = try await service.listTeamEvents(
        organizationId: organizationId,
        seasonId: selectedSeasonId,
        teamId: effectiveTeamFilterId,
        rangeStart: limits.0,
        rangeEnd: limits.1
      )
      guard accepts(context: context, token: token) else { return }
      events = loadedEvents
      isLoading = false
    } catch {
      guard accepts(context: context, token: token) else { return }
      errorText = scheduleMessage(for: error)
      SDApplicationErrorClassifier.log(error, functionName: "team-scheduling")
      isLoading = false
    }
  }

  private func scheduleMessage(for error: Error) -> String? {
    guard let presentation = SDApplicationErrorClassifier.presentation(
      for: error,
      taskIsCancelled: Task.isCancelled
    ) else { return nil }
    switch presentation.category {
    case .notDeployed, .serviceUnavailable, .malformedResponse:
      return "Schedule service is not available in this environment. Retry after service access is restored."
    case .forbidden:
      return "You no longer have permission to view this team’s schedule. Choose another team or ask an organization administrator."
    case .validation, .staleData:
      return "The selected team or season is no longer active. Choose an available schedule and try again."
    case .offline:
      return "You’re offline. Previously loaded events remain visible; reconnect to refresh."
    case .unauthorized:
      return "Please sign in again to refresh this schedule."
    default:
      return "The schedule could not be refreshed. Previously loaded events remain visible; try again."
    }
  }

  private var scheduleErrorTitle: String {
    guard let errorText else { return "Schedule could not load" }
    if errorText.contains("permission") { return "Schedule access denied" }
    if errorText.contains("offline") { return "Schedule is offline" }
    if errorText.contains("team or season") { return "Schedule filters changed" }
    if errorText.contains("service") { return "Schedule service unavailable" }
    return "Schedule could not load"
  }

  private var scheduleContextIdentity: String {
    "\(appState.activeOrgId?.uuidString ?? "none"):\(reloadKey)"
  }

  private func accepts(context: String, token: UUID) -> Bool {
    SDAsyncRequestGuard.accepts(
      responseContext: context,
      responseToken: token,
      activeContext: scheduleContextIdentity,
      currentToken: loadToken,
      taskIsCancelled: Task.isCancelled
    )
  }

  private func loadFacilities() async {
    guard let service = appState.supabase, let organizationId = appState.activeOrgId else { facilities = []; return }
    do { facilities = try await service.listFacilities(orgId: organizationId) }
    catch { facilities = [] }
  }

  private func mutate(_ event: SDTeamEvent, action: String, status: SDTeamEventStatus? = nil) async {
    guard let service = appState.supabase else { return }
    let context = scheduleContextIdentity
    do {
      var draft = SDTeamEventDraft(event: event)
      if let status { draft.status = status }
      _ = try await service.saveTeamEvent(
        organizationId: event.organization_id,
        seasonId: event.season_id,
        teamId: event.team_id,
        eventId: event.id,
        draft: draft,
        publish: event.status != .draft,
        coachIds: event.sd_team_event_coaches?.map(\.coach_id) ?? [],
        actionOverride: action,
        reason: action == "cancel" ? "Cancelled by authorized team staff" : nil
      )
      guard context == scheduleContextIdentity, !Task.isCancelled else { return }
      await reload()
    } catch {
      guard context == scheduleContextIdentity, !Task.isCancelled else { return }
      errorText = SDApplicationErrorClassifier.alertMessage(
        for: error,
        taskIsCancelled: Task.isCancelled
      )
    }
  }
}

struct EventEditorPresentation: Identifiable {
  let id = UUID()
  let teams: [SDTeamOperationsTeam]
  let seasonId: UUID
  let preselectedTeamId: UUID?
  var event: SDTeamEvent?
  var isDuplicate: Bool
  var editsFuture: Bool

  init(
    teams: [SDTeamOperationsTeam],
    seasonId: UUID,
    preselectedTeamId: UUID? = nil,
    event: SDTeamEvent? = nil,
    isDuplicate: Bool = false,
    editsFuture: Bool = false
  ) {
    self.teams = teams
    self.seasonId = seasonId
    self.preselectedTeamId = preselectedTeamId ?? event?.team_id
    self.event = event
    self.isDuplicate = isDuplicate
    self.editsFuture = editsFuture
  }
}

struct TeamEventRow: View {
  let event: SDTeamEvent
  let teamName: String

  var body: some View {
    HStack(alignment: .top, spacing: HP.Space.sm) {
      Image(systemName: event.event_type.systemImage)
        .frame(width: 32, height: 32)
        .foregroundStyle(HP.Color.accent)
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text(event.title).font(HP.Font.callout.weight(.semibold)).foregroundStyle(HP.Color.text)
          HPStatusBadge(text: event.status.label, kind: statusKind)
        }
        Label(event.event_type.label, systemImage: event.event_type.systemImage)
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        Text("\(teamName) • \(event.startDate.formatted(date: .omitted, time: .shortened))–\(event.endDate.formatted(date: .omitted, time: .shortened))")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        if let arrival = event.arrivalDate {
          Text("Arrive \(arrival.formatted(date: .omitted, time: .shortened))")
            .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        }
        if let location = event.location_name, !location.isEmpty {
          Label(location, systemImage: "mappin.and.ellipse").font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        }
        if let attire = event.uniformOrDressCode {
          Label(attire, systemImage: "tshirt").font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        }
        if let notes = event.notes?.sdNilIfBlank {
          Text(notes).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted).lineLimit(2)
        }
      }
      Spacer()
    }
    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private var statusKind: HPStatusKind {
    switch event.status {
    case .cancelled: .danger
    case .postponed: .warning
    case .scheduled, .confirmed, .completed: .success
    case .draft: .neutral
    }
  }
}

private struct TeamEventDetailView: View {
  let event: SDTeamEvent
  let teamName: String

  var body: some View {
    HPScreenScaffold { _ in
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPWorkspaceHeader(event.title, orgLabel: teamName, context: event.event_type.label)
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPStatusBadge(text: event.status.label, kind: event.status == .cancelled ? .danger : .neutral)
          Label(event.startDate.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
          Label(event.endDate.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
          Label(event.location_name ?? "Location not set", systemImage: "mappin.and.ellipse")
          if let address = event.address?.sdNilIfBlank { Text(address).foregroundStyle(HP.Color.textMuted) }
          if let description = event.description?.sdNilIfBlank { Text(description) }
        }
      }
      }
    }
    .navigationTitle("Event Details")
  }
}

struct TeamEventEditorView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  let teams: [SDTeamOperationsTeam]
  let seasonId: UUID
  let event: SDTeamEvent?
  let preselectedTeamId: UUID?
  let isDuplicate: Bool
  let editsFuture: Bool
  let onSaved: () -> Void
  @State private var draft: SDTeamEventDraft
  @State private var selectedTeamId: UUID?
  @State private var facilities: [SDFacility] = []
  @State private var conflicts: [SDTeamEventConflict] = []
  @State private var overrideReason = ""
  @State private var isSaving = false
  @State private var errorText: String?

  init(
    teams: [SDTeamOperationsTeam],
    seasonId: UUID,
    event: SDTeamEvent? = nil,
    preselectedTeamId: UUID? = nil,
    isDuplicate: Bool = false,
    editsFuture: Bool = false,
    onSaved: @escaping () -> Void
  ) {
    self.teams = teams
    self.seasonId = seasonId
    self.event = event
    self.preselectedTeamId = preselectedTeamId
    self.isDuplicate = isDuplicate
    self.editsFuture = editsFuture
    self.onSaved = onSaved
    _draft = State(initialValue: event.map(SDTeamEventDraft.init(event:)) ?? SDTeamEventDraft())
    _selectedTeamId = State(
      initialValue: event?.team_id
        ?? preselectedTeamId
        ?? (teams.count == 1 ? teams[0].id : nil)
    )
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Event details") {
          Picker("Type", selection: $draft.type) {
            ForEach(SDTeamEventType.mvpCases) { Label($0.label, systemImage: $0.systemImage).tag($0) }
          }
          Picker("Team", selection: $selectedTeamId) {
            Text("Select a team").tag(UUID?.none)
            ForEach(teams) { team in Text(team.name).tag(Optional(team.id)) }
          }
          .disabled(event != nil && !isDuplicate)
          TextField("Title", text: $draft.title)
          TextField("Description", text: $draft.description, axis: .vertical)
          Toggle("All day", isOn: $draft.allDay)
          DatePicker("Starts", selection: $draft.startAt)
          DatePicker("Ends", selection: $draft.endAt)
          if let timingIssue {
            Label(timingIssue.message, systemImage: "exclamationmark.triangle.fill")
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.danger)
          }
        }
        Section("Location") {
          TextField("Location", text: $draft.locationName)
          TextField("Address", text: $draft.address)
          Picker("Facility resource", selection: $draft.facilityId) {
            Text("None").tag(UUID?.none)
            ForEach(facilities) { facility in Text(facility.name).tag(Optional(facility.id)) }
          }
        }
        Section("Audience") {
          Picker("Visibility", selection: $draft.visibility) {
            Text("Players and parents").tag(SDTeamEventVisibility.team)
            Text("Staff only").tag(SDTeamEventVisibility.staffOnly)
          }
          TextField("Coach-private notes", text: $draft.notes, axis: .vertical)
        }
        Section("Optional") {
          Toggle("Set arrival time", isOn: Binding(
            get: { draft.arrivalAt != nil },
            set: { draft.arrivalAt = $0 ? draft.startAt.addingTimeInterval(-1800) : nil }
          ))
          if draft.arrivalAt != nil {
            DatePicker("Arrival", selection: Binding(
              get: { draft.arrivalAt ?? draft.startAt },
              set: { draft.arrivalAt = $0 }
            ))
          }
          Toggle("Recurring event", isOn: $draft.repeats)
          if draft.repeats {
            Text("Repeats weekly")
            Stepper("Every \(draft.recurrenceInterval) week(s)", value: $draft.recurrenceInterval, in: 1...12)
            Picker("Ends", selection: $draft.recurrenceUsesEndDate) {
              Text("After occurrences").tag(false)
              Text("On date").tag(true)
            }
            if draft.recurrenceUsesEndDate {
              DatePicker("Recurrence end", selection: $draft.recurrenceEndDate, in: draft.startAt..., displayedComponents: .date)
            } else {
              Stepper("\(draft.occurrenceCount) occurrences", value: $draft.occurrenceCount, in: 1...52)
            }
          }
          if let saveDisabledReason, timingIssue == nil {
            Text(saveDisabledReason)
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.textMuted)
          }
        }
        if !conflicts.isEmpty {
          Section("Scheduling warnings") {
            ForEach(conflicts, id: \.stableID) { conflict in
              Label(conflict.title, systemImage: "exclamationmark.triangle")
                .foregroundStyle(HP.Color.warning)
            }
            TextField("Required override reason", text: $overrideReason, axis: .vertical)
          }
        }
      }
      .navigationTitle(isDuplicate ? "Duplicate Event" : event == nil ? (teams.count == 1 ? "New \(draft.type.label)" : "New Organization Event") : "Edit Event")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItemGroup(placement: .confirmationAction) {
          Button("Save Draft") { Task { await save(publish: false) } }.disabled(!canSave || isSaving)
          Button("Publish") { Task { await save(publish: true) } }.disabled(!canSave || isSaving)
        }
      }
      .alert("Event Not Saved", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
        Button("OK", role: .cancel) {}
      } message: { Text(errorText ?? "") }
      .task { await loadFacilities() }
      .onChange(of: draft.endAt) { oldValue, newValue in
        let adjusted = SDTeamEventTiming.endAfterSelecting(newValue, start: draft.startAt, calendar: eventCalendar)
        if adjusted != newValue { draft.endAt = adjusted }
      }
      .onChange(of: draft.allDay) { _, isAllDay in
        guard isAllDay else { return }
        let range = SDTeamEventTiming.allDayRange(containing: draft.startAt, calendar: eventCalendar)
        draft.startAt = range.start
        draft.endAt = range.end
        draft.arrivalAt = nil
      }
    }
  }

  @ViewBuilder private var subtypeSection: some View {
    switch draft.type {
    case .practice:
      Section("Practice details") {
        TextField("Objectives (comma separated)", text: $draft.objectives)
        TextField("Dress code", text: $draft.dressCode)
        TextField("Equipment notes", text: $draft.equipmentNotes, axis: .vertical)
      }
    case .game:
      Section("Game details") {
        TextField("Opponent", text: $draft.opponent)
        Picker("Venue", selection: $draft.venueSide) { Text("Home").tag("home"); Text("Away").tag("away"); Text("Neutral").tag("neutral") }
        TextField("Uniform", text: $draft.uniform)
      }
    case .tournament:
      Section("Tournament details") { TextField("Tournament name", text: $draft.tournamentName); TextField("Host", text: $draft.tournamentHost) }
    case .meeting:
      Section("Meeting details") { TextField("Meeting type", text: $draft.meetingType); TextField("Virtual link", text: $draft.virtualLink) }
    case .travel:
      Section("Travel details") { TextField("Destination", text: $draft.destination); TextField("Transportation notes", text: $draft.transportationNotes); TextField("Lodging notes", text: $draft.lodgingNotes) }
    case .custom:
      EmptyView()
    }
  }

  private var canSave: Bool {
    selectedTeamId != nil
      && !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !draft.locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && timingIssue == nil
      && (!draft.repeats || draft.recurrenceFrequency != "weekly" || !draft.recurrenceWeekdays.isEmpty)
      && (!draft.repeats || !draft.recurrenceUsesEndDate || draft.recurrenceEndDate >= Calendar.current.startOfDay(for: draft.startAt))
  }

  private var timingIssue: SDTeamEventTimingIssue? {
    SDTeamEventTiming.validationIssue(start: draft.startAt, end: draft.endAt, arrival: draft.arrivalAt)
  }

  private var saveDisabledReason: String? {
    if selectedTeamId == nil { return "Select a team to save this event." }
    if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter an event title." }
    if draft.locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter an event location." }
    if draft.repeats && draft.recurrenceWeekdays.isEmpty { return "Select at least one weekday for the recurring event." }
    return nil
  }

  private var eventCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: draft.timezone) ?? .current
    return calendar
  }

  private static let weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"]
  private static let fullWeekdayLabels = Calendar.current.weekdaySymbols

  private func toggleWeekday(_ weekday: Int) {
    if let index = draft.recurrenceWeekdays.firstIndex(of: weekday) {
      draft.recurrenceWeekdays.remove(at: index)
    } else {
      draft.recurrenceWeekdays.append(weekday)
    }
  }

  private func save(publish: Bool) async {
    guard let service = appState.supabase,
          let organizationId = appState.activeOrgId,
          let selectedTeamId,
          let selectedTeam = teams.first(where: { $0.id == selectedTeamId }) else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      conflicts = []
      conflicts = try await service.teamEventConflicts(
        organizationId: organizationId,
        seasonId: selectedTeam.season_id,
        teamId: selectedTeam.id,
        eventId: isDuplicate ? nil : event?.id,
        startAt: draft.startAt,
        endAt: draft.endAt,
        facilityId: draft.facilityId
      )
      if !conflicts.isEmpty && overrideReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        errorText = "Review the schedule warnings and enter an override reason to continue."
        return
      }
      _ = try await service.saveTeamEvent(
        organizationId: organizationId,
        seasonId: selectedTeam.season_id,
        teamId: selectedTeam.id,
        eventId: event?.id,
        draft: draft,
        publish: publish,
        overrideReason: overrideReason.sdNilIfBlank,
        coachIds: event?.sd_team_event_coaches?.map(\.coach_id) ?? [],
        actionOverride: isDuplicate ? "duplicate" : editsFuture ? "update_future" : nil
      )
      onSaved()
    } catch {
      errorText = "The event could not be saved. Check its details and any schedule conflicts, then try again."
    }
  }

  private func loadFacilities() async {
    guard let service = appState.supabase, let organizationId = appState.activeOrgId else { return }
    do { facilities = try await service.listFacilities(orgId: organizationId) }
    catch { facilities = [] }
  }
}
