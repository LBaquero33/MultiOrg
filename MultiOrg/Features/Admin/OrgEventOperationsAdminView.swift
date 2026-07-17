import SwiftUI

struct OrgEventOperationsAdminView: View {
  @EnvironmentObject private var appState: AppState
  @State private var events: [SDTeamEvent] = []
  @State private var summaries: [UUID: SDEventOperationSummary] = [:]
  @State private var selectedEvent: SDTeamEvent?
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
      Text("Inspect completion, unresolved attendance, and audit history. Day-of coaching remains in Coach Today.")
        .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
    } results: { _ in
      if isLoading && events.isEmpty {
        HPCard { HPLoadingState(text: "Loading event operations…") }
      } else if events.isEmpty {
        HPCard { HPEmptyState(title: "No event operations", message: "No canonical events are available in the review window.", systemImage: "checklist") }
      } else {
        ForEach(events) { event in
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
      for team in appState.authorizedCoachTeams {
        let ids = events.filter { $0.team_id == team.id }.map(\.id)
        if !ids.isEmpty {
          all += try await service.listEventOperations(organizationId: organizationId, teamId: team.id, eventIds: ids)
        }
      }
      summaries = Dictionary(uniqueKeysWithValues: all.map { ($0.event_id, $0) })
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
  @State private var correctionParticipantId: UUID?
  @State private var correctionStatus: SDEventAttendanceStatus = .present
  @State private var correctionReason = ""
  @State private var reopenReason = ""
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
}
