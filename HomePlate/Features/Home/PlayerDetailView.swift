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
    HPDetailScreenLayout {
      HPCard {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: HP.Space.md) {
            playerIdentity
            Spacer(minLength: HP.Space.sm)
            HPStatusBadge(text: "Player", kind: .info)
          }
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            playerIdentity
            HPStatusBadge(text: "Player", kind: .info)
          }
        }
      }
    } metrics: {
      HPMetricCard(
        title: "Program",
        value: activeTemplate?.name ?? "None",
        context: activeAssignment == nil ? "No active assignment" : "Active assignment"
      )
      HPMetricCard(
        title: "Templates",
        value: "\(coachTemplates.count)",
        context: "Available to assign"
      )
    } details: {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.md) {
          HPSectionHeader("Program") {
            if isWorking {
              HPProgressIndicator(style: .spinner)
                .accessibilityLabel("Updating player program")
            }
          }

          if let a = activeAssignment, let t = activeTemplate {
            VStack(alignment: .leading, spacing: 6) {
              Text("Active: \(t.name)")
                .font(HP.Font.headline)
                .foregroundStyle(HP.Color.text)
                .fixedSize(horizontal: false, vertical: true)
              Text("Start: \(a.start_date)")
                .font(HP.Font.caption)
                .foregroundStyle(HP.Color.textMuted)
            }
            HPButton(
              title: "End current program",
              variant: .destructive,
              size: .md
            ) {
              Task { await endProgram() }
            }
            .disabled(isWorking)
          } else {
            Text("No active program assigned.")
              .font(HP.Font.callout)
              .foregroundStyle(HP.Color.textMuted)
          }

          Divider().overlay(HP.Color.border)

          HPSectionHeader("Assign program")
          if coachTemplates.isEmpty {
            Text("No templates yet. Create one in Coach → Programs.")
              .font(HP.Font.callout)
              .foregroundStyle(HP.Color.textMuted)
              .fixedSize(horizontal: false, vertical: true)
          } else {
            Picker("Template", selection: $selectedTemplateId) {
              Text("Select…").tag(UUID?.none)
              ForEach(coachTemplates) { t in
                Text(t.name).tag(UUID?.some(t.id))
              }
            }
            .pickerStyle(.menu)
            .tint(HP.Color.accent)
            DatePicker("Start date", selection: $startDate, displayedComponents: .date)
              .tint(HP.Color.accent)
            HPFormField(
              label: "Notes (optional)",
              text: $notes,
              placeholder: "Add assignment notes"
            )
          }
        }
      }
    } related: { _ in
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.xs) {
            HPSectionHeader("View (read-only)")
            NavigationLink {
              CoachPlayerDailyLogsView(player: player)
            } label: {
              navigationRow("Daily logs", systemImage: "checklist")
            }
            .buttonStyle(.plain)
            NavigationLink {
              CoachPlayerTestingEntriesView(player: player)
            } label: {
              navigationRow("Testing entries", systemImage: "list.bullet.clipboard")
            }
            .buttonStyle(.plain)
            NavigationLink {
              CoachPlayerBPSessionsView(player: player)
            } label: {
              navigationRow("BP sessions", systemImage: "baseball.diamond.bases")
            }
            .buttonStyle(.plain)
          }
        }

        HPCard(style: .flat) {
          Text("Coach view is read-only for player logs; assigning programs happens here.")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    } primaryAction: {
      if !coachTemplates.isEmpty {
        HPCard {
          HPButton(
            title: "Assign program",
            systemImage: "plus.circle",
            variant: .primary,
            size: .lg,
            isLoading: isWorking,
            fullWidth: true
          ) {
            Task { await assignProgram() }
          }
          .disabled(isWorking || selectedTemplateId == nil)
        }
      }
    }
    .navigationTitle(player.displayName)
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil }))
    {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorText ?? "")
    }
    .task {
      await reload()
    }
  }

  private var playerIdentity: some View {
    HStack(spacing: HP.Space.md) {
      HPAvatar(name: player.displayName, size: .lg)
      VStack(alignment: .leading, spacing: 2) {
        Text(player.displayName)
          .font(HP.Font.title)
          .tracking(HP.Font.titleTracking)
          .foregroundStyle(HP.Color.text)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)
        Text(player.id.uuidString)
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .textSelection(.enabled)
      }
    }
  }

  private func navigationRow(_ title: String, systemImage: String) -> some View {
    HStack(spacing: HP.Space.sm) {
      Image(systemName: systemImage)
        .foregroundStyle(HP.Color.accent)
        .accessibilityHidden(true)
      Text(title)
        .font(HP.Font.callout)
        .foregroundStyle(HP.Color.text)
      Spacer(minLength: HP.Space.sm)
      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(HP.Color.textMuted)
        .accessibilityHidden(true)
    }
    .frame(minHeight: 44)
    .contentShape(Rectangle())
    .accessibilityLabel(title)
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
      _ = try await supabase.assignProgram(
        templateId: templateId, playerId: player.id, startDateISO: dateISO,
        notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
        orgId: appState.activeOrgId)
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
