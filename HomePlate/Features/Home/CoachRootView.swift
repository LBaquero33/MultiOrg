import SwiftUI

/// Role- and capability-aware staff shell. The destination views, feature
/// gates, deep-link handlers, and authorization checks are the same routes that
/// predate the Home Plate navigation presentation.
struct CoachRootView: View {
  @EnvironmentObject private var appState: AppState
  @State private var trainingExperience: HPTrainingExperience?

#if os(macOS)
  @State private var selection: HPAppNavigationDestination = .coachToday
#else
  @State private var mobileSelection: HPAppNavigationDestination = .coachToday
#endif

  var body: some View {
    Group {
#if os(macOS)
    HPRegularApplicationShell(
      role: sidebarRole,
      inventory: navigationInventory,
      selection: $selection
    ) { destination in
      destinationView(destination)
    }
    .onChange(of: appState.activeOrgAuthorizationKey) { _, _ in
      let normalized = navigationInventory.normalizedRegularSelection(selection)
      if normalized != selection {
        selection = normalized
      }
    }
    .onChange(of: appState.requestedChatChannelId) { _, channelId in
      guard channelId != nil, feature("chat") else { return }
      selection = .chat
    }
    .onChange(of: appState.requestedTeamWorkspaceSection) { _, section in
      guard section != nil else { return }
      selection = .coachTeam
    }
    .task(id: appState.requestedChatChannelId) {
      guard appState.requestedChatChannelId != nil, feature("chat") else { return }
      selection = .chat
    }
    .task(id: appState.activeOrgAuthorizationKey) {
      await appState.refreshTeamOperationsContext()
    }
#else
    HPAdaptiveApplicationShell(
      role: sidebarRole,
      roleSubtitle: roleSubtitle,
      inventory: navigationInventory,
      selection: $mobileSelection
    ) { destination in
      destinationView(destination)
    }
    .onChange(of: appState.requestedChatChannelId) { _, channelId in
      guard channelId != nil, feature("chat") else { return }
      mobileSelection = .chat
    }
    .onChange(of: appState.requestedTeamWorkspaceSection) { _, section in
      guard section != nil else { return }
      mobileSelection = .coachTeam
    }
    .task(id: appState.requestedChatChannelId) {
      guard appState.requestedChatChannelId != nil, feature("chat") else { return }
      mobileSelection = .chat
    }
    .task(id: appState.activeOrgAuthorizationKey) {
      await appState.refreshTeamOperationsContext()
    }
#endif
  }

    .task(id: appState.activeOrgAuthorizationKey) {
      trainingExperience = nil
      guard let service = appState.supabase, let organizationId = appState.activeOrgId else { return }
      let loaded = try? await service.trainingExperience(organizationId: organizationId)
      guard !Task.isCancelled, appState.activeOrgId == organizationId else { return }
      trainingExperience = loaded
    }
  }

  private var isTraining: Bool {
    let kind = trainingExperience?.organization_type ?? appState.availableOrganizations.first(where: { $0.id == appState.activeOrgId })?.organization_type
    return ["training_facility", "independent_trainer", "hybrid_academy"].contains(kind ?? "")
  }

  private var navigationInventory: HPAppNavigationInventory {
    if isTraining {
      return .training(experience: trainingExperience, canAdminister: appState.canAdminActiveOrg)
    }
    if appState.canAdminActiveOrg {
      return HPAppNavigationInventory.owner(
        facilitiesTitle: term("facilities", fallback: "Facilities"),
        programsTitle: "\(term("program", fallback: "Program")) Templates",
        facilitiesEnabled: feature("facilities"),
        chatEnabled: feature("chat"),
        programsEnabled: feature("programs"),
        isPlatformAdmin: appState.isPlatformAdmin
      )
    }
    return HPAppNavigationInventory.staff(
      playersTitle: term("players", fallback: "Players"),
      facilitiesTitle: term("facilities", fallback: "Facilities"),
      programsTitle: "\(term("program", fallback: "Program")) Templates",
      facilitiesEnabled: feature("facilities"),
      chatEnabled: feature("chat"),
      programsEnabled: feature("programs"),
      paymentsEnabled: appState.canManagePaymentRequests,
      canAdministerOrganization: false,
      isPlatformAdmin: appState.isPlatformAdmin
    )
  }

  private var sidebarRole: HPRole {
    switch appState.activeOrgMembership?.normalizedRole {
    case "owner", "admin": .owner
    default: .coach
    }
  }

  private var roleSubtitle: String {
    switch appState.activeOrgMembership?.normalizedRole {
    case "owner": "Owner workspace"
    case "admin": "Organization admin workspace"
    default: "Coach workspace"
    }
  }

  @ViewBuilder
  private func destinationView(_ destination: HPAppNavigationDestination) -> some View {
    switch destination {
    case .coachToday:
      if isTraining { HPTrainingOperationsView(mode: .today).id(appState.activeOrgAuthorizationKey) } else { CoachTodayFoundationView() }
    case .coachTeam:
      CoachTeamCommandCenterView()
    case .coachSchedule:
      if isTraining { HPTrainingOperationsView(mode: .sessions).id(appState.activeOrgAuthorizationKey) } else { CoachScheduleFoundationView() }
    case .coachPlayers:
      if isTraining { HPTrainingOperationsView(mode: .athletes).id(appState.activeOrgAuthorizationKey) } else { CoachHomeView() }
    case .coachCalendar:
      GameCalendarView()
    case .coachFacilities:
      if feature("facilities") {
        CoachFacilitiesView()
      } else {
        disabledFeatureView("Facilities")
      }
    case .coachTeams:
      if appState.canAdminActiveOrg {
#if os(macOS)
        OrgTeamOperationsAdminView()
#else
        NavigationStack { OrgTeamOperationsAdminView() }
#endif
      } else {
        CoachTeamsView()
      }
    case .coachPrograms:
      if feature("programs") {
        CoachProgramsView()
      } else {
        disabledFeatureView("Programs")
      }
    case .chat:
      if feature("chat") {
        ChatChannelListView()
      } else {
        disabledFeatureView("Chat")
      }
    case .games:
      GameCalendarView()
    case .payments:
      if appState.canAdminActiveOrg, let organizationId = appState.activeOrgId {
#if os(macOS)
        financeView(organizationId: organizationId)
#else
        NavigationStack { financeView(organizationId: organizationId) }
#endif
      } else if appState.canManagePaymentRequests {
        CoachPaymentRequestsView()
      } else {
        accessDeniedView("Payments")
      }
    case .finance:
      if appState.canAdminActiveOrg, let organizationId = appState.activeOrgId {
#if os(macOS)
        financeView(organizationId: organizationId)
#else
        NavigationStack { financeView(organizationId: organizationId) }
#endif
      } else {
        disabledFeatureView("Finance")
      }
    case .organizationAdmin:
      if !appState.canAdminActiveOrg {
        accessDeniedView("Organization Administration")
      } else {
#if os(macOS)
        OrgAdminConsoleView()
#else
        NavigationStack { OrgAdminConsoleView() }
#endif
      }
    case .platformAdmin:
      if !appState.isPlatformAdmin {
        accessDeniedView("Platform Administration")
      } else {
#if os(macOS)
        PlatformAdminDashboardView()
#else
        NavigationStack { PlatformAdminDashboardView() }
#endif
      }
    case .account:
#if os(macOS)
      AccountView()
#else
      NavigationStack { AccountView() }
#endif
    default:
      disabledFeatureView("Workspace")
    }
  }

  private func financeView(organizationId: UUID) -> some View {
    FinanceDashboardView(
      organizationId: organizationId,
      organizationName: financeOrganizationName,
      platformSupportMode: false
    )
  }

  private var financeOrganizationName: String {
    appState.availableOrganizations.first(where: { $0.id == appState.activeOrgId })?.name
      ?? appState.activeOrgSettings?.display_name
      ?? appState.activeOrgSettings?.short_name
      ?? "Home Plate"
  }

  private func term(_ key: String, fallback: String) -> String {
    appState.activeOrgSettings?.term(key, fallback: fallback) ?? fallback
  }

  private func feature(_ key: String) -> Bool {
    appState.activeOrgSettings?.feature(key) ?? true
  }

  private func disabledFeatureView(_ name: String) -> some View {
    HPStateScreenLayout { _ in
      HPCard {
        HPEmptyState(
          title: "\(name) is disabled",
          message: "Turn it back on in Org Admin → Features.",
          systemImage: "switch.2"
        )
      }
    }
  }

  private func accessDeniedView(_ name: String) -> some View {
    HPStateScreenLayout { _ in
      HPCard {
        HPEmptyState(
          title: "Access denied",
          message: "Your active organization membership does not allow access to \(name.lowercased()).",
          systemImage: "lock.shield"
        )
      }
    }
  }
}

private struct HPTrainingOperationsView: View {
  enum Mode { case today, athletes, sessions }
  @EnvironmentObject private var appState: AppState
  @State private var workspace: HPTrainingWorkspace?
  @State private var errorText: String?
  @State private var busy = false
  @State private var completion: HPTrainingWorkspace.Appointment?
  let mode: Mode

  var body: some View {
    NavigationStack {
      List {
        if let errorText { Section { Text(errorText).foregroundStyle(.red); Button("Retry") { Task { await reload() } } } }
        if let workspace {
          if !(workspace.source_diagnostics["unavailable_sources"] ?? []).isEmpty {
            Text("Some records could not be loaded. Missing information is not a zero or a completed task.").foregroundStyle(.orange)
          }
          if mode == .athletes {
            Section("Athletes") {
              if workspace.athletes.isEmpty { Text("No athletes are available to your current role.") }
              ForEach(workspace.athletes) { athlete in
                VStack(alignment: .leading) {
                  Text(athlete.display_name).font(.headline)
                  Text(athlete.athlete_user_id == nil ? "Staff-maintained record · Account not linked" : "Account linked").font(.caption)
                }
              }
            }
          } else {
            Section(mode == .today ? "Today and needs closeout" : "Sessions") {
              let rows = workspace.appointments.filter { appointment in
                mode == .sessions || date(appointment.starts_at).map { Calendar.current.isDateInToday($0) } == true ||
                  (date(appointment.ends_at).map { $0 < Date() } == true && !terminal(appointment.status))
              }
              if rows.isEmpty { Text("No sessions in this view.") }
              ForEach(rows) { appointment in
                VStack(alignment: .leading, spacing: 8) {
                  Text(workspace.services.first { $0.id == appointment.service_id }?.name ?? "Training session").font(.headline)
                  Text(date(appointment.starts_at)?.formatted(date: .abbreviated, time: .shortened) ?? "Date unavailable").font(.subheadline)
                  Text(appointment.status.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption)
                  ForEach(workspace.participants.filter { $0.appointment_id == appointment.id }, id: \.athlete_id) { participant in
                    Text(workspace.athletes.first { $0.id == participant.athlete_id }?.display_name ?? "Athlete").font(.caption)
                  }
                  if !terminal(appointment.status) {
                    if canManage(appointment, workspace: workspace) {
                      Button("Check in") { Task { await checkIn(appointment) } }.disabled(busy || appointment.status == "checked_in")
                    }
                    if canComplete(appointment, workspace: workspace) {
                      Button("Complete roster") { completion = appointment }.disabled(busy)
                    }
                  }
                }.padding(.vertical, 4)
              }
            }
          }
          Section("Organization tools") {
            Link("Open booking, services and website tools", destination: URL(string: "https://www.homeplateapps.com/app/lessons")!)
            Text("Web sign-in may be required. Choose the same organization before making changes.").font(.caption)
          }
        } else if errorText == nil { ProgressView("Loading training workspace…") }
      }
      .navigationTitle(mode == .athletes ? "Athletes" : mode == .sessions ? "Sessions" : "Training today")
      .refreshable { await reload() }
      .task { await reload() }
      .sheet(item: $completion) { appointment in
        if let workspace {
          HPTrainingCompletionSheet(appointment: appointment, workspace: workspace) { await reload() }
        }
      }
    }
  }
  private func terminal(_ status: String) -> Bool { ["completed", "cancelled", "no_show"].contains(status) }
  private func date(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
  private func canComplete(_ appointment: HPTrainingWorkspace.Appointment, workspace: HPTrainingWorkspace) -> Bool {
    if workspace.access["is_admin"]?.boolValue == true { return true }
    guard let currentUserId = appState.myProfile?.id else { return false }
    return appointment.trainer_user_id == currentUserId
  }
  private func canManage(_ appointment: HPTrainingWorkspace.Appointment, workspace: HPTrainingWorkspace) -> Bool {
    canComplete(appointment, workspace: workspace) || workspace.access["staff_kind"]?.stringValue == "front_desk"
  }
  private func reload() async {
    guard let service = appState.supabase, let org = appState.activeOrgId else { return }
    do {
      let loaded = try await service.trainingWorkspace(organizationId: org)
      guard !Task.isCancelled, org == appState.activeOrgId else { return }
      workspace = loaded; errorText = nil
    } catch {
      guard !Task.isCancelled, org == appState.activeOrgId else { return }
      errorText = "Training records could not be refreshed. Please retry."
    }
  }
  private func checkIn(_ appointment: HPTrainingWorkspace.Appointment) async {
    guard let service = appState.supabase, let org = appState.activeOrgId else { return }
    busy = true; defer { busy = false }
    do {
      try await service.trainingAction(organizationId: org, action: "update_appointment", payload: [
        "appointment_id": .string(appointment.id.uuidString), "status": .string("checked_in"),
        "expected_updated_at": .string(appointment.updated_at),
      ])
      await reload()
    } catch { errorText = "Check-in could not be confirmed. Refresh before trying again." }
  }
}

private struct HPTrainingCompletionSheet: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var attendance: [UUID: String] = [:]
  @State private var outcomes: [UUID: String] = [:]
  @State private var shared: [UUID: Bool] = [:]
  @State private var operationId = UUID()
  @State private var busy = false
  @State private var errorText: String?
  let appointment: HPTrainingWorkspace.Appointment
  let workspace: HPTrainingWorkspace
  let onSaved: () async -> Void
  private var roster: [HPTrainingWorkspace.Participant] { workspace.participants.filter { $0.appointment_id == appointment.id } }
  var body: some View {
    NavigationStack {
      Form {
        Text("Choose attendance for every athlete. Credits are not automatically deducted.")
        ForEach(roster, id: \.athlete_id) { participant in
          Section(workspace.athletes.first { $0.id == participant.athlete_id }?.display_name ?? "Athlete") {
            Picker("Attendance", selection: Binding(get: { attendance[participant.athlete_id] ?? "" }, set: { attendance[participant.athlete_id] = $0 })) {
              Text("Select attendance").tag("")
              Text("Attended").tag("completed")
              Text("No-show").tag("no_show")
              Text("Excused / cancelled").tag("cancelled")
            }
            TextField("Outcome", text: Binding(get: { outcomes[participant.athlete_id] ?? "" }, set: { outcomes[participant.athlete_id] = $0 }), axis: .vertical)
            Toggle("Share outcome with athlete and family", isOn: Binding(get: { shared[participant.athlete_id] ?? false }, set: { shared[participant.athlete_id] = $0 }))
          }
        }
        if let errorText { Text(errorText).foregroundStyle(.red) }
      }
      .navigationTitle("Complete roster")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
        ToolbarItem(placement: .confirmationAction) {
          Button("Complete") { Task { await save() } }
            .disabled(busy || roster.isEmpty || roster.contains { attendance[$0.athlete_id, default: ""].isEmpty })
        }
      }
      .interactiveDismissDisabled(busy)
    }
  }
  private func save() async {
    guard let service = appState.supabase, let org = appState.activeOrgId else { return }
    busy = true; defer { busy = false }
    let rows: [SDJSONValue] = roster.map { participant in .object([
      "athlete_id": .string(participant.athlete_id.uuidString.lowercased()),
      "attendance_status": .string(attendance[participant.athlete_id, default: ""]),
      "outcome": .string(outcomes[participant.athlete_id, default: ""]),
      "private_note": .string(""),
      "visible_to_athlete": .bool(shared[participant.athlete_id, default: false]),
    ]) }
    do {
      try await service.trainingAction(organizationId: org, action: "complete_appointment", payload: [
        "appointment_id": .string(appointment.id.uuidString), "operation_id": .string(operationId.uuidString),
        "expected_updated_at": .string(appointment.updated_at), "participants": .array(rows),
      ])
      await onSaved(); dismiss()
    } catch { errorText = "Completion could not be confirmed. Retry the same roster, or refresh if another staff member changed the session." }
  }
}
