import SwiftUI

struct CoachEventOperationView: View {
  @EnvironmentObject private var appState: AppState
  let event: SDTeamEvent
  let teamName: String

  @State private var operation: SDEventOperation?
  @State private var participants: [SDEventOperationParticipant] = []
  @State private var checklist: [SDEventOperationChecklistItem] = []
  @State private var notes: [SDEventOperationNote] = []
  @State private var tournamentChildren: [SDTeamEvent] = []
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var retryMutation: PendingMutation?
  @State private var attendanceEditor: AttendanceEditorPresentation?
  @State private var availabilityOverride: CoachAvailabilityOverridePresentation?
  @State private var selectedAttendanceIds: Set<UUID> = []
  @State private var completionEditor: CompletionPresentation?
  @State private var checklistOverride: SDEventOperationChecklistItem?
  @State private var checklistOverrideReason = ""
  @State private var noteBody = ""
  @State private var noteType = "team_coach_note"
  @State private var noteVisibility = "staff"
  @State private var notePlayerId: UUID?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        missionCard
        if let operation {
          readinessCard(operation)
          if event.event_type == .practice {
            PracticePlannerView(event: event, operation: operation, teamName: teamName)
          }
          participantsCard(operation)
          checklistCard
          notesCard
          detailsCard
          completionCard(operation)
        } else if !isLoading {
          HPCard {
            HPEmptyState(
              title: "Operation not prepared",
              message: "Initialize this event from its canonical schedule and current roster snapshot.",
              systemImage: "baseball.diamond.bases"
            )
            if can(.startEventOperation) {
              HPButton(title: "Prepare", systemImage: "checklist", variant: .primary, size: .md) {
                run(.initialize(UUID()))
              }
            }
          }
        }
        if let retryMutation {
          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              HPSectionHeader("Field connection interrupted") {
                HPStatusBadge(text: "Unsaved", kind: .warning)
              }
              Text("The pending change is preserved on this screen with its original retry identifier.")
                .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
              HPButton(title: "Retry Pending Change", systemImage: "arrow.clockwise", variant: .primary, size: .md) {
                run(retryMutation)
              }
            }
          }
        }
      }
      .padding(HP.Space.md)
    }
    .background(HP.Color.bg)
    .navigationTitle(operation?.operation_type.label ?? event.event_type.label)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button { Task { await reload() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
      }
    }
    .overlay { if isLoading && operation == nil { ProgressView("Loading mission…") } }
    .task { await reload() }
    .refreshable { await reload() }
    .sheet(item: $attendanceEditor) { presentation in
      AttendanceEditorSheet(presentation: presentation) { status, arrival, departure, attendanceNote, privateNote in
        attendanceEditor = nil
        run(.attendance(
          presentation.participant,
          status,
          arrival,
          departure,
          attendanceNote,
          privateNote,
          UUID()
        ))
      }
    }
    .sheet(item: $availabilityOverride) { presentation in
      CoachAvailabilityOverrideSheet(presentation: presentation) { draft, reason in
        availabilityOverride = nil
        run(.availability(presentation.participant, draft, reason, UUID()))
      }
    }
    .sheet(item: $completionEditor) { presentation in
      OperationCompletionSheet(presentation: presentation) { reason, summary in
        completionEditor = nil
        run(.transition(presentation.status, reason, summary, UUID()))
      }
    }
    .alert("Checklist Override", isPresented: Binding(
      get: { checklistOverride != nil },
      set: { if !$0 { checklistOverride = nil; checklistOverrideReason = "" } }
    )) {
      TextField("Required reason", text: $checklistOverrideReason)
      Button("Override") {
        if let item = checklistOverride {
          run(.checklist(item, true, checklistOverrideReason, UUID()))
        }
        checklistOverride = nil
        checklistOverrideReason = ""
      }
      .disabled(checklistOverrideReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Required checklist items remain visible in history when overridden.")
    }
    .alert("Mission Update", isPresented: Binding(
      get: { errorText != nil },
      set: { if !$0 { errorText = nil } }
    )) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
  }

  private var missionCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader(event.title) {
          HPStatusBadge(text: operation?.status.label ?? "Not Started", kind: operation?.status == .completed ? .success : .info)
        }
        Text("\(teamName) • \(appState.selectedSeason?.name ?? "Season")")
          .font(HP.Font.callout.weight(.semibold)).foregroundStyle(HP.Color.text)
        Label(event.startDate.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
        if let arrival = event.arrivalDate {
          Label("Arrive \(arrival.formatted(date: .omitted, time: .shortened))", systemImage: "figure.walk.arrival")
        }
        if let location = event.location_name?.sdNilIfBlank {
          Label(location, systemImage: "mappin.and.ellipse")
        }
        if let attire = event.uniformOrDressCode?.sdNilIfBlank {
          Label(attire, systemImage: "tshirt")
        }
      }
      .font(HP.Font.callout).foregroundStyle(HP.Color.textMuted)
    }
  }

  private func readinessCard(_ operation: SDEventOperation) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Mission readiness") {
          HPStatusBadge(text: operation.primaryAction, kind: .info)
        }
        HStack(spacing: HP.Space.sm) {
          HPMetricCard(title: "Expected", value: "\(playerParticipants.count)", context: "players")
          HPMetricCard(title: "Availability", value: "\(unresolvedAvailability)", context: "unresolved")
          HPMetricCard(title: "Attendance", value: "\(unrecordedAttendance)", context: "not recorded")
        }
        stateActions(operation)
      }
    }
  }

  @ViewBuilder private func stateActions(_ operation: SDEventOperation) -> some View {
    HStack(spacing: HP.Space.sm) {
      switch operation.status {
      case .notStarted:
        if can(.startEventOperation) { actionButton("Prepare", .ready) }
      case .ready:
        if can(.startEventOperation) {
          actionButton(operation.operation_type == .gameDay ? "Start Game Day" : operation.operation_type == .practiceDay ? "Start Practice" : "Start Check-In", .inProgress)
        }
        if can(.completeEventOperation) {
          HPButton(title: "Complete with Reason", systemImage: "checkmark.circle", variant: .secondary, size: .md) {
            completionEditor = CompletionPresentation(status: .completed, requiresReason: true)
          }
        }
      case .inProgress:
        if can(.startEventOperation) { actionButton("Pause", .paused, secondary: true) }
        if can(.completeEventOperation) {
          HPButton(title: "Complete Event", systemImage: "checkmark.circle", variant: .primary, size: .md) {
            completionEditor = CompletionPresentation(status: .completed, requiresReason: hasCompletionBlockers)
          }
        }
      case .paused:
        if can(.startEventOperation) { actionButton("Resume", .inProgress) }
      case .completed:
        if can(.reopenEventOperation) {
          HPButton(title: "Reopen", systemImage: "arrow.uturn.backward", variant: .secondary, size: .md) {
            completionEditor = CompletionPresentation(status: .ready, requiresReason: true)
          }
        }
      case .cancelled:
        EmptyView()
      }
    }
  }

  private func actionButton(_ title: String, _ status: SDEventOperationStatus, secondary: Bool = false) -> some View {
    HPButton(title: title, systemImage: "arrow.right.circle", variant: secondary ? .secondary : .primary, size: .md) {
      run(.transition(status, nil, nil, UUID()))
    }
  }

  private func participantsCard(_ operation: SDEventOperation) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Participants") {
          HPStatusBadge(text: "\(playerParticipants.count) players", kind: .neutral)
        }
        HStack {
          if can(.manageEventAttendance), !playerParticipants.isEmpty,
             operation.status != .completed, operation.attendance_finalized_at == nil {
            HPButton(title: "Mark All Present", systemImage: "checkmark.circle", variant: .secondary, size: .sm) {
              run(.bulkAttendance(playerParticipants, .present, UUID()))
            }
            if !selectedAttendanceIds.isEmpty {
              HPButton(title: "Mark Selected", systemImage: "checkmark.circle", variant: .secondary, size: .sm) {
                run(.bulkAttendance(
                  playerParticipants.filter { selectedAttendanceIds.contains($0.id) },
                  .present,
                  UUID()
                ))
              }
            }
            HPButton(title: "Finalize Attendance", systemImage: "lock", variant: .secondary, size: .sm) {
              run(.finalize(operation.version, UUID()))
            }
          }
        }
        ForEach(playerParticipants) { participant in
          HStack(alignment: .center, spacing: HP.Space.sm) {
            HPAvatar(name: participantName(participant), size: .sm)
            VStack(alignment: .leading, spacing: 2) {
              Text(participantName(participant)).font(HP.Font.callout.weight(.semibold))
              Text("Availability: \(participant.availability_status.label) • Attendance: \(participant.attendance_status.label)")
                .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            }
            Spacer()
            if can(.manageEventAttendance), operation.status != .completed,
               operation.attendance_finalized_at == nil {
              Button {
                if selectedAttendanceIds.contains(participant.id) {
                  selectedAttendanceIds.remove(participant.id)
                } else {
                  selectedAttendanceIds.insert(participant.id)
                }
              } label: {
                Image(systemName: selectedAttendanceIds.contains(participant.id) ? "checkmark.square.fill" : "square")
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Select \(participantName(participant))")
            }
            if can(.manageEventAvailability), operation.status != .completed {
              Button("Availability") {
                availabilityOverride = CoachAvailabilityOverridePresentation(participant: participant)
              }
              .buttonStyle(.bordered).controlSize(.small)
            }
            if can(.manageEventAttendance), operation.status != .completed,
               operation.attendance_finalized_at == nil {
              Button("Edit") {
                attendanceEditor = AttendanceEditorPresentation(
                  participant: participant,
                  canEditPrivateNotes: can(.addPrivatePlayerNotes)
                )
              }
                .buttonStyle(.bordered).controlSize(.small)
            }
          }
          .frame(minHeight: 48)
        }
      }
    }
  }

  private var checklistCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Checklist") {
          HPStatusBadge(text: "\(checklist.filter(\.isHandled).count)/\(checklist.count)", kind: .neutral)
        }
        if checklist.isEmpty {
          Text("No configured operational items.").font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        }
        ForEach(checklist) { item in
          HStack {
            Button {
              guard can(.manageEventChecklist) else { return }
              run(.checklist(item, !item.isHandled, nil, UUID()))
            } label: {
              Label(item.title, systemImage: item.isHandled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.isHandled ? HP.Color.success : HP.Color.text)
            }
            .buttonStyle(.plain)
            Spacer()
            if item.required && !item.isHandled && can(.manageEventChecklist) {
              Button("Override") { checklistOverride = item }.buttonStyle(.borderless)
            }
          }
          if let details = item.details?.sdNilIfBlank {
            Text(details).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
          }
        }
      }
    }
  }

  private var notesCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Notes")
        ForEach(notes) { note in
          VStack(alignment: .leading, spacing: 2) {
            Text(note.note_type.replacingOccurrences(of: "_", with: " ").capitalized)
              .font(HP.Font.caption.weight(.semibold)).foregroundStyle(HP.Color.textMuted)
            Text(note.body).font(HP.Font.callout).foregroundStyle(HP.Color.text)
          }
        }
        if can(.addTeamEventNotes) || can(.addPrivatePlayerNotes) {
          Picker("Type", selection: $noteType) {
            if can(.addTeamEventNotes) {
              Text("Coach Note").tag("team_coach_note")
              Text("Internal Staff Note").tag("internal_staff_note")
              Text("Post-Event Recap").tag("post_event_recap")
            }
            if can(.addPrivatePlayerNotes) { Text("Player-Specific Note").tag("player_coach_note") }
          }
          .onAppear {
            if !can(.addTeamEventNotes) && can(.addPrivatePlayerNotes) {
              noteType = "player_coach_note"
              noteVisibility = "staff"
            }
          }
          if noteType == "player_coach_note" {
            Picker("Player", selection: $notePlayerId) {
              Text("Select player").tag(UUID?.none)
              ForEach(playerParticipants) { participant in
                Text(participantName(participant)).tag(Optional(participant.user_id))
              }
            }
          }
          Picker("Visibility", selection: $noteVisibility) {
            Text("Staff only").tag("staff")
            if noteType != "internal_staff_note" && noteType != "player_coach_note" {
              Text("Team visible").tag("team")
            }
            if noteType == "player_coach_note" { Text("Player visible").tag("player") }
          }
          .disabled(noteType == "post_event_recap")
          .onChange(of: noteType) { _, type in
            if type == "post_event_recap" {
              noteVisibility = "team"
            } else if type == "internal_staff_note" {
              noteVisibility = "staff"
            } else if type == "player_coach_note" && noteVisibility == "team" {
              noteVisibility = "staff"
            } else if type == "team_coach_note" && noteVisibility == "player" {
              noteVisibility = "staff"
            }
          }
          TextField("Operational note", text: $noteBody, axis: .vertical)
          HPButton(title: noteType == "post_event_recap" ? "Publish Recap" : "Add Note", systemImage: "square.and.pencil", variant: .secondary, size: .md) {
            let visibility = noteType == "post_event_recap"
              ? "team"
              : noteType == "internal_staff_note" || (noteType == "player_coach_note" && noteVisibility == "team")
                ? "staff"
                : noteVisibility
            run(.note(noteType, visibility, noteBody, notePlayerId, UUID()))
          }
          .disabled(noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (noteType == "player_coach_note" && notePlayerId == nil))
        }
      }
    }
  }

  private var detailsCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Event details")
        if let description = event.description?.sdNilIfBlank { Text(description) }
        if let game = event.sd_team_event_games?.first {
          Text("Opponent: \(game.opponent) • \(game.venue_side.capitalized)")
        }
        if let tournament = event.sd_team_event_tournaments?.first {
          Text("Tournament: \(tournament.tournament_name)")
          if tournamentChildren.isEmpty {
            Text("No canonical child events are currently scheduled.")
              .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
          } else {
            ForEach(tournamentChildren) { child in
              Label(
                "\(child.startDate.formatted(date: .abbreviated, time: .shortened)) • \(child.title)",
                systemImage: child.event_type.systemImage
              )
            }
          }
        }
        if let meeting = event.sd_team_event_meetings?.first, let link = meeting.virtual_link?.sdNilIfBlank {
          Text("Meeting link: \(link)")
        }
        if let travel = event.sd_team_event_travel?.first {
          Text("Destination: \(travel.destination)")
          if let transportation = travel.transportation_notes?.sdNilIfBlank { Text(transportation) }
          if let lodging = travel.lodging_notes?.sdNilIfBlank { Text(lodging) }
        }
        Text("Practice Planner, stations, drills, and live scorekeeping are not part of this operation workspace.")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
      }
      .font(HP.Font.callout).foregroundStyle(HP.Color.text)
    }
  }

  private func completionCard(_ operation: SDEventOperation) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Completion")
        if operation.status == .completed {
          Label("Event operation completed", systemImage: "checkmark.seal.fill")
            .foregroundStyle(HP.Color.success)
          if let summary = operation.operational_summary?.sdNilIfBlank { Text(summary) }
        } else {
          Text(hasCompletionBlockers
               ? "Attendance or required checklist items still need review. Completion requires an explicit reason."
               : "Attendance and required checklist items are ready for completion.")
            .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        }
      }
    }
  }

  private var playerParticipants: [SDEventOperationParticipant] {
    participants.filter { $0.participant_type == "player" && $0.expected }
  }

  private var unresolvedAvailability: Int {
    playerParticipants.filter { $0.availability_status == .unknown || $0.availability_status == .tentative }.count
  }

  private var unrecordedAttendance: Int {
    playerParticipants.filter { $0.attendance_status == .notRecorded }.count
  }

  private var hasCompletionBlockers: Bool {
    unrecordedAttendance > 0 || checklist.contains { $0.required && !$0.isHandled }
  }

  private func participantName(_ participant: SDEventOperationParticipant) -> String {
    appState.teamOperationsContext?.people.first(where: { $0.id == participant.user_id })?.displayName
      ?? "Player \(participant.user_id.uuidString.prefix(6))"
  }

  private func can(_ capability: SDTeamCapability) -> Bool {
    appState.canAdminActiveOrg ||
      appState.authorizedCoachTeams.first(where: { $0.id == event.team_id })?.capabilitySet.contains(capability) == true
  }

  private func reload() async {
    guard let service = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let response = try await service.eventOperation(organizationId: event.organization_id, eventId: event.id)
      operation = response.operation
      participants = response.participants ?? []
      checklist = response.checklist ?? []
      notes = response.notes ?? []
      if event.event_type == .tournament {
        let start = Calendar.current.date(byAdding: .day, value: -1, to: event.startDate)!
        let end = Calendar.current.date(byAdding: .day, value: 14, to: event.endDate)!
        tournamentChildren = try await service.listTeamEvents(
          organizationId: event.organization_id,
          seasonId: event.season_id,
          teamId: event.team_id,
          rangeStart: start,
          rangeEnd: end
        ).filter {
          $0.sd_team_event_tournaments?.first?.parent_tournament_event_id == event.id
        }
      } else {
        tournamentChildren = []
      }
      errorText = nil
    } catch {
      errorText = "The event mission could not be refreshed. Existing unsent changes remain available for retry."
    }
  }

  private func run(_ mutation: PendingMutation) {
    Task {
      guard let service = appState.supabase else { return }
      isLoading = true
      defer { isLoading = false }
      do {
        switch mutation {
        case .initialize(let requestId):
          _ = try await service.initializeEventOperation(organizationId: event.organization_id, eventId: event.id, requestId: requestId)
        case .transition(let status, let reason, let summary, let requestId):
          guard let operation else { return }
          _ = try await service.transitionEventOperation(
            organizationId: event.organization_id,
            eventId: event.id,
            expectedVersion: operation.version,
            status: status,
            reason: reason,
            summary: summary,
            requestId: requestId
          )
        case .attendance(let participant, let status, let arrival, let departure, let attendanceNote, let privateNote, let requestId):
          _ = try await service.updateEventAttendance(
            organizationId: event.organization_id,
            eventId: event.id,
            participantId: participant.id,
            participantVersion: participant.version,
            status: status,
            arrivalAt: arrival,
            departureAt: departure,
            attendanceNotes: attendanceNote,
            privateNotes: privateNote,
            correctionReason: operation?.status == .completed ? "Authorized post-completion correction" : nil,
            requestId: requestId
          )
        case .availability(let participant, let draft, let reason, let requestId):
          _ = try await service.updateEventAvailability(
            organizationId: event.organization_id,
            eventId: event.id,
            playerId: participant.user_id,
            participantVersion: participant.version,
            draft: draft,
            overrideReason: reason,
            requestId: requestId
          )
        case .bulkAttendance(let participants, let status, let requestId):
          _ = try await service.bulkUpdateEventAttendance(
            organizationId: event.organization_id,
            eventId: event.id,
            participants: participants,
            status: status,
            correctionReason: operation?.status == .completed ? "Authorized post-completion bulk correction" : nil,
            requestId: requestId
          )
        case .finalize(let version, let requestId):
          _ = try await service.finalizeEventAttendance(
            organizationId: event.organization_id,
            eventId: event.id,
            expectedVersion: version,
            reason: unrecordedAttendance > 0 ? "Authorized attendance finalization override" : nil,
            requestId: requestId
          )
        case .checklist(let item, let completed, let overrideReason, let requestId):
          _ = try await service.updateEventChecklist(
            organizationId: event.organization_id,
            eventId: event.id,
            itemId: item.id,
            itemVersion: item.version,
            completed: completed,
            overrideReason: overrideReason,
            requestId: requestId
          )
        case .note(let type, let visibility, let body, let playerId, let requestId):
          _ = try await service.addEventOperationNote(
            organizationId: event.organization_id,
            eventId: event.id,
            type: type,
            visibility: visibility,
            body: body,
            playerId: playerId,
            requestId: requestId
          )
          noteBody = ""
        }
        retryMutation = nil
        await reload()
      } catch {
        retryMutation = mutation
        errorText = "The field connection did not confirm this change. Refresh for stale data or retry the preserved update."
      }
    }
  }
}

private enum PendingMutation: Equatable {
  case initialize(UUID)
  case transition(SDEventOperationStatus, String?, String?, UUID)
  case attendance(SDEventOperationParticipant, SDEventAttendanceStatus, Date?, Date?, String?, String?, UUID)
  case availability(SDEventOperationParticipant, SDEventAvailabilityDraft, String, UUID)
  case bulkAttendance([SDEventOperationParticipant], SDEventAttendanceStatus, UUID)
  case finalize(Int, UUID)
  case checklist(SDEventOperationChecklistItem, Bool, String?, UUID)
  case note(String, String, String, UUID?, UUID)
}

private struct CoachAvailabilityOverridePresentation: Identifiable {
  let id = UUID()
  let participant: SDEventOperationParticipant
}

private struct CoachAvailabilityOverrideSheet: View {
  @Environment(\.dismiss) private var dismiss
  let presentation: CoachAvailabilityOverridePresentation
  let onSave: (SDEventAvailabilityDraft, String) -> Void
  @State private var draft: SDEventAvailabilityDraft
  @State private var overrideReason = ""

  init(
    presentation: CoachAvailabilityOverridePresentation,
    onSave: @escaping (SDEventAvailabilityDraft, String) -> Void
  ) {
    self.presentation = presentation
    self.onSave = onSave
    _draft = State(initialValue: SDEventAvailabilityDraft(
      status: presentation.participant.availability_status,
      reason: presentation.participant.availability_reason ?? "",
      expectedArrival: SDEventOperationDateParser.date(presentation.participant.expected_arrival_at),
      expectedDeparture: SDEventOperationDateParser.date(presentation.participant.expected_departure_at)
    ))
  }

  var body: some View {
    NavigationStack {
      Form {
        Picker("Availability", selection: $draft.status) {
          ForEach(SDEventAvailabilityStatus.allCases) { Text($0.label).tag($0) }
        }
        TextField("Availability reason", text: $draft.reason, axis: .vertical)
        if draft.status == .late {
          DatePicker("Expected arrival", selection: Binding(
            get: { draft.expectedArrival ?? Date() },
            set: { draft.expectedArrival = $0 }
          ))
        }
        if draft.status == .leavingEarly {
          DatePicker("Expected departure", selection: Binding(
            get: { draft.expectedDeparture ?? Date() },
            set: { draft.expectedDeparture = $0 }
          ))
        }
        TextField("Required coach override reason", text: $overrideReason, axis: .vertical)
      }
      .navigationTitle("Override Availability")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Apply") {
            if draft.status == .late && draft.expectedArrival == nil {
              draft.expectedArrival = Date()
            }
            if draft.status == .leavingEarly && draft.expectedDeparture == nil {
              draft.expectedDeparture = Date()
            }
            onSave(draft, overrideReason)
          }
            .disabled(overrideReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }
}

private struct AttendanceEditorPresentation: Identifiable {
  let id = UUID()
  let participant: SDEventOperationParticipant
  let canEditPrivateNotes: Bool
}

private struct AttendanceEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  let presentation: AttendanceEditorPresentation
  let onSave: (SDEventAttendanceStatus, Date?, Date?, String?, String?) -> Void
  @State private var status: SDEventAttendanceStatus
  @State private var setArrival = false
  @State private var arrival = Date()
  @State private var setDeparture = false
  @State private var departure = Date()
  @State private var attendanceNote = ""
  @State private var privateNote = ""

  init(
    presentation: AttendanceEditorPresentation,
    onSave: @escaping (SDEventAttendanceStatus, Date?, Date?, String?, String?) -> Void
  ) {
    self.presentation = presentation
    self.onSave = onSave
    _status = State(initialValue: presentation.participant.attendance_status)
    let existingArrival = SDEventOperationDateParser.date(presentation.participant.arrival_at)
    let existingDeparture = SDEventOperationDateParser.date(presentation.participant.departure_at)
    _setArrival = State(initialValue: existingArrival != nil)
    _arrival = State(initialValue: existingArrival ?? Date())
    _setDeparture = State(initialValue: existingDeparture != nil)
    _departure = State(initialValue: existingDeparture ?? Date())
    _attendanceNote = State(initialValue: presentation.participant.attendance_notes ?? "")
    _privateNote = State(initialValue: presentation.participant.private_notes ?? "")
  }

  var body: some View {
    NavigationStack {
      Form {
        Picker("Attendance", selection: $status) {
          ForEach(SDEventAttendanceStatus.allCases) { Text($0.label).tag($0) }
        }
        Toggle("Record arrival", isOn: $setArrival)
        if setArrival { DatePicker("Arrival", selection: $arrival) }
        Toggle("Record early departure", isOn: $setDeparture)
        if setDeparture { DatePicker("Departure", selection: $departure) }
        TextField("Attendance annotation", text: $attendanceNote, axis: .vertical)
        if presentation.canEditPrivateNotes {
          TextField("Private attendance note", text: $privateNote, axis: .vertical)
        }
      }
      .navigationTitle("Attendance")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            onSave(
              status,
              setArrival ? arrival : nil,
              setDeparture ? departure : nil,
              attendanceNote.sdNilIfBlank,
              presentation.canEditPrivateNotes ? privateNote.sdNilIfBlank : nil
            )
          }
        }
      }
    }
  }
}

private struct CompletionPresentation: Identifiable {
  let id = UUID()
  let status: SDEventOperationStatus
  let requiresReason: Bool
}

private struct OperationCompletionSheet: View {
  @Environment(\.dismiss) private var dismiss
  let presentation: CompletionPresentation
  let onSave: (String?, String?) -> Void
  @State private var reason = ""
  @State private var summary = ""

  var body: some View {
    NavigationStack {
      Form {
        if presentation.requiresReason {
          TextField(presentation.status == .ready ? "Reopen reason" : "Completion override reason", text: $reason, axis: .vertical)
        }
        if presentation.status == .completed {
          TextField("Operational summary (optional)", text: $summary, axis: .vertical)
        }
      }
      .navigationTitle(presentation.status == .ready ? "Reopen Event" : "Complete Event")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Confirm") { onSave(reason.sdNilIfBlank, summary.sdNilIfBlank) }
            .disabled(presentation.requiresReason && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }
}

private struct PracticePlannerView: View {
  @EnvironmentObject private var appState: AppState
  let event: SDTeamEvent
  let operation: SDEventOperation
  let teamName: String
  @State private var plan: SDPracticePlan?
  @State private var blocks: [SDPracticePlanBlock] = []
  @State private var groups: [SDPracticePlanGroup] = []
  @State private var assignments: [SDPracticePlanAssignment] = []
  @State private var equipment: [SDPracticeEquipmentRequirement] = []
  @State private var executions: [SDPracticeBlockExecution] = []
  @State private var validation: SDPracticePlanValidation?
  @State private var templates: [SDPracticePlanTemplate] = []
  @State private var priorPlans: [SDPracticePriorPlan] = []
  @State private var history: [SDPracticePlanSnapshot] = []
  @State private var showWorkspace = false
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var pendingMutation: PendingPracticeMutation?

  var body: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Practice Plan") {
          HPStatusBadge(text: plan?.status.label ?? "No Plan", kind: badgeKind)
        }
        if let plan {
          Text(plan.title).font(HP.Font.headline).foregroundStyle(HP.Color.text)
          HStack(spacing: HP.Space.sm) {
            HPMetricCard(title: "Duration", value: "\(validation?.total_duration_minutes ?? 0)m", context: "planned")
            HPMetricCard(title: "Blocks", value: "\(blocks.filter { $0.parent_block_id == nil }.count)", context: "sequential")
            HPMetricCard(title: "Groups", value: "\(groups.count)", context: "player groups")
          }
          if let validation {
            Label(
              validation.blocking_errors.isEmpty
                ? validation.readiness_warnings.isEmpty ? "Plan is ready" : "\(validation.readiness_warnings.count) readiness warning(s)"
                : "\(validation.blocking_errors.count) blocking error(s)",
              systemImage: validation.blocking_errors.isEmpty ? "checkmark.circle" : "exclamationmark.triangle"
            )
            .font(HP.Font.caption).foregroundStyle(validation.blocking_errors.isEmpty ? HP.Color.textMuted : HP.Color.danger)
          }
          if plan.status == .active, let current = currentExecution {
            Text("Current: \(current.title)").font(HP.Font.callout.weight(.semibold))
            if let nextExecution { Text("Next: \(nextExecution.title)").font(HP.Font.caption).foregroundStyle(HP.Color.textMuted) }
          }
          HPButton(title: plan.status == .active ? "Run Practice Plan" : "Open Practice Plan", systemImage: "list.number", variant: .primary, size: .md) {
            showWorkspace = true
          }
        } else if can(.createPracticePlan) {
          Text("Create a plan from blank, an organization template, or a completed team practice.")
            .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
          HStack(spacing: HP.Space.sm) {
            HPButton(title: "Create Plan", systemImage: "plus", variant: .primary, size: .sm) {
              run("initialize_blank_plan", ["title": .string(event.title)])
            }
            Menu("Build from Template") {
              if templates.isEmpty { Text("No active templates") }
              ForEach(templates) { template in
                Button(template.name) { run("initialize_from_template", ["template_id": .string(template.id.uuidString), "title": .string(event.title)]) }
              }
            }
            Menu("Duplicate Prior") {
              if priorPlans.isEmpty { Text("No completed practices") }
              ForEach(priorPlans) { prior in
                Button(prior.title) { run("duplicate_prior_plan", ["source_plan_id": .string(prior.id.uuidString), "title": .string(event.title), "objectives": .array(prior.objectives.map(SDJSONValue.string))]) }
              }
            }
          }
          ForEach(templates.prefix(3)) { template in
            DisclosureGroup("Preview: \(template.name)") {
              Text(template.description ?? "Reusable practice structure")
              if !template.objectives.isEmpty { Text(template.objectives.joined(separator: " • ")) }
            }
            .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
          }
        } else {
          Text("No practice plan is available. Your team responsibility is read-only.")
            .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        }
        if pendingMutation != nil {
          HPButton(title: "Retry Pending Plan Change", systemImage: "arrow.clockwise", variant: .secondary, size: .sm) {
            if let pendingMutation { run(pendingMutation.action, pendingMutation.data, requestId: pendingMutation.requestId) }
          }
        }
      }
    }
    .overlay { if isLoading { ProgressView() } }
    .task { await reload() }
    .sheet(isPresented: $showWorkspace) {
      NavigationStack {
        PracticePlannerWorkspace(
          event: event,
          teamName: teamName,
          operation: operation,
          plan: plan,
          blocks: blocks,
          groups: groups,
          assignments: assignments,
          equipment: equipment,
          executions: executions,
          history: history,
          validation: validation,
          players: appState.teamOperationsContext?.players(for: event.team_id) ?? [],
          coaches: appState.teamOperationsContext?.staff(for: event.team_id) ?? [],
          capabilities: capabilitySet,
          onMutation: { action, data in run(action, data) }
        )
      }
    }
    .alert("Practice Planner", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
  }

  private var capabilitySet: Set<SDTeamCapability> {
    if appState.canAdminActiveOrg { return Set(SDTeamCapability.allCases) }
    return appState.authorizedCoachTeams.first(where: { $0.id == event.team_id })?.capabilitySet ?? []
  }
  private func can(_ capability: SDTeamCapability) -> Bool { capabilitySet.contains(capability) }
  private var badgeKind: HPStatusKind {
    switch plan?.status { case .published, .completed: .success; case .active: .info; case .draft, .ready: .warning; default: .neutral }
  }
  private var currentExecution: SDPracticeBlockExecution? { executions.first { $0.status == .active && $0.parent_block_id == nil } }
  private var nextExecution: SDPracticeBlockExecution? { executions.filter { $0.status == .pending && $0.parent_block_id == nil }.sorted { $0.sequence_index < $1.sequence_index }.first }

  private func reload() async {
    guard let service = appState.supabase else { return }
    isLoading = true; defer { isLoading = false }
    do {
      async let detail = service.practicePlan(organizationId: event.organization_id, eventId: event.id)
      async let availableTemplates = service.practiceTemplates(organizationId: event.organization_id, eventId: event.id, teamId: event.team_id)
      async let availablePrior = service.priorPracticePlans(organizationId: event.organization_id, eventId: event.id, teamId: event.team_id)
      let response = try await detail
      plan = response.plan; blocks = response.blocks; groups = response.groups; assignments = response.assignments
      equipment = response.equipment; executions = response.executions; validation = response.validation
      templates = (try? await availableTemplates) ?? []
      priorPlans = (try? await availablePrior) ?? []
      if response.plan == nil {
        history = []
      } else {
        history = (try? await service.practicePlanHistory(
          organizationId: event.organization_id,
          eventId: event.id
        )) ?? []
      }
      errorText = nil
    } catch { errorText = "The practice plan could not be refreshed. Any pending change remains available for retry." }
  }

  private func run(_ action: String, _ data: [String: SDJSONValue], requestId: UUID = UUID()) {
    Task {
      guard let service = appState.supabase else { return }
      isLoading = true; defer { isLoading = false }
      do {
        _ = try await service.mutatePracticePlan(action: action, organizationId: event.organization_id, eventId: event.id, data: data, requestId: requestId)
        pendingMutation = nil
        await reload()
      } catch {
        pendingMutation = PendingPracticeMutation(action: action, data: data, requestId: requestId)
        errorText = "This plan change was not confirmed. Refresh stale data or retry the preserved change."
      }
    }
  }
}

private struct PendingPracticeMutation: Equatable {
  let action: String
  let data: [String: SDJSONValue]
  let requestId: UUID
}

private struct PracticePlannerWorkspace: View {
  @Environment(\.dismiss) private var dismiss
  let event: SDTeamEvent
  let teamName: String
  let operation: SDEventOperation
  let plan: SDPracticePlan?
  let blocks: [SDPracticePlanBlock]
  let groups: [SDPracticePlanGroup]
  let assignments: [SDPracticePlanAssignment]
  let equipment: [SDPracticeEquipmentRequirement]
  let executions: [SDPracticeBlockExecution]
  let history: [SDPracticePlanSnapshot]
  let validation: SDPracticePlanValidation?
  let players: [Profile]
  let coaches: [Profile]
  let capabilities: Set<SDTeamCapability>
  let onMutation: (String, [String: SDJSONValue]) -> Void
  @State private var title = ""
  @State private var objectives = ""
  @State private var blockTitle = ""
  @State private var blockType: SDPracticeBlockType = .warmup
  @State private var blockDuration = 15
  @State private var blockVisibility = "team_visible"
  @State private var groupName = ""
  @State private var equipmentName = ""
  @State private var equipmentQuantity = 1
  @State private var selectedPlayer: UUID?
  @State private var selectedCoach: UUID?
  @State private var selectedGroup: UUID?
  @State private var selectedBlock: UUID?
  @State private var templateName = ""
  @State private var adjustmentReason = ""
  @State private var editingBlock: SDPracticePlanBlock?
  @State private var editingEquipment: SDPracticeEquipmentRequirement?

  var body: some View {
    Form {
      summarySection
      validationSection
      if plan?.status == .active { executionSection }
      if plan?.status == .completed { completionSection }
      if capabilities.contains(.editPracticePlan), plan?.status != .active, plan?.status != .completed { editorSection }
      blocksSection
      if capabilities.contains(.assignPracticeGroups) { groupsSection }
      if capabilities.contains(.assignPracticePlayers) || capabilities.contains(.assignPracticeCoaches) { assignmentsSection }
      if capabilities.contains(.managePracticeEquipment) { equipmentSection }
      if capabilities.contains(.managePracticeTemplates) { templateSection }
      publicationSection
    }
    .navigationTitle(plan?.title ?? "Practice Plan")
    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    .onAppear {
      title = plan?.title ?? event.title
      objectives = plan?.objectives.joined(separator: "\n") ?? ""
      selectedPlayer = players.first?.id; selectedCoach = coaches.first?.id; selectedGroup = groups.first?.id; selectedBlock = topBlocks.first?.id
    }
    .sheet(item: $editingBlock) { block in
      PracticeBlockEditSheet(block: block) { data in onMutation("update_block", data); editingBlock = nil }
    }
    .sheet(item: $editingEquipment) { item in
      PracticeEquipmentEditSheet(item: item) { data in onMutation("update_equipment_requirement", data); editingEquipment = nil }
    }
  }

  private var topBlocks: [SDPracticePlanBlock] { blocks.filter { $0.parent_block_id == nil }.sorted { $0.sequence_index < $1.sequence_index } }
  private var current: SDPracticeBlockExecution? { executions.first { $0.status == .active && $0.parent_block_id == nil } }
  private var next: SDPracticeBlockExecution? { executions.filter { $0.status == .pending && $0.parent_block_id == nil }.sorted { $0.sequence_index < $1.sequence_index }.first }

  private var summarySection: some View {
    Section("Plan Summary") {
      LabeledContent("Team", value: teamName)
      LabeledContent("Status", value: plan?.status.label ?? "No Plan")
      LabeledContent("Planned duration", value: "\(validation?.total_duration_minutes ?? 0) minutes")
      LabeledContent("Published version", value: plan?.published_version.map(String.init) ?? "Not published")
      if let objectives = plan?.objectives, !objectives.isEmpty { Text(objectives.joined(separator: " • ")) }
    }
  }

  @ViewBuilder private var validationSection: some View {
    if let validation {
      Section("Readiness Validation") {
        if validation.blocking_errors.isEmpty && validation.readiness_warnings.isEmpty { Label("Ready", systemImage: "checkmark.circle.fill") }
        ForEach(validation.blocking_errors) { Label($0.label, systemImage: "xmark.octagon").foregroundStyle(HP.Color.danger) }
        ForEach(validation.readiness_warnings) { Label($0.label, systemImage: "exclamationmark.triangle") }
        ForEach(validation.notices) { Label($0.label, systemImage: "info.circle") }
      }
    }
  }

  private var editorSection: some View {
    Section("Plan Editor") {
      TextField("Plan title", text: $title)
      TextField("Objectives, one per line", text: $objectives, axis: .vertical)
      Button("Save Plan Details") {
        guard let plan else { return }
        onMutation("update_plan", ["expected_version": .int(plan.version), "title": .string(title), "objectives": .array(objectives.split(separator: "\n").map { .string(String($0)) })])
      }
      TextField("New block title", text: $blockTitle)
      Picker("Block type", selection: $blockType) { ForEach(SDPracticeBlockType.allCases) { Text($0.label).tag($0) } }
      Stepper("Duration: \(blockDuration) minutes", value: $blockDuration, in: blockType == .arrival ? 0...240 : 1...240)
      Picker("Visibility", selection: $blockVisibility) { Text("Staff Only").tag("staff_only"); Text("Team Visible").tag("team_visible"); Text("Player Visible").tag("player_visible") }
      Button("Add Block") {
        onMutation("add_block", ["title": .string(blockTitle), "block_type": .string(blockType.rawValue), "sequence_index": .int(topBlocks.count), "start_offset_minutes": .int(topBlocks.reduce(0) { $0 + $1.duration_minutes }), "duration_minutes": .int(blockDuration), "visibility": .string(blockVisibility)])
        blockTitle = ""
      }.disabled(blockTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
  }

  private var blocksSection: some View {
    Section("Block List and Parallel Stations") {
      if topBlocks.isEmpty { Text("No blocks yet") }
      ForEach(topBlocks) { block in
        VStack(alignment: .leading) {
          Text(block.title).font(.headline)
          Text("\(block.start_offset_minutes)m • \(block.duration_minutes)m • \(block.block_type.label)").font(.caption)
          ForEach(blocks.filter { $0.parent_block_id == block.id }) { station in Text("Station: \(station.station_name ?? station.title)").font(.caption) }
          if capabilities.contains(.editPracticePlan), plan?.status != .active, plan?.status != .completed {
            HStack {
              Button("Move Up") { reorder(block, delta: -1) }.disabled(block.sequence_index == 0)
              Button("Move Down") { reorder(block, delta: 1) }.disabled(block.sequence_index >= topBlocks.count - 1)
              Button("Add Station") {
                onMutation("add_station", ["parent_block_id": .string(block.id.uuidString), "title": .string("New Station"), "station_name": .string("New Station"), "parallel_group_key": .string(block.id.uuidString), "block_type": .string(block.block_type.rawValue), "sequence_index": .int(blocks.filter { $0.parent_block_id == block.id }.count), "start_offset_minutes": .int(block.start_offset_minutes), "duration_minutes": .int(block.duration_minutes), "visibility": .string(block.visibility)])
              }
              Button("Edit") { editingBlock = block }
              Button("Remove", role: .destructive) { onMutation("remove_block", ["block_id": .string(block.id.uuidString), "expected_version": .int(block.version)]) }
            }.buttonStyle(.borderless)
          }
          ForEach(blocks.filter { $0.parent_block_id == block.id }) { station in
            if capabilities.contains(.editPracticePlan), plan?.status != .active, plan?.status != .completed {
              HStack {
                Button("Edit \(station.station_name ?? station.title)") { editingBlock = station }
                Button("Remove Station", role: .destructive) { onMutation("remove_station", ["block_id": .string(station.id.uuidString), "expected_version": .int(station.version)]) }
              }.buttonStyle(.borderless).font(.caption)
            }
          }
        }
      }
    }
  }

  private var groupsSection: some View {
    Section("Group Manager") {
      ForEach(groups) { group in
        HStack { Text(group.name); Spacer(); Button("Archive") { onMutation("archive_group", ["group_id": .string(group.id.uuidString), "expected_version": .int(group.version)]) } }
      }
      TextField("Group name", text: $groupName)
      Button("Create Group") { onMutation("create_group", ["name": .string(groupName), "sort_order": .int(groups.count)]); groupName = "" }
        .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
  }

  private var assignmentsSection: some View {
    Section("Player and Coach Assignment") {
      if capabilities.contains(.assignPracticePlayers), !players.isEmpty {
        Picker("Player", selection: $selectedPlayer) { ForEach(players) { Text($0.displayName).tag(Optional($0.id)) } }
        Picker("Default group", selection: $selectedGroup) { Text("Unassigned").tag(UUID?.none); ForEach(groups) { Text($0.name).tag(Optional($0.id)) } }
        Button("Assign Player") { if let selectedPlayer { onMutation("assign_player", ["user_id": .string(selectedPlayer.uuidString), "group_id": selectedGroup.map { .string($0.uuidString) } ?? .null]) } }
      }
      if capabilities.contains(.assignPracticeCoaches), !coaches.isEmpty {
        Picker("Coach", selection: $selectedCoach) { ForEach(coaches) { Text($0.displayName).tag(Optional($0.id)) } }
        Picker("Block / Station", selection: $selectedBlock) { Text("Plan lead").tag(UUID?.none); ForEach(blocks) { Text($0.title).tag(Optional($0.id)) } }
        Button("Assign Coach") { if let selectedCoach { onMutation("assign_coach", ["user_id": .string(selectedCoach.uuidString), "block_id": selectedBlock.map { .string($0.uuidString) } ?? .null, "is_lead": .bool(selectedBlock == nil)]) } }
      }
      Text("Assignments are revalidated against the event participant snapshot and active team staff.").font(.caption)
      ForEach(assignments) { assignment in
        HStack {
          Text(assignment.assignment_type.capitalized + " assignment").font(.caption)
          Spacer()
          if assignment.assignment_type == "player" || assignment.assignment_type == "coach" {
            Button("Remove", role: .destructive) { onMutation(assignment.assignment_type == "player" ? "unassign_player" : "unassign_coach", ["assignment_id": .string(assignment.id.uuidString)]) }
          }
        }
      }
    }
  }

  private var equipmentSection: some View {
    Section("Equipment Requirements") {
      ForEach(equipment) { item in
        HStack { Text("\(item.quantity)× \(item.name)"); Spacer(); Button("Edit") { editingEquipment = item }; Image(systemName: item.prepared ? "checkmark.circle.fill" : "circle") }
          .contentShape(Rectangle()).onTapGesture { onMutation("update_equipment_requirement", ["equipment_id": .string(item.id.uuidString), "expected_version": .int(item.version), "prepared": .bool(!item.prepared)]) }
      }
      TextField("Equipment name", text: $equipmentName)
      Stepper("Quantity: \(equipmentQuantity)", value: $equipmentQuantity, in: 1...100)
      Button("Add Equipment") { onMutation("add_equipment_requirement", ["name": .string(equipmentName), "quantity": .int(equipmentQuantity), "required": .bool(true), "visibility": .string("player_visible")]); equipmentName = "" }
        .disabled(equipmentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
  }

  private var templateSection: some View {
    Section("Reusable Template") {
      TextField("Template name", text: $templateName)
      Button("Save Current Plan as Template") { onMutation("save_plan_as_template", ["name": .string(templateName), "team_id": .string(event.team_id.uuidString), "season_id": .string(event.season_id.uuidString)]) }
        .disabled(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || plan == nil)
    }
  }

  @ViewBuilder private var publicationSection: some View {
    Section("Publish and Operation") {
      if let plan, capabilities.contains(.publishPracticePlan), plan.status != .active, plan.status != .completed {
        Button(plan.published_version == nil ? "Publish Plan" : "Publish Revised Version") { onMutation(plan.published_version == nil ? "publish_plan" : "republish_plan", [:]) }
          .disabled(validation?.valid != true)
      }
      if plan?.status == .published, capabilities.contains(.modifyActivePracticePlan), operation.status == .inProgress || operation.status == .ready {
        Button("Start Practice with Published Version") { onMutation("capture_started_snapshot", [:]) }
      }
    }
  }

  private var executionSection: some View {
    Section("Active Practice Plan") {
      if let current { LabeledContent("Current block", value: current.title) }
      if let next { LabeledContent("Next block", value: next.title) }
      ForEach(executions.filter { $0.parent_block_id != nil && $0.status == .active }) { Text("Active station: \($0.title)") }
      ForEach(executions.sorted { $0.sequence_index < $1.sequence_index }) { execution in
        HStack {
          VStack(alignment: .leading) { Text(execution.title); Text(execution.status.rawValue.capitalized).font(.caption) }
          Spacer()
          if capabilities.contains(.executePracticeBlocks) {
            if execution.status == .pending { Button("Start") { mutateExecution("start_block", execution) } }
            if execution.status == .active { Button("Complete") { mutateExecution("complete_block", execution) } }
            if execution.status == .pending || execution.status == .active { Button("Skip") { mutateExecution("skip_block", execution, reason: adjustmentReason.sdNilIfBlank ?? "Field adjustment") } }
            if execution.status == .completed || execution.status == .skipped { Button("Reopen") { mutateExecution("reopen_block", execution, reason: adjustmentReason.sdNilIfBlank ?? "Authorized correction") } }
          }
        }
      }
      TextField("Adjustment reason", text: $adjustmentReason)
      if capabilities.contains(.modifyActivePracticePlan) {
        Button("Add Emergency Block") { onMutation("add_active_block", ["title": .string("Emergency Adjustment"), "block_type": .string("custom"), "sequence_index": .int(executions.count), "start_offset_minutes": .int(validation?.total_duration_minutes ?? 0), "duration_minutes": .int(10), "visibility": .string("staff_only"), "reason": .string(adjustmentReason)]) }
          .disabled(adjustmentReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      if capabilities.contains(.completePracticePlan) { Button("Complete Practice") { onMutation("complete_practice_plan", [:]) }.disabled(executions.contains { $0.status == .active }) }
    }
  }

  private var completionSection: some View {
    Section("Completion Review") {
      LabeledContent("Completed blocks", value: "\(executions.filter { $0.status == .completed }.count)")
      LabeledContent("Skipped blocks", value: "\(executions.filter { $0.status == .skipped }.count)")
      LabeledContent("Adjusted blocks", value: "\(executions.filter { $0.status == .adjusted }.count)")
      DisclosureGroup("Completed Plan History") {
        ForEach(history) { snapshot in
          Text("\(snapshot.snapshot_type.capitalized) • Version \(snapshot.plan_version) • \(snapshot.created_at)")
            .font(.caption)
        }
      }
      Text("Attendance completion remains in the Practice Day participants section.")
      if capabilities.contains(.reopenPracticePlan) {
        TextField("Required reopen reason", text: $adjustmentReason)
        Button("Reopen Completed Practice") { onMutation("reopen_completed_practice", ["reason": .string(adjustmentReason)]) }
          .disabled(adjustmentReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
  }

  private func reorder(_ block: SDPracticePlanBlock, delta: Int) {
    var ordered = topBlocks
    guard let index = ordered.firstIndex(where: { $0.id == block.id }) else { return }
    let destination = index + delta
    guard ordered.indices.contains(destination), let plan else { return }
    ordered.swapAt(index, destination)
    let payload = ordered.enumerated().map { SDJSONValue.object(["id": .string($0.element.id.uuidString), "sequence_index": .int($0.offset)]) }
    onMutation("reorder_blocks", ["expected_version": .int(plan.version), "blocks": .array(payload)])
  }

  private func mutateExecution(_ action: String, _ execution: SDPracticeBlockExecution, reason: String? = nil) {
    var data: [String: SDJSONValue] = ["execution_id": .string(execution.id.uuidString), "expected_version": .int(execution.version)]
    if let reason { data["reason"] = .string(reason) }
    onMutation(action, data)
  }
}

private struct PracticeBlockEditSheet: View {
  @Environment(\.dismiss) private var dismiss
  let block: SDPracticePlanBlock
  let onSave: ([String: SDJSONValue]) -> Void
  @State private var title: String
  @State private var duration: Int
  @State private var location: String
  @State private var instructions: String
  @State private var coachingPoints: String
  @State private var visibility: String

  init(block: SDPracticePlanBlock, onSave: @escaping ([String: SDJSONValue]) -> Void) {
    self.block = block; self.onSave = onSave
    _title = State(initialValue: block.title); _duration = State(initialValue: block.duration_minutes)
    _location = State(initialValue: block.location_area ?? ""); _instructions = State(initialValue: block.instructions ?? "")
    _coachingPoints = State(initialValue: block.coaching_points ?? ""); _visibility = State(initialValue: block.visibility)
  }

  var body: some View {
    NavigationStack {
      Form {
        TextField("Block or station title", text: $title)
        Stepper("Duration: \(duration) minutes", value: $duration, in: block.block_type == .arrival ? 0...240 : 1...240)
        TextField("Location or field area", text: $location)
        TextField("Instructions", text: $instructions, axis: .vertical)
        TextField("Staff coaching points", text: $coachingPoints, axis: .vertical)
        Picker("Visibility", selection: $visibility) { Text("Staff Only").tag("staff_only"); Text("Team Visible").tag("team_visible"); Text("Player Visible").tag("player_visible") }
      }
      .navigationTitle(block.parent_block_id == nil ? "Edit Block" : "Edit Station")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            onSave(["block_id": .string(block.id.uuidString), "expected_version": .int(block.version), "title": .string(title), "duration_minutes": .int(duration), "location_area": .string(location), "instructions": .string(instructions), "coaching_points": .string(coachingPoints), "visibility": .string(visibility)])
            dismiss()
          }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }
}

private struct PracticeEquipmentEditSheet: View {
  @Environment(\.dismiss) private var dismiss
  let item: SDPracticeEquipmentRequirement
  let onSave: ([String: SDJSONValue]) -> Void
  @State private var name: String
  @State private var quantity: Int
  @State private var notes: String
  @State private var prepared: Bool

  init(item: SDPracticeEquipmentRequirement, onSave: @escaping ([String: SDJSONValue]) -> Void) {
    self.item = item; self.onSave = onSave
    _name = State(initialValue: item.name); _quantity = State(initialValue: item.quantity)
    _notes = State(initialValue: item.notes ?? ""); _prepared = State(initialValue: item.prepared)
  }

  var body: some View {
    NavigationStack {
      Form {
        TextField("Equipment", text: $name)
        Stepper("Quantity: \(quantity)", value: $quantity, in: 1...100)
        Toggle("Prepared", isOn: $prepared)
        TextField("Internal preparation notes", text: $notes, axis: .vertical)
      }
      .navigationTitle("Edit Equipment")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            onSave(["equipment_id": .string(item.id.uuidString), "expected_version": .int(item.version), "name": .string(name), "quantity": .int(quantity), "prepared": .bool(prepared), "notes": .string(notes)])
            dismiss()
          }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }
}
