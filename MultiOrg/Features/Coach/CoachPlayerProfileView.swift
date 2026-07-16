import SwiftUI

/// Coach-facing player profile with Shiny-style top tabs.
struct CoachPlayerProfileView: View {
  @EnvironmentObject private var appState: AppState
  let player: Profile

  enum Tab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case calendar = "Calendar"
    case testing = "Testing"
    case program = "Program"
    case analysis = "Analysis"
    case developmentAI = "Development AI"
    var id: String { rawValue }
  }

  @State private var tab: Tab = .overview
  @State private var canManagePlayer = true

  var body: some View {
    content
      .background(DHDTheme.pageBackground)
      .toolbar {
#if os(macOS)
        ToolbarItem(placement: .automatic) {
          Picker("", selection: $tab) {
            ForEach(Tab.allCases) { t in
              Text(t.rawValue).tag(t)
            }
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 520)
        }
#else
        ToolbarItem(placement: .primaryAction) {
          Menu {
            ForEach(Tab.allCases) { section in
              Button {
                tab = section
              } label: {
                if tab == section {
                  Label(section.rawValue, systemImage: "checkmark")
                } else {
                  Text(section.rawValue)
                }
              }
            }
          } label: {
            Label(tab.rawValue, systemImage: "rectangle.grid.1x2")
          }
          .accessibilityLabel("Player sections")
          .accessibilityHint("Includes Player Development AI and Coach Copilot")
        }
#endif
      }
      .navigationTitle(player.displayName)
      #if !os(macOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .task(id: player.id) {
        canManagePlayer = await appState.canManagePlayerOnActiveTeam(player.id)
      }
  }

  @ViewBuilder
  private var content: some View {
    switch tab {
    case .overview:
      CoachPlayerOverviewView(player: player)
    case .calendar:
      CoachPlayerCalendarView(player: player)
    case .testing:
      CoachPlayerTestingCRUDView(player: player, canManagePlayer: canManagePlayer)
    case .program:
      CoachPlayerProgramAssignerView(player: player, canManagePlayer: canManagePlayer)
    case .analysis:
      CoachPlayerAnalysisView(player: player)
    case .developmentAI:
      PlayerDevelopmentAIWorkspaceView(player: player)
    }
  }
}

private struct CoachPlayerProgramAssignerView: View {
  @EnvironmentObject private var appState: AppState
  let player: Profile
  let canManagePlayer: Bool

  @State private var activeAssignments: [SDProgramAssignment] = []
  @State private var activeTemplates: [UUID: SDProgramTemplate] = [:]
  @State private var coachTemplates: [SDProgramTemplate] = []
  @State private var selectedTemplateId: UUID?
  @State private var startDate = Date()
  @State private var notes = ""
  @State private var isWorking = false
  @State private var errorText: String?
  @State private var toastText: String?
  @State private var parentEmail = ""
  @State private var parentRelationship = ""
  @State private var parentInvites: [SDParentInvite] = []
  @State private var parentLinks: [SDParentChildLink] = []
  @State private var playerAccess: SDAdminPlayerAccess?
  @State private var accessActionInFlight = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        DHDHeaderCard {
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text("Program assignment")
                .font(.title3.weight(.semibold))
              Text(player.displayName)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.85))
            }
            Spacer()
            if isWorking { ProgressView().tint(.white) }
          }
          .foregroundStyle(.white)
        }

        DHDCard {
          VStack(alignment: .leading, spacing: 12) {
            if !canManagePlayer {
              Label("Your organization limits program changes to players on your assigned team.", systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
            }
            DHDSectionHeader("Active programs") {
              if !activeAssignments.isEmpty {
                DHDStatusBadge(text: "\(activeAssignments.count) active", color: .green)
              }
            }

            if activeAssignments.isEmpty {
              Text("No active programs assigned.")
                .foregroundStyle(DHDTheme.textSecondary)
            } else {
              ForEach(activeAssignments) { assignment in
                if let template = activeTemplates[assignment.template_id] {
                  VStack(alignment: .leading, spacing: 8) {
                    HStack {
                      Label(template.kind.title, systemImage: template.kind.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DHDTheme.accent)
                      Spacer()
                      Text("Starts \(assignment.start_date)")
                        .font(.caption)
                        .foregroundStyle(DHDTheme.textSecondary)
                    }
                    DHDFormRow("Template") { Text(template.name) }
                    DHDFormRow("Days/week") { Text("\(template.lift_weekdays.count)") }
                    DHDFormRow("Weekdays") { Text(weekdayLabel(template.lift_weekdays)) }
                    Button(role: .destructive) {
                      Task { await endProgram(assignment) }
                    } label: {
                      Label("End \(template.kind.title) program", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(isWorking || !canManagePlayer)
                  }
                  if assignment.id != activeAssignments.last?.id {
                    Divider().overlay(DHDTheme.separator.opacity(0.35))
                  }
                }
              }
            }
          }
        }

        if appState.canAdminActiveOrg {
          DHDCard {
            VStack(alignment: .leading, spacing: 12) {
              DHDSectionHeader("Player app access") {
                DHDStatusBadge(
                  text: playerAccess?.is_active == true ? "Access granted" : "Payment required",
                  color: playerAccess?.is_active == true ? .green : .orange
                )
              }

              Text("This override applies only to \(player.displayName). It does not change access for anyone else in the organization.")
                .font(.footnote)
                .foregroundStyle(DHDTheme.textSecondary)

              HStack(spacing: 10) {
                Button {
                  Task { await setPlayerAccess(true) }
                } label: {
                  Label("Grant access", systemImage: "lock.open.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(accessActionInFlight || playerAccess?.is_active == true)

                Button {
                  Task { await setPlayerAccess(false) }
                } label: {
                  Label("Require payment", systemImage: "lock.fill")
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(accessActionInFlight || playerAccess?.is_active == false)

                if accessActionInFlight { ProgressView().controlSize(.small) }
                Spacer()
              }

              if let updated = playerAccess?.updated_at, !updated.isEmpty {
                Text("Last changed \(updated)")
                  .font(.caption2)
                  .foregroundStyle(DHDTheme.textSecondary)
              }
            }
          }
        }

        DHDCard {
          VStack(alignment: .leading, spacing: 12) {
            DHDSectionHeader("Assign new program") {
              EmptyView()
            }

            if coachTemplates.isEmpty {
              Text("No templates yet. Create one in Program Templates.")
                .foregroundStyle(DHDTheme.textSecondary)
            } else {
              Picker("Template", selection: $selectedTemplateId) {
                Text("Select…").tag(UUID?.none)
                ForEach(coachTemplates) { t in
                  Text(t.name).tag(UUID?.some(t.id))
                }
              }

              DatePicker("Start date", selection: $startDate, displayedComponents: .date)

              TextField("Notes (optional)", text: $notes)
                .textFieldStyle(.roundedBorder)

              Button {
                Task { await assignProgram() }
              } label: {
                Label("Assign", systemImage: "checkmark.circle")
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.borderedProminent)
              .disabled(isWorking || selectedTemplateId == nil || !canManagePlayer)
            }
          }
        }

        DHDCard {
          VStack(alignment: .leading, spacing: 12) {
            DHDSectionHeader("Parents") { EmptyView() }

            Text("Invite a parent/guardian to view this player (view-only) and request bookings/payments.")
              .font(.caption)
              .foregroundStyle(DHDTheme.textSecondary)

            HStack(spacing: 10) {
              TextField("Parent email", text: $parentEmail)
                .textFieldStyle(.roundedBorder)
              TextField("Relationship (optional)", text: $parentRelationship)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
              Button {
                Task { await sendParentInvite() }
              } label: {
                Label("Invite", systemImage: "paperplane")
              }
              .buttonStyle(.borderedProminent)
              .disabled(isWorking || !canManagePlayer || parentEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !parentLinks.isEmpty {
              Divider().overlay(DHDTheme.separator.opacity(0.35))
              Text("Linked parents")
                .font(.headline)
              ForEach(parentLinks, id: \.id) { link in
                Text("Parent \(link.parent_id.uuidString.prefix(6).uppercased()) • \(link.relationship ?? "—")")
                  .font(.caption)
                  .foregroundStyle(DHDTheme.textSecondary)
              }
            }

            if !parentInvites.isEmpty {
              Divider().overlay(DHDTheme.separator.opacity(0.35))
              Text("Invites")
                .font(.headline)
              ForEach(parentInvites) { inv in
                HStack {
                  VStack(alignment: .leading, spacing: 2) {
                    Text(inv.email_norm).font(.subheadline)
                    Text(inv.accepted_at == nil ? "Pending" : "Accepted")
                      .font(.caption)
                      .foregroundStyle(DHDTheme.textSecondary)
                  }
                  Spacer()
                }
              }
            }
          }
        }

      }
      .padding(DHDTheme.pagePadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(maxHeight: .infinity, alignment: .topLeading)
    }
    .background(DHDTheme.pageBackground)
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .dhdToast($toastText)
    .task { await reload() }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      coachTemplates = try await supabase.listMyCoachTemplates()
      activeAssignments = try await supabase.fetchActiveAssignments(playerId: player.id)
      var templates: [UUID: SDProgramTemplate] = [:]
      for assignment in activeAssignments {
        templates[assignment.template_id] = try await supabase.fetchTemplate(id: assignment.template_id)
      }
      activeTemplates = templates
      parentInvites = try await supabase.coachListParentInvites(childId: player.id)
      parentLinks = try await supabase.coachListParentLinks(childId: player.id)
      if appState.canAdminActiveOrg, let orgId = appState.activeOrgId {
        playerAccess = try await supabase.adminFetchPlayerAccess(orgId: orgId, playerId: player.id)
      }
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func setPlayerAccess(_ isActive: Bool) async {
    guard let supabase = appState.supabase, let orgId = appState.activeOrgId else {
      errorText = "Choose an organization before changing player access."
      return
    }
    accessActionInFlight = true
    defer { accessActionInFlight = false }
    do {
      playerAccess = try await supabase.adminSetPlayerAccess(
        orgId: orgId,
        playerId: player.id,
        isActive: isActive
      )
      toastText = isActive ? "Access granted to \(player.displayName)." : "Payment is now required for \(player.displayName)."
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
        templateId: templateId,
        playerId: player.id,
        startDateISO: dateISO,
        notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
        orgId: appState.activeOrgId
      )
      toastText = "Assigned"
      await reload()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func endProgram(_ assignment: SDProgramAssignment) async {
    guard let supabase = appState.supabase else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      try await supabase.endAssignment(assignmentId: assignment.id)
      toastText = "Ended"
      await reload()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func sendParentInvite() async {
    guard let supabase = appState.supabase, let orgId = appState.activeOrgId else {
      errorText = "Choose an organization before inviting a parent."
      return
    }
    isWorking = true
    defer { isWorking = false }
    do {
      let rel = parentRelationship.trimmingCharacters(in: .whitespacesAndNewlines)
      _ = try await supabase.coachCreateParentInvite(
        orgId: orgId,
        childId: player.id,
        parentEmail: parentEmail,
        relationship: rel.isEmpty ? nil : rel
      )
      toastText = "Invited"
      parentEmail = ""
      parentRelationship = ""
      await reload()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func weekdayLabel(_ days: [Int]) -> String {
    let map: [Int: String] = [1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 7: "Sun"]
    return days.compactMap { map[$0] }.joined(separator: ", ")
  }
}
