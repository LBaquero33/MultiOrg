import SwiftUI

struct OrgEventOperationsAdminView: View {
  @EnvironmentObject private var appState: AppState
  @State private var events: [SDTeamEvent] = []
  @State private var summaries: [UUID: SDEventOperationSummary] = [:]
  @State private var practicePlans: [UUID: SDPracticePlanSummary] = [:]
  @State private var gamePlans: [UUID: SDGamePlanSummary] = [:]
  @State private var selectedEvent: SDTeamEvent?
  @State private var selectedTeamId: UUID?
  @State private var isLoading = false
  @State private var errorText: String?

  var body: some View {
    HPListScreenLayout {
      HPWorkspaceHeader(
        "Event Operations",
        orgLabel: appState.selectedSeason?.name ?? "Season",
        context: "Administrative inspection and correction"
      )
    } controls: {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        Text("Inspect completion, unresolved attendance, and audit history. Day-of coaching remains in Coach Today.")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        Picker("Team", selection: $selectedTeamId) {
          Text("All authorized teams").tag(UUID?.none)
          ForEach(appState.authorizedCoachTeams) { team in Text(team.name).tag(Optional(team.id)) }
        }
        .pickerStyle(.menu)
      }
    } results: { _ in
      if isLoading && filteredEvents.isEmpty {
        HPCard { HPLoadingState(text: "Loading event operations…") }
      } else if filteredEvents.isEmpty {
        HPCard { HPEmptyState(title: "No event operations", message: "No canonical events are available in the review window.", systemImage: "checklist") }
      } else {
        ForEach(filteredEvents) { event in
          HPCard {
            Button { selectedEvent = event } label: {
              HStack(alignment: .top, spacing: HP.Space.sm) {
                Image(systemName: event.event_type.systemImage).foregroundStyle(HP.Color.accent)
                VStack(alignment: .leading, spacing: 3) {
                  Text(event.title).font(HP.Font.headline).foregroundStyle(HP.Color.text)
                  Text("\(teamName(event.team_id)) • \(event.startDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
                  if let summary = summaries[event.id] {
                    Text("\(summary.status.label) • \(summary.unrecorded_attendance) attendance unresolved • \(summary.checklist_completed)/\(summary.checklist_total) checklist")
                      .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
                  } else {
                    Text("Not initialized").font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
                  }
                  if event.event_type == .practice {
                    Text("Practice plan: \(practicePlans[event.id]?.status.label ?? "No Plan")")
                      .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
                  }
                  if event.event_type == .game {
                    let gamePlan = gamePlans[event.id]
                    Text("Game plan: \(gamePlan?.status.label ?? "No Plan") • \(gamePlan?.lineup_mode.label ?? "Lineup not started")")
                      .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
                  }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(HP.Color.textMuted)
              }
              .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .navigationTitle("Event Operations")
    .task { await reload() }
    .refreshable { await reload() }
    .sheet(item: $selectedEvent) { event in
      NavigationStack {
        OrgEventOperationInspectionView(event: event, teamName: teamName(event.team_id))
          .environmentObject(appState)
      }
    }
    .alert("Event Operations", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
  }

  private func teamName(_ id: UUID) -> String {
    appState.authorizedCoachTeams.first(where: { $0.id == id })?.name ?? "Team"
  }

  private var filteredEvents: [SDTeamEvent] {
    guard let selectedTeamId else { return events }
    return events.filter { $0.team_id == selectedTeamId }
  }

  private func reload() async {
    guard let service = appState.supabase, let organizationId = appState.activeOrgId else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let start = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
      let end = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
      events = try await service.listTeamEvents(
        organizationId: organizationId,
        seasonId: appState.selectedSeason?.id,
        teamId: nil,
        rangeStart: start,
        rangeEnd: end
      ).filter { $0.status != .draft }
      var all: [SDEventOperationSummary] = []
      var plans: [SDPracticePlanSummary] = []
      var games: [SDGamePlanSummary] = []
      for team in appState.authorizedCoachTeams {
        let ids = events.filter { $0.team_id == team.id }.map(\.id)
        if !ids.isEmpty {
          all += try await service.listEventOperations(organizationId: organizationId, teamId: team.id, eventIds: ids)
        }
        plans += (try? await service.practicePlanSummaries(
          organizationId: organizationId,
          seasonId: team.season_id,
          teamId: team.id
        )) ?? []
        games += (try? await service.gamePlanSummaries(
          organizationId: organizationId,
          seasonId: team.season_id,
          teamId: team.id
        )) ?? []
      }
      summaries = Dictionary(uniqueKeysWithValues: all.map { ($0.event_id, $0) })
      practicePlans = Dictionary(uniqueKeysWithValues: plans.map { ($0.event_id, $0) })
      gamePlans = Dictionary(uniqueKeysWithValues: games.map { ($0.event_id, $0) })
    } catch {
      errorText = "Administrative operation state could not be loaded."
    }
  }
}

private struct OrgEventOperationInspectionView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  let event: SDTeamEvent
  let teamName: String
  @State private var detail: SDEventOperationDetailResponse?
  @State private var audit: [SDEventOperationAuditEntry] = []
  @State private var practicePlan: SDPracticePlanDetailResponse?
  @State private var gamePlan: SDGamePlanDetailResponse?
  @State private var gameHistory: [SDGamePlanSnapshot] = []
  @State private var gameRuleProfiles: [SDGameRuleProfile] = []
  @State private var practiceTemplates: [SDPracticePlanTemplate] = []
  @State private var organizationTemplateName = ""
  @State private var selectedTemplateId: UUID?
  @State private var templateRename = ""
  @State private var correctionParticipantId: UUID?
  @State private var correctionStatus: SDEventAttendanceStatus = .present
  @State private var correctionReason = ""
  @State private var reopenReason = ""
  @State private var showGameResultEditor = false
  @State private var showGameRuleEditor = false
  @State private var errorText: String?

  var body: some View {
    Form {
      Section("Mission") {
        Text(event.title).font(HP.Font.headline)
        Text("\(teamName) • \(event.startDate.formatted(date: .abbreviated, time: .shortened))")
        Text("Status: \(detail?.operation?.status.label ?? "Not initialized")")
      }
      if let operation = detail?.operation {
        Section("Attendance inspection") {
          Text("\(unresolvedAttendance) expected player record(s) remain unresolved.")
          Picker("Participant", selection: $correctionParticipantId) {
            Text("Select participant").tag(UUID?.none)
            ForEach(playerParticipants) { participant in
              Text(participantName(participant)).tag(Optional(participant.id))
            }
          }
          Picker("Correct to", selection: $correctionStatus) {
            ForEach(SDEventAttendanceStatus.allCases) { Text($0.label).tag($0) }
          }
          TextField("Required correction reason", text: $correctionReason, axis: .vertical)
          Button("Apply Audited Correction") { applyCorrection() }
            .disabled(correctionParticipantId == nil || correctionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        if operation.status == .completed {
          Section("Reopen") {
            TextField("Required reopen reason", text: $reopenReason, axis: .vertical)
            Button("Reopen Operation") { reopen(operation) }
              .disabled(reopenReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
      }
      if event.event_type == .practice {
        Section("Practice plan inspection") {
          Text("Plan status: \(practicePlan?.plan?.status.label ?? "No Plan")")
          Text("Readiness: \(practicePlan?.validation?.blocking_errors.count ?? 0) blocking, \(practicePlan?.validation?.readiness_warnings.count ?? 0) warning(s)")
          Text("\(practicePlan?.blocks.count ?? 0) blocks • \(practicePlan?.groups.count ?? 0) groups • \(practicePlan?.equipment.count ?? 0) equipment requirements")
          if practicePlan?.plan?.status == .completed {
            TextField("Required practice reopen reason", text: $reopenReason, axis: .vertical)
            Button("Reopen Completed Practice Plan") { reopenPracticePlan() }
              .disabled(reopenReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
        Section("Template inventory") {
          ForEach(practiceTemplates) { template in
            HStack {
              VStack(alignment: .leading) { Text(template.name); Text(template.active ? "Active" : "Archived").font(.caption) }
              Spacer()
              Button(template.active ? "Archive" : "Restore") {
                mutateTemplate(template.active ? "archive_template" : "restore_template", template: template)
              }
            }
          }
          Picker("Template to edit", selection: $selectedTemplateId) {
            Text("Select template").tag(UUID?.none)
            ForEach(practiceTemplates) { Text($0.name).tag(Optional($0.id)) }
          }
          TextField("New template name", text: $templateRename)
          HStack {
            Button("Rename Template") { mutateSelectedTemplate("update_template") }
            Button("Duplicate Template") { mutateSelectedTemplate("duplicate_template") }
          }
          .disabled(selectedTemplateId == nil || templateRename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          TextField("Organization template name", text: $organizationTemplateName)
          Button("Create Organization Template") {
            guard let service = appState.supabase else { return }
            Task {
              do {
                _ = try await service.mutatePracticePlan(
                  action: "create_template",
                  organizationId: event.organization_id,
                  eventId: event.id,
                  data: ["name": .string(organizationTemplateName), "snapshot": .object([:]), "objectives": .array([])]
                )
                organizationTemplateName = ""; await reload()
              } catch { errorText = "The organization template could not be created." }
            }
          }.disabled(organizationTemplateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      if event.event_type == .game {
        Section("Game plan inspection") {
          Text("Plan status: \(gamePlan?.plan?.status.label ?? "No Plan")")
          Text("Lineup mode: \(gamePlan?.plan?.lineup_mode.label ?? "Not selected")")
          Text("Readiness: \(gamePlan?.validation?.blocking_errors.count ?? 0) blocking, \(gamePlan?.validation?.readiness_warnings.count ?? 0) warning(s)")
          Text("\(gamePlan?.batting_order?.count ?? 0) hitters • \(gamePlan?.validation?.eh_count ?? 0) EH • \(gamePlan?.defense?.count ?? 0) defensive assignments")
          if let result = gamePlan?.result {
            Text(result.team_score.flatMap { team in result.opponent_score.map { "Result: \(team)–\($0) • \(result.outcome.capitalized)" } } ?? "Result recorded without confirmed score")
            Button("Correct Result with Reason") { showGameResultEditor = true }
          }
          if gamePlan?.plan?.status == .completed {
            TextField("Required game reopen reason", text: $reopenReason, axis: .vertical)
            Button("Reopen Completed Game Plan") { reopenGamePlan() }
              .disabled(reopenReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
        Section("Rule profile inspection") {
          if gameRuleProfiles.isEmpty { Text("No scoped rule profiles are available.") }
          ForEach(gameRuleProfiles) { profile in
            VStack(alignment: .leading, spacing: 2) {
              Text(profile.name)
              Text("\(ruleScope(profile)) • \(profile.innings.map { "\($0) innings" } ?? "Innings advisory") • \(profile.maximum_eh.map { "Up to \($0) EH" } ?? "No EH cap")")
                .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            }
          }
          Button("Create Scoped Rule Profile") { showGameRuleEditor = true }
        }
        Section("Game-plan history") {
          if gameHistory.isEmpty { Text("No preserved revisions are available.") }
          ForEach(gameHistory.prefix(12)) { snapshot in
            VStack(alignment: .leading, spacing: 2) {
              Text("\(snapshot.snapshot_type.capitalized) • Version \(snapshot.plan_version)")
              Text(snapshot.created_at).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            }
          }
        }
      }
      Section("Audit history") {
        if audit.isEmpty { Text("No audit entries available.") }
        ForEach(audit) { entry in
          VStack(alignment: .leading, spacing: 2) {
            Text(entry.action.replacingOccurrences(of: "_", with: " ").capitalized)
              .font(HP.Font.callout.weight(.semibold))
            if let reason = entry.reason?.sdNilIfBlank { Text(reason).font(HP.Font.caption) }
            Text(entry.created_at).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
          }
        }
      }
    }
    .navigationTitle("Operation Review")
    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
    .task { await reload() }
    .sheet(isPresented: $showGameResultEditor) {
      GameResultEditorSheet(result: gamePlan?.result) { data in mutateGame("record_game_result", data: data) }
    }
    .sheet(isPresented: $showGameRuleEditor) {
      GameRuleProfileEditorSheet(event: event) { data in mutateGame("create_rule_profile", data: data) }
    }
    .alert("Administrative Correction", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
  }

  private var playerParticipants: [SDEventOperationParticipant] {
    detail?.participants?.filter { $0.participant_type == "player" && $0.expected } ?? []
  }

  private var unresolvedAttendance: Int {
    playerParticipants.filter { $0.attendance_status == .notRecorded }.count
  }

  private func participantName(_ participant: SDEventOperationParticipant) -> String {
    appState.teamOperationsContext?.people.first(where: { $0.id == participant.user_id })?.displayName
      ?? "Player \(participant.user_id.uuidString.prefix(6))"
  }

  private func reload() async {
    guard let service = appState.supabase else { return }
    do {
      detail = try await service.eventOperation(organizationId: event.organization_id, eventId: event.id)
      if event.event_type == .practice {
        practicePlan = try? await service.practicePlan(organizationId: event.organization_id, eventId: event.id)
        practiceTemplates = (try? await service.practiceTemplates(
          organizationId: event.organization_id,
          eventId: event.id,
          teamId: event.team_id,
          includeArchived: true
        )) ?? []
      }
      if event.event_type == .game {
        gamePlan = try? await service.gamePlan(organizationId: event.organization_id, eventId: event.id)
        gameHistory = (try? await service.gamePlanHistory(organizationId: event.organization_id, eventId: event.id)) ?? []
        gameRuleProfiles = (try? await service.gameRuleProfiles(
          organizationId: event.organization_id,
          eventId: event.id,
          teamId: event.team_id,
          seasonId: event.season_id
        )) ?? []
      }
      if detail?.operation != nil {
        audit = try await service.eventOperationAuditHistory(organizationId: event.organization_id, eventId: event.id).audit
      }
    } catch { errorText = "Operation inspection could not be refreshed." }
  }

  private func applyCorrection() {
    guard let service = appState.supabase,
          let participant = playerParticipants.first(where: { $0.id == correctionParticipantId }) else { return }
    Task {
      do {
        _ = try await service.updateEventAttendance(
          organizationId: event.organization_id,
          eventId: event.id,
          participantId: participant.id,
          participantVersion: participant.version,
          status: correctionStatus,
          correctionReason: correctionReason,
          requestId: UUID()
        )
        correctionReason = ""
        await reload()
      } catch { errorText = "The correction was rejected because the record changed or authorization failed." }
    }
  }

  private func reopen(_ operation: SDEventOperation) {
    guard let service = appState.supabase else { return }
    Task {
      do {
        _ = try await service.transitionEventOperation(
          organizationId: event.organization_id,
          eventId: event.id,
          expectedVersion: operation.version,
          status: .ready,
          reason: reopenReason,
          requestId: UUID()
        )
        reopenReason = ""
        await reload()
      } catch { errorText = "The operation could not be reopened. Refresh and verify its current version." }
    }
  }

  private func reopenPracticePlan() {
    guard let service = appState.supabase else { return }
    Task {
      do {
        _ = try await service.mutatePracticePlan(
          action: "reopen_completed_practice",
          organizationId: event.organization_id,
          eventId: event.id,
          data: ["reason": .string(reopenReason)]
        )
        reopenReason = ""
        await reload()
      } catch { errorText = "The completed practice could not be reopened. Refresh and verify operation state." }
    }
  }

  private func reopenGamePlan() {
    guard let service = appState.supabase else { return }
    Task {
      do {
        _ = try await service.mutateGamePlan(
          action: "reopen_completed_game",
          organizationId: event.organization_id,
          eventId: event.id,
          data: ["reason": .string(reopenReason)]
        )
        reopenReason = ""
        await reload()
      } catch { errorText = "The completed game could not be reopened. Reopen the event operation first, then refresh." }
    }
  }

  private func mutateGame(_ action: String, data: [String: SDJSONValue]) {
    guard let service = appState.supabase else { return }
    Task {
      do {
        _ = try await service.mutateGamePlan(
          action: action,
          organizationId: event.organization_id,
          eventId: event.id,
          data: data
        )
        await reload()
      } catch { errorText = "The game-plan correction was rejected. Refresh and verify authorization and current state." }
    }
  }

  private func ruleScope(_ profile: SDGameRuleProfile) -> String {
    if profile.event_id != nil { return "Game" }
    if profile.tournament_event_id != nil { return "Tournament" }
    if profile.team_id != nil { return "Team" }
    if profile.season_id != nil { return "Season" }
    return "Organization"
  }

  private func mutateTemplate(_ action: String, template: SDPracticePlanTemplate) {
    guard let service = appState.supabase else { return }
    Task {
      do {
        _ = try await service.mutatePracticePlan(
          action: action,
          organizationId: event.organization_id,
          eventId: event.id,
          data: ["template_id": .string(template.id.uuidString), "expected_version": .int(template.version)]
        )
        await reload()
      } catch { errorText = "The template changed or authorization failed. Refresh and try again." }
    }
  }

  private func mutateSelectedTemplate(_ action: String) {
    guard let service = appState.supabase,
          let template = practiceTemplates.first(where: { $0.id == selectedTemplateId }) else { return }
    Task {
      do {
        _ = try await service.mutatePracticePlan(
          action: action,
          organizationId: event.organization_id,
          eventId: event.id,
          data: [
            "template_id": .string(template.id.uuidString),
            "expected_version": .int(template.version),
            "name": .string(templateRename),
            "description": .string(template.description ?? ""),
            "team_id": template.team_id.map { .string($0.uuidString) } ?? .null,
            "season_id": template.season_id.map { .string($0.uuidString) } ?? .null,
          ]
        )
        templateRename = ""; await reload()
      } catch { errorText = "The template could not be updated. Refresh and verify its current version." }
    }
  }
}
