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
