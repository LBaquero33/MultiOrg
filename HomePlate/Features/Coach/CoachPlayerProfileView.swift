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

    static func visible(playerDevelopmentAIEnabled: Bool) -> [Tab] {
      allCases.filter { playerDevelopmentAIEnabled || $0 != .developmentAI }
    }
  }

  @State private var tab: Tab = .overview
  @State private var canManagePlayer = true

  var body: some View {
    content
      .background(HP.Color.bg)
      .toolbar {
#if os(macOS)
        ToolbarItem(placement: .automatic) {
          ViewThatFits(in: .horizontal) {
            Picker("Player sections", selection: $tab) {
              ForEach(Tab.visible(playerDevelopmentAIEnabled: appState.isPlayerDevelopmentCopilotEnabled)) { section in
                Text(section.rawValue).tag(section)
              }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize(horizontal: true, vertical: false)

            Picker("Player sections", selection: $tab) {
              ForEach(Tab.visible(playerDevelopmentAIEnabled: appState.isPlayerDevelopmentCopilotEnabled)) { section in
                Text(section.rawValue).tag(section)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
          }
          .accessibilityLabel("Player sections")
        }
#else
        ToolbarItem(placement: .primaryAction) {
          Menu {
            ForEach(Tab.visible(playerDevelopmentAIEnabled: appState.isPlayerDevelopmentCopilotEnabled)) { section in
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
          .accessibilityHint(
            appState.isPlayerDevelopmentCopilotEnabled
              ? "Includes Player Development AI and Coach Copilot"
              : "Choose a player section"
          )
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
      .onChange(of: appState.isPlayerDevelopmentCopilotEnabled) { _, enabled in
        if !enabled, tab == .developmentAI { tab = .overview }
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
      if appState.isPlayerDevelopmentCopilotEnabled {
        PlayerDevelopmentAIWorkspaceView(player: player)
      } else {
        CoachPlayerOverviewView(player: player)
      }
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
    HPDetailScreenLayout {
      HPWorkspaceHeader(
        "Program assignment",
        context: player.displayName
      ) {
        if isWorking {
          HPProgressIndicator(style: .spinner)
            .accessibilityLabel("Loading program assignment")
        }
      }
    } metrics: {
      HPMetricCard(
        title: "Active programs",
        value: "\(activeAssignments.count)",
        context: "Current assignments"
      )
      HPMetricCard(
        title: "Templates",
        value: "\(coachTemplates.count)",
        context: "Available to assign"
      )
      HPMetricCard(
        title: "Linked parents",
        value: "\(parentLinks.count)",
        context: "View-only access"
      )
      if appState.canAdminActiveOrg {
        HPMetricCard(
          title: "Player access",
          value: playerAccess?.is_active == true ? "Granted" : "Payment required",
          context: "Player-specific override",
          valueColor: playerAccess?.is_active == true ? HP.Color.success : HP.Color.warning
        )
      }
    } details: {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        activeProgramsCard
        if appState.canAdminActiveOrg {
          playerAccessCard
        }
        assignProgramCard
        parentsCard
      }
    } related: { _ in
      EmptyView()
    } primaryAction: {
      EmptyView()
    }
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .dhdToast($toastText)
    .task { await reload() }
  }

  private var activeProgramsCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        if !canManagePlayer {
          Label(
            "Your organization limits program changes to players on your assigned team.",
            systemImage: "lock.fill"
          )
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.warning)
          .fixedSize(horizontal: false, vertical: true)
        }

        HPSectionHeader("Active programs") {
          if !activeAssignments.isEmpty {
            HPStatusBadge(text: "\(activeAssignments.count) active", kind: .success)
          }
        }

        if activeAssignments.isEmpty {
          Text("No active programs assigned.")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
        } else {
          ForEach(activeAssignments) { assignment in
            if let template = activeTemplates[assignment.template_id] {
              VStack(alignment: .leading, spacing: HP.Space.sm) {
                activeProgramHeader(template: template, assignment: assignment)
                detailValueRow("Template", value: template.name)
                detailValueRow("Days/week", value: "\(template.lift_weekdays.count)")
                detailValueRow("Weekdays", value: weekdayLabel(template.lift_weekdays))
                HPButton(
                  title: "End \(template.kind.title) program",
                  systemImage: "xmark.circle",
                  variant: .destructive,
                  size: .md,
                  fullWidth: true,
                  action: { Task { await endProgram(assignment) } }
                )
                .disabled(isWorking || !canManagePlayer)
              }
              if assignment.id != activeAssignments.last?.id {
                Divider().overlay(HP.Color.border.opacity(0.5))
              }
            }
          }
        }
      }
    }
  }

  private func activeProgramHeader(
    template: SDProgramTemplate,
    assignment: SDProgramAssignment
  ) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .firstTextBaseline, spacing: HP.Space.sm) {
        programKindLabel(template)
        Spacer(minLength: HP.Space.sm)
        programStartLabel(assignment)
      }
      VStack(alignment: .leading, spacing: HP.Space.xs) {
        programKindLabel(template)
        programStartLabel(assignment)
      }
    }
  }

  private func programKindLabel(_ template: SDProgramTemplate) -> some View {
    Label(template.kind.title, systemImage: template.kind.systemImage)
      .font(HP.Font.caption.weight(.semibold))
      .foregroundStyle(HP.Color.accent)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func programStartLabel(_ assignment: SDProgramAssignment) -> some View {
    Text("Starts \(assignment.start_date)")
      .font(HP.Font.caption)
      .foregroundStyle(HP.Color.textMuted)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func detailValueRow(_ label: String, value: String) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .firstTextBaseline, spacing: HP.Space.sm) {
        detailLabel(label)
        Spacer(minLength: HP.Space.sm)
        detailValue(value, alignment: .trailing)
      }
      VStack(alignment: .leading, spacing: HP.Space.xs) {
        detailLabel(label)
        detailValue(value, alignment: .leading)
      }
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }

  private func detailLabel(_ label: String) -> some View {
    Text(label)
      .font(HP.Font.caption)
      .foregroundStyle(HP.Color.textMuted)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func detailValue(_ value: String, alignment: TextAlignment) -> some View {
    Text(value)
      .font(HP.Font.callout.weight(.semibold))
      .foregroundStyle(HP.Color.text)
      .multilineTextAlignment(alignment)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var playerAccessCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Player app access") {
          HPStatusBadge(
            text: playerAccess?.is_active == true ? "Access granted" : "Payment required",
            kind: playerAccess?.is_active == true ? .success : .warning
          )
        }

        Text("This override applies only to \(player.displayName). It does not change access for anyone else in the organization.")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)

        ViewThatFits(in: .horizontal) {
          HStack(spacing: HP.Space.sm) {
            grantAccessButton(fullWidth: false)
            requirePaymentButton(fullWidth: false)
            if accessActionInFlight {
              HPProgressIndicator(style: .spinner)
                .accessibilityLabel("Updating player access")
            }
            Spacer(minLength: 0)
          }
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            grantAccessButton(fullWidth: true)
            requirePaymentButton(fullWidth: true)
            if accessActionInFlight {
              HPProgressIndicator(style: .spinner)
                .accessibilityLabel("Updating player access")
            }
          }
        }

        if let updated = playerAccess?.updated_at, !updated.isEmpty {
          Text("Last changed \(updated)")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
        }
      }
    }
  }

  private func grantAccessButton(fullWidth: Bool) -> some View {
    HPButton(
      title: "Grant access",
      systemImage: "lock.open.fill",
      variant: .secondary,
      size: .md,
      fullWidth: fullWidth,
      action: { Task { await setPlayerAccess(true) } }
    )
    .disabled(accessActionInFlight || playerAccess?.is_active == true)
  }

  private func requirePaymentButton(fullWidth: Bool) -> some View {
    HPButton(
      title: "Require payment",
      systemImage: "lock.fill",
      variant: .destructive,
      size: .md,
      fullWidth: fullWidth,
      action: { Task { await setPlayerAccess(false) } }
    )
    .disabled(accessActionInFlight || playerAccess?.is_active == false)
  }

  private var assignProgramCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("Assign new program")

        if coachTemplates.isEmpty {
          Text("No templates yet. Create one in Program Templates.")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
        } else {
          Picker("Template", selection: $selectedTemplateId) {
            Text("Select…").tag(UUID?.none)
            ForEach(coachTemplates) { template in
              Text(template.name).tag(UUID?.some(template.id))
            }
          }
          .tint(HP.Color.accent)

          DatePicker("Start date", selection: $startDate, displayedComponents: .date)
            .tint(HP.Color.accent)

          HPFormField(
            label: "Notes (optional)",
            text: $notes,
            placeholder: "Optional assignment notes"
          )

          HPButton(
            title: "Assign",
            systemImage: "checkmark.circle",
            variant: .primary,
            size: .lg,
            fullWidth: true,
            action: { Task { await assignProgram() } }
          )
          .disabled(isWorking || selectedTemplateId == nil || !canManagePlayer)
        }
      }
    }
  }

  private var parentsCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("Parents")

        Text("Invite a parent/guardian to view this player (view-only) and request bookings/payments.")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)

        ViewThatFits(in: .horizontal) {
          HStack(alignment: .bottom, spacing: HP.Space.sm) {
            HPFormField(label: "Parent email", text: $parentEmail, placeholder: "Parent email")
            HPFormField(
              label: "Relationship (optional)",
              text: $parentRelationship,
              placeholder: "Relationship"
            )
            .frame(maxWidth: 220)
            inviteButton(fullWidth: false)
          }
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPFormField(label: "Parent email", text: $parentEmail, placeholder: "Parent email")
            HPFormField(
              label: "Relationship (optional)",
              text: $parentRelationship,
              placeholder: "Relationship"
            )
            inviteButton(fullWidth: true)
          }
        }

        if !parentLinks.isEmpty {
          Divider().overlay(HP.Color.border.opacity(0.5))
          HPSectionHeader("Linked parents")
          ForEach(parentLinks, id: \.id) { link in
            Text("Parent \(link.parent_id.uuidString.prefix(6).uppercased()) • \(link.relationship ?? "—")")
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.textMuted)
              .fixedSize(horizontal: false, vertical: true)
          }
        }

        if !parentInvites.isEmpty {
          Divider().overlay(HP.Color.border.opacity(0.5))
          HPSectionHeader("Invites")
          ForEach(parentInvites) { invite in
            VStack(alignment: .leading, spacing: 2) {
              Text(invite.email_norm)
                .font(HP.Font.callout)
                .foregroundStyle(HP.Color.text)
                .fixedSize(horizontal: false, vertical: true)
              Text(invite.accepted_at == nil ? "Pending" : "Accepted")
                .font(HP.Font.caption)
                .foregroundStyle(HP.Color.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    }
  }

  private func inviteButton(fullWidth: Bool) -> some View {
    HPButton(
      title: "Invite",
      systemImage: "paperplane",
      variant: .secondary,
      size: .md,
      fullWidth: fullWidth,
      action: { Task { await sendParentInvite() } }
    )
    .disabled(
      isWorking || !canManagePlayer ||
        parentEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    )
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
