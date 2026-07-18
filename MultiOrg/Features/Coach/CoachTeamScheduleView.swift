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
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var loadToken: UUID?
  @State private var editor: EventEditorPresentation?
  @State private var planningEvent: SDTeamEvent?

  var body: some View {
    NavigationStack {
      HPListScreenLayout {
        HPWorkspaceHeader(
          "Schedule",
          orgLabel: appState.selectedSeason?.name ?? "Season",
          context: appState.isAllTeamsSelected ? "All authorized teams" : appState.selectedTeam?.name ?? "Team assignment required"
        ) { CoachTeamSelector() }
      } controls: {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          Picker("View", selection: $mode) {
            ForEach(SDTeamScheduleMode.allCases) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented)
          HStack {
            if appState.canAdminActiveOrg {
              Menu {
                ForEach(appState.teamOperationsContext?.seasons ?? []) { season in
                  Button(season.name) { seasonFilterId = season.id }
                }
              } label: {
                Label(selectedSeasonName, systemImage: "calendar.badge.clock")
              }
              .frame(minHeight: 44)
            }
            Menu {
              Picker("Event type", selection: $filter) {
                ForEach(SDTeamScheduleFilter.allCases) { Text($0.rawValue).tag($0) }
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
            Button { anchorDate = Calendar.current.date(byAdding: .day, value: -1, to: anchorDate) ?? anchorDate } label: {
              Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous date")
            Button("Today") { anchorDate = Date() }
            Button { anchorDate = Calendar.current.date(byAdding: .day, value: 1, to: anchorDate) ?? anchorDate } label: {
              Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next date")
          }
        }
      } results: { _ in
        scheduleResults
      }
      .navigationTitle("Schedule")
      .toolbar {
        if canCreate, let team = appState.selectedTeam {
          ToolbarItem(placement: .primaryAction) {
            Button { editor = EventEditorPresentation(teams: [team], seasonId: team.season_id) } label: {
              Label("New Event", systemImage: "plus")
            }
          }
        } else if appState.canAdminActiveOrg, appState.isAllTeamsSelected,
                  let scheduleSeasonId = selectedSeasonId, !seasonTeams.isEmpty {
          ToolbarItem(placement: .primaryAction) {
            Menu {
              Button("All Teams") { editor = EventEditorPresentation(teams: seasonTeams, seasonId: scheduleSeasonId) }
              Divider()
              ForEach(seasonTeams) { team in
                Button(team.name) { editor = EventEditorPresentation(teams: [team], seasonId: team.season_id) }
              }
            } label: { Label("New Event", systemImage: "plus") }
          }
        }
      }
      .task(id: reloadKey) { await reload() }
      .task(id: appState.activeOrgId) { await loadFacilities() }
      .refreshable { await reload() }
      .alert("Schedule Error", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
        Button("OK", role: .cancel) {}
      } message: { Text(errorText ?? "") }
      .sheet(item: $editor) { presentation in
        TeamEventEditorView(teams: presentation.teams, seasonId: presentation.seasonId) {
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
    }
  }

  @ViewBuilder private var scheduleResults: some View {
    if appState.selectedTeam == nil && !appState.isAllTeamsSelected {
      HPCard { HPEmptyState(title: "Team assignment required", message: "An active team is needed to view its schedule.", systemImage: "calendar.badge.exclamationmark") }
    } else if isLoading && events.isEmpty {
      HPCard { HPLoadingState(text: "Loading team schedule…") }
    } else if let errorText, events.isEmpty {
      HPCard {
        HPErrorState(
          title: "Schedule unavailable",
          message: errorText,
          onRetry: { Task { await reload() } }
        )
      }
    } else if filteredEvents.isEmpty {
      HPCard { HPEmptyState(title: "No scheduled events", message: "No (filter.rawValue.lowercased()) match this (mode.rawValue.lowercased()) view.", systemImage: "calendar") }
    } else {
      ForEach(groupedDays, id: \.day) { group in
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader(group.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            ForEach(group.events) { event in
              HStack(alignment: .top, spacing: HP.Space.xs) {
                TeamEventRow(event: event, teamName: teamName(event.team_id))
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
    appState.selectedTeamCapabilities.contains(.createTeamEvent)
  }

  private func canMutate(_ event: SDTeamEvent) -> Bool {
    canEdit(event) || canDuplicate(event) || canCancel(event)
  }

  private func canOpenPlan(_ event: SDTeamEvent) -> Bool {
    guard event.event_type == .practice || event.event_type == .game else { return false }
    if appState.canAdminActiveOrg { return true }
    guard event.team_id == appState.selectedTeam?.id else { return false }
    return event.event_type == .practice
      ? appState.selectedTeamCapabilities.contains(.viewPracticePlan)
      : appState.selectedTeamCapabilities.contains(.viewGamePlan)
  }

  private func canEdit(_ event: SDTeamEvent) -> Bool {
    appState.canAdminActiveOrg || (event.team_id == appState.selectedTeam?.id && appState.selectedTeamCapabilities.contains(.editTeamEvent))
  }

  private func canDuplicate(_ event: SDTeamEvent) -> Bool {
    appState.canAdminActiveOrg || (event.team_id == appState.selectedTeam?.id && appState.selectedTeamCapabilities.contains(.createTeamEvent))
  }

  private func canCancel(_ event: SDTeamEvent) -> Bool {
    appState.canAdminActiveOrg || (event.team_id == appState.selectedTeam?.id && appState.selectedTeamCapabilities.contains(.cancelTeamEvent))
  }

  private func teams(for event: SDTeamEvent) -> [SDTeamOperationsTeam] {
    appState.authorizedCoachTeams.filter { $0.id == event.team_id }
  }

  private var filteredEvents: [SDTeamEvent] {
    events.filter {
      filter.includes($0.event_type) && (facilityFilterId == nil || $0.facility_id == facilityFilterId)
    }
  }

  private var selectedFacilityName: String {
    guard let facilityFilterId else { return "All Facilities" }
    return facilities.first(where: { $0.id == facilityFilterId })?.name ?? "Facility"
  }

  private var selectedSeasonId: UUID? {
    appState.selectedTeam?.season_id ?? seasonFilterId ?? appState.selectedSeason?.id
  }

  private var selectedSeasonName: String {
    guard let selectedSeasonId else { return "All Seasons" }
    return appState.teamOperationsContext?.seasons.first(where: { $0.id == selectedSeasonId })?.name ?? "Season"
  }

  private var seasonTeams: [SDTeamOperationsTeam] {
    guard let selectedSeasonId else { return appState.authorizedCoachTeams }
    return appState.authorizedCoachTeams.filter { $0.season_id == selectedSeasonId }
  }

  private var groupedDays: [(day: Date, events: [SDTeamEvent])] {
    Dictionary(grouping: filteredEvents) { Calendar.current.startOfDay(for: $0.startDate) }
      .map { ($0.key, $0.value.sorted { $0.startDate < $1.startDate }) }
      .sorted { $0.day < $1.day }
  }

  private var reloadKey: String {
    "\(appState.selectedTeamId?.uuidString ?? "all"):\(selectedSeasonId?.uuidString ?? "all-seasons"):\(mode.rawValue):\(filter.rawValue):\(DateUtils.toISODate(anchorDate))"
  }

  private func teamName(_ id: UUID) -> String {
    appState.authorizedCoachTeams.first(where: { $0.id == id })?.name ?? "Team"
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

  private func reload() async {
    guard let service = appState.supabase, let organizationId = appState.activeOrgId else { return }
    if appState.selectedTeam == nil && !appState.isAllTeamsSelected { events = []; return }
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
        teamId: appState.selectedTeam?.id,
        rangeStart: limits.0,
        rangeEnd: limits.1
      )
      guard accepts(context: context, token: token) else { return }
      events = loadedEvents
      isLoading = false
    } catch {
      guard accepts(context: context, token: token) else { return }
      errorText = SDApplicationErrorClassifier.alertMessage(
        for: error,
        taskIsCancelled: Task.isCancelled
      )
      isLoading = false
    }
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

private struct EventEditorPresentation: Identifiable {
  let id = UUID()
  let teams: [SDTeamOperationsTeam]
  let seasonId: UUID
  var event: SDTeamEvent?
  var isDuplicate = false
  var editsFuture = false
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
          if event.status == .draft { HPStatusBadge(text: "Draft", kind: .neutral) }
          if event.status == .cancelled { HPStatusBadge(text: "Cancelled", kind: .danger) }
          if event.status == .postponed { HPStatusBadge(text: "Postponed", kind: .warning) }
        }
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
}

struct TeamEventEditorView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  let teams: [SDTeamOperationsTeam]
  let seasonId: UUID
  let event: SDTeamEvent?
  let isDuplicate: Bool
  let editsFuture: Bool
  let onSaved: () -> Void
  @State private var draft: SDTeamEventDraft
  @State private var facilities: [SDFacility] = []
  @State private var conflicts: [SDTeamEventConflict] = []
  @State private var overrideReason = ""
  @State private var isSaving = false
  @State private var errorText: String?

  init(
    teams: [SDTeamOperationsTeam],
    seasonId: UUID,
    event: SDTeamEvent? = nil,
    isDuplicate: Bool = false,
    editsFuture: Bool = false,
    onSaved: @escaping () -> Void
  ) {
    self.teams = teams
    self.seasonId = seasonId
    self.event = event
    self.isDuplicate = isDuplicate
    self.editsFuture = editsFuture
    self.onSaved = onSaved
    _draft = State(initialValue: event.map(SDTeamEventDraft.init(event:)) ?? SDTeamEventDraft())
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Event") {
          Picker("Type", selection: $draft.type) {
            ForEach(SDTeamEventType.allCases) { Label($0.label, systemImage: $0.systemImage).tag($0) }
          }
          TextField("Title", text: $draft.title)
          TextField("Description", text: $draft.description, axis: .vertical)
          Toggle("All day", isOn: $draft.allDay)
          DatePicker("Starts", selection: $draft.startAt)
          DatePicker("Ends", selection: $draft.endAt)
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
        }
        Section("Location") {
          TextField("Location", text: $draft.locationName)
          TextField("Address", text: $draft.address)
          Picker("Facility resource", selection: $draft.facilityId) {
            Text("None").tag(UUID?.none)
            ForEach(facilities) { facility in Text(facility.name).tag(Optional(facility.id)) }
          }
        }
        subtypeSection
        Section("Team visibility") {
          Picker("Visibility", selection: $draft.visibility) {
            Text("Players and parents").tag(SDTeamEventVisibility.team)
            Text("Staff only").tag(SDTeamEventVisibility.staffOnly)
          }
          TextField("Coach-private notes", text: $draft.notes, axis: .vertical)
        }
        Section("Repeat") {
          Toggle("Recurring event", isOn: $draft.repeats)
          if draft.repeats {
            Picker("Frequency", selection: $draft.recurrenceFrequency) {
              Text("Daily").tag("daily")
              Text("Weekly").tag("weekly")
            }
            Stepper("Every \(draft.recurrenceInterval) \(draft.recurrenceFrequency == "daily" ? "day(s)" : "week(s)")", value: $draft.recurrenceInterval, in: 1...12)
            if draft.recurrenceFrequency == "weekly" {
              ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HP.Space.xs) {
                  ForEach(Array(Self.weekdayLabels.enumerated()), id: \.offset) { weekday, label in
                    Button(label) { toggleWeekday(weekday) }
                      .buttonStyle(.bordered)
                      .tint(draft.recurrenceWeekdays.contains(weekday) ? HP.Color.accent : HP.Color.textMuted)
                      .accessibilityLabel("Repeat on \(Self.fullWeekdayLabels[weekday])")
                      .accessibilityValue(draft.recurrenceWeekdays.contains(weekday) ? "Selected" : "Not selected")
                  }
                }
              }
            }
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
          Button("Schedule") { Task { await save(publish: true) } }.disabled(!canSave || isSaving)
        }
      }
      .alert("Event Not Saved", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
        Button("OK", role: .cancel) {}
      } message: { Text(errorText ?? "") }
      .task { await loadFacilities() }
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
    !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && draft.endAt > draft.startAt
      && (draft.arrivalAt ?? draft.startAt) <= draft.startAt
      && (!draft.repeats || draft.recurrenceFrequency != "weekly" || !draft.recurrenceWeekdays.isEmpty)
      && (!draft.repeats || !draft.recurrenceUsesEndDate || draft.recurrenceEndDate >= Calendar.current.startOfDay(for: draft.startAt))
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
    guard let service = appState.supabase, let organizationId = appState.activeOrgId else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      conflicts = []
      for team in teams {
        conflicts.append(contentsOf: try await service.teamEventConflicts(
          organizationId: organizationId,
          seasonId: seasonId,
          teamId: team.id,
          eventId: isDuplicate ? nil : event?.id,
          startAt: draft.startAt,
          endAt: draft.endAt,
          facilityId: draft.facilityId
        ))
      }
      if !conflicts.isEmpty && overrideReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        errorText = "Review the schedule warnings and enter an override reason to continue."
        return
      }
      for team in teams {
        _ = try await service.saveTeamEvent(
          organizationId: organizationId,
          seasonId: seasonId,
          teamId: team.id,
          eventId: event?.id,
          draft: draft,
          publish: publish,
          overrideReason: overrideReason.sdNilIfBlank,
          coachIds: event?.sd_team_event_coaches?.map(\.coach_id) ?? [],
          actionOverride: isDuplicate ? "duplicate" : editsFuture ? "update_future" : nil
        )
      }
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
