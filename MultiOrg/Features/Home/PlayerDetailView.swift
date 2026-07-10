import SwiftUI

struct PlayerDetailView: View {
  @EnvironmentObject private var appState: AppState
  let player: Profile

  @State private var activeAssignment: SDProgramAssignment?
  @State private var activeTemplate: SDProgramTemplate?
  @State private var coachTemplates: [SDProgramTemplate] = []
  @State private var selectedTemplateId: UUID?
  @State private var startDate = Date()
  @State private var notes = ""
  @State private var isWorking = false
  @State private var errorText: String?

  var body: some View {
    List {
      Section("Player") {
        Text(player.displayName)
        Text(player.id.uuidString)
          .font(.caption)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }

      Section("Program") {
        if let a = activeAssignment, let t = activeTemplate {
          VStack(alignment: .leading, spacing: 6) {
            Text("Active: \(t.name)").font(.headline)
            Text("Start: \(a.start_date)").font(.caption).foregroundStyle(.secondary)
          }
          Button("End current program", role: .destructive) {
            Task { await endProgram() }
          }
          .disabled(isWorking)
        } else {
          Text("No active program assigned.")
            .foregroundStyle(.secondary)
        }

        Divider()

        Text("Assign program").font(.headline)
        if coachTemplates.isEmpty {
          Text("No templates yet. Create one in Coach → Programs.")
            .foregroundStyle(.secondary)
        } else {
          Picker("Template", selection: $selectedTemplateId) {
            Text("Select…").tag(UUID?.none)
            ForEach(coachTemplates) { t in
              Text(t.name).tag(UUID?.some(t.id))
            }
          }
          DatePicker("Start date", selection: $startDate, displayedComponents: .date)
          TextField("Notes (optional)", text: $notes)
          Button {
            Task { await assignProgram() }
          } label: {
            if isWorking { ProgressView() } else { Text("Assign") }
          }
          .disabled(isWorking || selectedTemplateId == nil)
        }
      }

      Section("View (read-only)") {
        NavigationLink("Daily logs") { CoachPlayerDailyLogsView(player: player) }
        NavigationLink("Testing entries") { CoachPlayerTestingEntriesView(player: player) }
        NavigationLink("BP sessions") { CoachPlayerBPSessionsView(player: player) }
      }
      Section("Next") {
        Text("Coach view is read-only for player logs; assigning programs happens here.")
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle(player.displayName)
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorText ?? "")
    }
    .task {
      await reload()
    }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      coachTemplates = try await supabase.listMyCoachTemplates()
      activeAssignment = try await supabase.fetchActiveAssignment(playerId: player.id)
      if let activeAssignment {
        activeTemplate = try await supabase.fetchTemplate(id: activeAssignment.template_id)
      } else {
        activeTemplate = nil
      }
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func assignProgram() async {
    guard let supabase = appState.supabase else { return }
    guard let templateId = selectedTemplateId else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      let dateISO = DateUtils.toISODate(startDate)
      _ = try await supabase.assignProgram(templateId: templateId, playerId: player.id, startDateISO: dateISO, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes, orgId: appState.activeOrgId)
      await reload()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func endProgram() async {
    guard let supabase = appState.supabase else { return }
    guard let a = activeAssignment else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      try await supabase.endAssignment(assignmentId: a.id)
      await reload()
    } catch {
      errorText = error.localizedDescription
    }
  }
}
