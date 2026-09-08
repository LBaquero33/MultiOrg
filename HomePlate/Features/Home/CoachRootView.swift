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

struct HPTrainingOperationsView: View {
  enum Mode { case today, athletes, sessions }
  @EnvironmentObject private var appState: AppState
  @State private var workspace: HPTrainingWorkspace?
  @State private var errorText: String?
  @State private var busy = false
  @State private var completion: HPTrainingWorkspace.Appointment?
  @State private var booking = false
  @State private var credits = false
  @State private var now = Date()
  @State private var trainerFilter = "all"
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
            if workspace.access["is_admin"]?.boolValue == true || workspace.access["staff_kind"]?.stringValue == "front_desk" {
              Picker("Trainer", selection: $trainerFilter) {
                Text("All authorized trainers").tag("all")
                Text("My sessions").tag(appState.myProfile?.id.uuidString ?? "none")
              }
            }
            Section(mode == .today ? "Today and needs closeout" : "Sessions") {
              let rows = workspace.appointments.filter { appointment in
                (trainerFilter == "all" || appointment.trainer_user_id?.uuidString == trainerFilter) &&
                (mode == .sessions || date(appointment.starts_at).map { HPTrainingCalendar.isToday($0, now: now, timezone: organizationTimezone) } == true ||
                  (date(appointment.ends_at).map { $0 < now } == true && !terminal(appointment.status)))
              }
              if rows.isEmpty { Text("No sessions in this view.") }
              ForEach(rows) { appointment in
                VStack(alignment: .leading, spacing: 8) {
                  Text(workspace.services.first { $0.id == appointment.service_id }?.name ?? "Training session").font(.headline)
                  Text(date(appointment.starts_at).map { HPTrainingCalendar.label($0, timezone: organizationTimezone) } ?? "Date unavailable").font(.subheadline)
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
                  if appointment.status == "completed" && canComplete(appointment, workspace: workspace) {
                    Button("Correct attendance / report") { completion = appointment }.disabled(busy)
                  }
                }.padding(.vertical, 4)
              }
            }
          }
          Section("Organization tools") {
            NavigationLink("Services, trainers and packages") {
              HPTrainingCatalogView(workspace: workspace) { await reload() }
            }
            Button("Book a session") { booking = true }
            Button("Package balances and credit decisions") { credits = true }
            Link("Open booking, services and website tools", destination: URL(string: "https://www.homeplateapps.com/app/lessons")!)
            Text("Web sign-in may be required. Choose the same organization before making changes.").font(.caption)
          }
          if !workspace.outcomes.isEmpty {
            Section("Shared session reports") {
              ForEach(Array(workspace.outcomes.enumerated()), id: \.offset) { _, report in
                VStack(alignment: .leading) {
                  if case .object(let outcome) = report["development_outcome"] {
                    NavigationLink {
                      ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                          Text("Shared session report").font(.title2.bold())
                          Text(outcome["summary"]?.stringValue ?? "No summary recorded.")
                            .textSelection(.enabled)
                          Text("This report contains the outcome shared by staff. Attendance and package-credit decisions are separate.").font(.caption)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding()
                      }.navigationTitle("Session report")
                    } label: { Text(outcome["summary"]?.stringValue ?? "Session report").lineLimit(3) }
                  }
                  if let athlete = report["athlete_id"]?.stringValue {
                    Text(workspace.athletes.first { $0.id.uuidString.lowercased() == athlete.lowercased() }?.display_name ?? "Athlete").font(.caption)
                  }
                }
              }
            }
          }
        } else if errorText == nil { ProgressView("Loading training workspace…") }
      }
      .navigationTitle(mode == .athletes ? "Athletes" : mode == .sessions ? "Sessions" : "Training today")
      .refreshable { await reload() }
      .task { await reload() }
      .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
      .sheet(item: $completion) { appointment in
        if let workspace {
          HPTrainingCompletionSheet(appointment: appointment, workspace: workspace) { await reload() }
        }
      }
      .sheet(isPresented: $booking) {
        if let workspace { HPTrainingBookingSheet(workspace: workspace, timezone: organizationTimezone) { await reload() } }
      }
      .sheet(isPresented: $credits) { HPTrainingCreditsView() }
    }
  }
  private func terminal(_ status: String) -> Bool { ["completed", "cancelled", "no_show"].contains(status) }
  private var organizationTimezone: String? {
    appState.availableOrganizations.first { $0.id == appState.activeOrgId }?.timezone
  }
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
  @State private var privateNotes: [UUID: String] = [:]
  @State private var shared: [UUID: Bool] = [:]
  @State private var operationId = UUID()
  @State private var correctionReason = ""
  @State private var busy = false
  @State private var errorText: String?
  let appointment: HPTrainingWorkspace.Appointment
  let workspace: HPTrainingWorkspace
  let onSaved: () async -> Void
  private var roster: [HPTrainingWorkspace.Participant] { workspace.participants.filter { $0.appointment_id == appointment.id } }
  var body: some View {
    NavigationStack {
      Form {
        if appointment.status == "completed" {
          Section("Reason for correction") {
            TextField("Explain what needs correcting", text: $correctionReason, axis: .vertical)
            Text("Previous attendance and reports remain in staff audit history. Credit decisions are separate.")
          }
        }
        Text("Choose attendance for every athlete. Package credits are used at booking confirmation, not charged again here. Staff review cancellation and no-show credits separately.")
        ForEach(roster, id: \.athlete_id) { participant in
          Section(workspace.athletes.first { $0.id == participant.athlete_id }?.display_name ?? "Athlete") {
            Picker("Attendance", selection: Binding(get: { attendance[participant.athlete_id] ?? "" }, set: { attendance[participant.athlete_id] = $0 })) {
              Text("Select attendance").tag("")
              Text("Attended").tag("completed")
              Text("No-show").tag("no_show")
              Text("Excused / cancelled").tag("cancelled")
            }
            TextField("Outcome", text: Binding(get: { outcomes[participant.athlete_id] ?? "" }, set: { outcomes[participant.athlete_id] = $0 }), axis: .vertical)
            TextField("Private staff note", text: Binding(get: { privateNotes[participant.athlete_id] ?? "" }, set: { privateNotes[participant.athlete_id] = $0 }), axis: .vertical)
            Toggle("Share outcome with athlete and family", isOn: Binding(get: { shared[participant.athlete_id] ?? false }, set: { shared[participant.athlete_id] = $0 }))
          }
        }
        if let errorText { Text(errorText).foregroundStyle(.red) }
      }
      .navigationTitle(appointment.status == "completed" ? "Correct roster" : "Complete roster")
      .onAppear {
        guard appointment.status == "completed", attendance.isEmpty else { return }
        for participant in roster {
          attendance[participant.athlete_id] = participant.attendance_status
          let report = workspace.outcomes.first { $0["appointment_id"]?.stringValue?.lowercased() == appointment.id.uuidString.lowercased() && $0["athlete_id"]?.stringValue?.lowercased() == participant.athlete_id.uuidString.lowercased() }
          if case .object(let outcome) = report?["development_outcome"] { outcomes[participant.athlete_id] = outcome["summary"]?.stringValue }
          shared[participant.athlete_id] = report?["visible_to_athlete"]?.boolValue ?? false
        }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
        ToolbarItem(placement: .confirmationAction) {
          Button("Complete") { Task { await save() } }
            .disabled(busy || roster.isEmpty || (appointment.status == "completed" && correctionReason.trimmingCharacters(in: .whitespacesAndNewlines).count < 8) || roster.contains { attendance[$0.athlete_id, default: ""].isEmpty })
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
      "private_note": .string(privateNotes[participant.athlete_id, default: ""]),
      "visible_to_athlete": .bool(shared[participant.athlete_id, default: false]),
    ]) }
    do {
      try await service.trainingAction(organizationId: org, action: appointment.status == "completed" ? "correct_appointment" : "complete_appointment", payload: [
        "reason": .string(correctionReason),
        "appointment_id": .string(appointment.id.uuidString), "operation_id": .string(operationId.uuidString),
        "expected_updated_at": .string(appointment.updated_at), "participants": .array(rows),
      ])
      await onSaved(); dismiss()
    } catch { errorText = "Completion could not be confirmed. Retry the same roster, or refresh if another staff member changed the session." }
  }
}

private struct HPTrainingBookingSheet: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  let workspace: HPTrainingWorkspace
  let timezone: String?
  let onSaved: () async -> Void
  @State private var athleteId = ""
  @State private var serviceId = ""
  @State private var trainerId = ""
  @State private var packageId = ""
  @State private var locationId = ""
  @State private var resourceIds: Set<UUID> = []
  @State private var startsAt = Date().addingTimeInterval(3600)
  @State private var requestId = UUID()
  @State private var busy = false
  @State private var errorText: String?
  private var trainers: [HPTrainingWorkspace.Trainer] {
    let eligible = Set((workspace.trainer_offerings ?? []).filter { $0.active && $0.service_id.uuidString == serviceId }.map(\.trainer_directory_id))
    return (workspace.staff_directory ?? []).filter { $0.staff_kind == "trainer" && $0.status == "active" && eligible.contains($0.id) }
  }
  var body: some View {
    NavigationStack {
      Form {
        Section("Session") {
          Picker("Athlete", selection: $athleteId) {
            Text("Choose athlete").tag("")
            ForEach(workspace.athletes) { Text($0.display_name).tag($0.id.uuidString) }
          }
          Picker("Service", selection: $serviceId) {
            Text("Choose service").tag("")
            ForEach(workspace.services.filter { $0.active != false }) { Text($0.name).tag($0.id.uuidString) }
          }.onChange(of: serviceId) { _, _ in trainerId = "" }
          Picker("Trainer", selection: $trainerId) {
            Text("Choose trainer").tag("")
            ForEach(trainers) { Text($0.display_name).tag($0.id.uuidString) }
          }
          DatePicker("Start", selection: $startsAt)
            .environment(\.timeZone, HPTrainingCalendar.calendar(timezone: timezone).timeZone)
          Text("Times use \(timezone ?? "UTC"). Working hours, permissions, and conflicts are checked when you confirm.").font(.caption)
          Picker("Location", selection: $locationId) {
            Text("No location selected").tag("")
            ForEach((workspace.locations ?? []).filter { $0.is_active != false }) { Text($0.name).tag($0.id.uuidString) }
          }.onChange(of: locationId) { _, _ in resourceIds.removeAll() }
          ForEach((workspace.resources ?? []).filter { $0.is_active != false && (locationId.isEmpty || $0.location_id?.uuidString == locationId) }) { resource in
            Toggle(resource.name, isOn: Binding(get: { resourceIds.contains(resource.id) }, set: { if $0 { resourceIds.insert(resource.id) } else { resourceIds.remove(resource.id) } }))
          }
        }
        Section("Package funding") {
          Picker("Package", selection: $packageId) {
            Text("Do not use package credits").tag("")
            ForEach((workspace.packages ?? []).filter(\.active)) { Text($0.name).tag($0.id.uuidString) }
          }
          Text("Selecting a package uses one existing credit when this booking is confirmed. An insufficient balance prevents the entire booking. No cash payment is collected here.").font(.caption)
        }
        if let errorText { Text(errorText).foregroundStyle(.red) }
      }
      .navigationTitle("Book a session")
      .disabled(busy)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
        ToolbarItem(placement: .confirmationAction) {
          Button("Confirm") { Task { await save() } }.disabled(busy || athleteId.isEmpty || serviceId.isEmpty || trainerId.isEmpty)
        }
      }.interactiveDismissDisabled(busy)
    }
  }
  private func save() async {
    guard let service = appState.supabase, let org = appState.activeOrgId else { return }
    busy = true; defer { busy = false }; errorText = nil
    do {
      try await service.trainingAction(organizationId: org, action: "create_appointment", payload: [
        "service_id": .string(serviceId), "trainer_directory_id": .string(trainerId),
        "athlete_ids": .array([.string(athleteId)]), "starts_at": .string(ISO8601DateFormatter().string(from: startsAt)),
        "package_id": .string(packageId), "idempotency_key": .string(requestId.uuidString),
        "location_id": .string(locationId), "resource_ids": .array(resourceIds.sorted { $0.uuidString < $1.uuidString }.map { .string($0.uuidString) }),
      ])
      await onSaved(); dismiss()
    } catch { errorText = "Booking could not be confirmed: \(error.localizedDescription). Check availability and package credits, then retry. If you change the request, close and reopen this form." }
  }
}

private struct HPTrainingCreditsView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var data: HPTrainingCredits?
  @State private var errorText: String?
  @State private var selected: HPTrainingCredits.Decision?
  var body: some View {
    NavigationStack {
      List {
        Section { Text("Package credits are used at booking confirmation. Staff decide whether to keep or return the used credit after a cancellation or no-show.") }
        if let errorText { Section { Text(errorText).foregroundStyle(.red); Button("Retry") { Task { await load() } } } }
        if let data {
          Section("Ledger balances") {
            if data.balances.isEmpty { Text("No package ledger recorded for this view.") }
            ForEach(data.balances) { row in
              VStack(alignment: .leading) {
                Text("\(row.display_name) · \(row.package_name)")
                Text("\(row.credits) available credits").font(.headline)
                if let expired = row.expired_credits, expired > 0 { Text("\(expired) expired credits retained in history").font(.caption) }
              }
            }
          }
          Section("Staff decisions needed") {
            if data.pending_decisions.isEmpty { Text("No pending decisions in your accessible records.") }
            ForEach(data.pending_decisions) { row in
              Button { selected = row } label: { VStack(alignment: .leading) { Text(row.display_name); Text(row.package_name).font(.caption) } }
            }
          }
          if let reviews = data.payment_review, !reviews.isEmpty {
            Section("Payments needing staff review") {
              Text("A payment changed after credits were issued. Review the payment before making a reasoned credit adjustment. No credits were automatically removed.")
              ForEach(reviews) { row in
                VStack(alignment: .leading) { Text("\(row.display_name) · \(row.package_name)"); Text(row.reversed ? "Reversed" : row.has_refund ? "Refund recorded" : row.payment_status).font(.caption) }
              }
            }
          }
        } else if errorText == nil { ProgressView("Loading credits…") }
      }.navigationTitle("Package credits")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task(id: appState.activeOrgAuthorizationKey) { await load() }
        .refreshable { await load() }
        .sheet(item: $selected) { row in HPTrainingCreditDecisionSheet(row: row) { await load() } }
    }
  }
  private func load() async {
    guard let service = appState.supabase, let org = appState.activeOrgId else { return }
    data = nil; errorText = nil
    do {
      let result = try await service.trainingCredits(organizationId: org)
      guard !Task.isCancelled, org == appState.activeOrgId else { return }; data = result
    } catch { guard !Task.isCancelled, org == appState.activeOrgId else { return }; errorText = "Credit records could not be loaded." }
  }
}

private struct HPTrainingCreditDecisionSheet: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  let row: HPTrainingCredits.Decision
  let onSaved: () async -> Void
  @State private var choice = ""
  @State private var reason = ""
  @State private var requestId = UUID()
  @State private var busy = false
  @State private var errorText: String?
  var body: some View {
    NavigationStack {
      Form {
        Text("\(row.display_name) · \(row.package_name). One credit was used when booked. Keeping it does not charge again. This decision is recorded once.")
        Picker("Decision", selection: $choice) {
          Text("Choose explicitly").tag(""); Text("Keep used credit").tag("keep"); Text("Return one credit").tag("return")
        }
        TextField("Reason for decision", text: $reason, axis: .vertical)
        if let errorText { Text(errorText).foregroundStyle(.red) }
      }.navigationTitle("Review credit")
        .disabled(busy)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") { Task { await save() } }.disabled(busy || choice.isEmpty || reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
          }
        }.interactiveDismissDisabled(busy)
    }
  }
  private func save() async {
    guard let service = appState.supabase, let org = appState.activeOrgId else { return }
    busy = true; defer { busy = false }
    do {
      try await service.trainingAction(organizationId: org, action: "decide_package_credit", payload: [
        "appointment_id": .string(row.appointment_id.uuidString), "athlete_id": .string(row.athlete_id.uuidString),
        "decision": .string(choice), "reason": .string(reason), "request_id": .string(requestId.uuidString),
      ])
      await onSaved(); dismiss()
    } catch { errorText = "The decision could not be confirmed: \(error.localizedDescription)" }
  }
}
