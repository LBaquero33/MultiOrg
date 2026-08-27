import SwiftUI

enum WARTrainingWorkspaceMode: String, CaseIterable, Identifiable {
  case athletes = "Athletes"
  case trainers = "Trainers"
  case lessons = "Lessons & Sessions"
  case testing = "Testing"
  case dataLab = "WAR Data Lab"

  var id: String { rawValue }

  var symbol: String {
    switch self {
    case .athletes: "figure.run"
    case .trainers: "person.2.badge.gearshape"
    case .lessons: "calendar.badge.clock"
    case .testing: "testtube.2"
    case .dataLab: "chart.xyaxis.line"
    }
  }

  var context: String {
    switch self {
    case .athletes: "Profiles, trainer assignments, packages, testing, and performance data"
    case .trainers: "Public profiles, specialties, availability, and athlete assignments"
    case .lessons: "Bookings, arrivals, session delivery, resources, and payment state"
    case .testing: "Reusable assessments, results, comparisons, and family reports"
    case .dataLab: "Blast, Rapsodo, 4D Motion, combined performance, trends, and source coverage"
    }
  }
}

private enum WAROperationsSheet: Identifiable {
  case athlete
  case appointment
  case testingTemplate
  case availability

  var id: String { String(describing: self) }
}

struct WARTrainingOperationsView: View {
  @EnvironmentObject private var appState: AppState
  @StateObject private var model = WAROperationsWorkspaceModel()
  @State private var query = ""
  @State private var activeSheet: WAROperationsSheet?
  @State private var selectedAthleteId: UUID?
  @State private var selectedDataLabModule = "athlete_overview"
  @State private var selectedProvider = ""

  let mode: WARTrainingWorkspaceMode

  private let dataLabModules: [(String, String)] = [
    ("athlete_overview", "Overview"),
    ("session_detail", "Sessions"),
    ("blast", "Blast"),
    ("rapsodo", "Rapsodo"),
    ("4d_motion", "4D Motion"),
    ("combined_performance", "Combined"),
    ("trends", "Trends"),
    ("athlete_comparison", "Compare"),
    ("reports", "Reports"),
    ("source_files", "Sources"),
  ]

  var body: some View {
    HPListScreenLayout {
      HPWorkspaceHeader(mode.rawValue, context: mode.context) {
        if canCreate {
          HPButton(
            title: primaryActionTitle,
            systemImage: "plus",
            variant: .primary,
            size: .sm
          ) { activeSheet = primarySheet }
        }
      }
    } controls: {
      controls
    } results: { _ in
      VStack(alignment: .leading, spacing: HP.Space.md) {
        sourceHealth
        if model.isLoading, model.workspace == nil {
          HPCard { HPLoadingState(text: "Loading WAR Performance…") }
        } else if let error = model.loadError, model.workspace == nil {
          HPCard {
            HPErrorState(
              title: "WAR Performance couldn’t be loaded.",
              message: error,
              onRetry: { Task { await reload() } }
            )
          }
        } else if let workspace = model.workspace {
          workspaceContent(workspace)
        }
        if let error = model.operationError {
          HPCard { HPErrorState(title: "The update couldn’t be completed.", message: error) }
        }
      }
    }
    .navigationTitle(mode.rawValue)
    .task(id: appState.activeOrgAuthorizationKey) { await reload() }
    .refreshable { await reload() }
    .sheet(item: $activeSheet) { sheet in operationSheet(sheet) }
    .hpToast($model.confirmation)
  }

  @ViewBuilder
  private var controls: some View {
    if mode == .dataLab {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          Picker("Athlete", selection: $selectedAthleteId) {
            Text("Select athlete").tag(UUID?.none)
            ForEach(filteredAthletes, id: \.warRecordID) { athlete in
              Text(athlete.warDisplay("display_name")).tag(athlete.warUUID("id") as UUID?)
            }
          }
          .pickerStyle(.menu)
          Picker("Model", selection: $selectedDataLabModule) {
            ForEach(dataLabModules, id: \.0) { module in Text(module.1).tag(module.0) }
          }
          .pickerStyle(.menu)
          if !availableProviders.isEmpty {
            Picker("Provider", selection: $selectedProvider) {
              Text("Automatic").tag("")
              ForEach(availableProviders, id: \.self) { provider in Text(provider.capitalized).tag(provider) }
            }
            .pickerStyle(.menu)
          }
          HPButton(
            title: "Run analysis",
            systemImage: "play.fill",
            variant: .primary,
            isLoading: model.isAnalyzing,
            fullWidth: true
          ) { Task { await runAnalysis() } }
        }
      }
    } else {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSearchBar(text: $query, placeholder: "Search \(mode.rawValue.lowercased())")
          Text(resultCountLabel)
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
        }
      }
    }
  }

  @ViewBuilder
  private var sourceHealth: some View {
    if let workspace = model.workspace, !workspace.unavailableSources.isEmpty {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.xs) {
          Label("Some connected sources are temporarily unavailable", systemImage: "exclamationmark.triangle")
            .font(HP.Font.callout.weight(.semibold))
            .foregroundStyle(HP.Color.warning)
          Text(workspace.unavailableSources.map(readable).joined(separator: ", "))
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
          Text("Loaded WAR records remain available while those sources recover.")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
        }
      }
    }
  }

  @ViewBuilder
  private func workspaceContent(_ workspace: SDWARWorkspace) -> some View {
    switch mode {
    case .athletes: athleteWorkspace(workspace)
    case .trainers: trainerWorkspace(workspace)
    case .lessons: lessonsWorkspace(workspace)
    case .testing: testingWorkspace(workspace)
    case .dataLab: dataLabWorkspace(workspace)
    }
  }

  @ViewBuilder
  private func athleteWorkspace(_ workspace: SDWARWorkspace) -> some View {
    summaryGrid([
      ("Athletes", workspace.athletes.count, "figure.run"),
      ("Assigned", Set(workspace.assignments.compactMap { $0.warUUID("athlete_id") }).count, "person.2"),
      ("Testing results", workspace.testing_results.count, "testtube.2"),
      ("Provider files", workspace.imports.count, "externaldrive"),
    ])
    if filteredAthletes.isEmpty {
      HPCard {
        HPEmptyState(
          title: query.isEmpty ? "No athletes yet" : "No athletes match",
          message: query.isEmpty ? "Create or invite the first WAR athlete." : "Try another name or email.",
          systemImage: "figure.run",
          actionTitle: workspace.isManager && query.isEmpty ? "Add athlete" : nil,
          action: workspace.isManager && query.isEmpty ? { activeSheet = .athlete } : nil
        )
      }
    } else {
      ForEach(filteredAthletes, id: \.warRecordID) { athlete in
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HStack(alignment: .top) {
              VStack(alignment: .leading, spacing: 4) {
                Text(athlete.warDisplay("display_name")).font(HP.Font.headline)
                Text(athlete.warDisplay("invited_email", fallback: "No linked email"))
                  .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
              }
              Spacer()
              HPStatusBadge(text: readable(athlete.warDisplay("status")), kind: statusKind(athlete.warString("status")))
            }
            let athleteId = athlete.warUUID("id")
            let trainerCount = workspace.assignments.filter { $0.warUUID("athlete_id") == athleteId }.count
            let tests = workspace.testing_results.filter { $0.warUUID("athlete_id") == athleteId }.count
            let files = workspace.imports.filter {
              $0.warUUID("player_id") == athleteId || $0.warUUID("war_athlete_id") == athleteId
            }.count
            Text("\(trainerCount) trainer assignment\(trainerCount == 1 ? "" : "s") · \(tests) tests · \(files) provider files")
              .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            if let discipline = athlete.warString("primary_discipline").nilIfBlank {
              Label(readable(discipline), systemImage: "scope")
                .font(HP.Font.caption).foregroundStyle(HP.Color.textTertiary)
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func trainerWorkspace(_ workspace: SDWARWorkspace) -> some View {
    summaryGrid([
      ("Trainers", workspace.staff.filter { $0.warString("staff_kind") == "trainer" }.count, "person.2"),
      ("Availability windows", workspace.availability.count, "clock"),
      ("Athlete assignments", workspace.assignments.count, "link"),
      ("Public profiles", workspace.public_profiles.filter { $0.warBool("is_published") }.count, "globe"),
    ])
    let trainers = filteredTrainers
    if trainers.isEmpty {
      HPCard {
        HPEmptyState(
          title: "No trainers match",
          message: query.isEmpty ? "Add trainer memberships in WAR Settings, then configure profiles and availability here." : "Try another search.",
          systemImage: "person.2.badge.gearshape"
        )
      }
    } else {
      ForEach(trainers, id: \.warRecordID) { trainer in
        let trainerId = trainer.warUUID("user_id")
        let profile = workspace.profiles.first { $0.warUUID("id") == trainerId }
        let publicProfile = workspace.public_profiles.first { $0.warUUID("user_id") == trainerId }
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HStack(alignment: .top) {
              VStack(alignment: .leading, spacing: 4) {
                Text(publicProfile?.warDisplay("display_name", fallback: profile?.warDisplay("full_name", fallback: "Trainer") ?? "Trainer") ?? profile?.warDisplay("full_name", fallback: "Trainer") ?? "Trainer")
                  .font(HP.Font.headline)
                Text(publicProfile?.warDisplay("public_title", fallback: readable(trainer.warDisplay("staff_kind"))) ?? readable(trainer.warDisplay("staff_kind")))
                  .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
              }
              Spacer()
              HPStatusBadge(
                text: publicProfile?.warBool("is_published") == true ? "Public" : "Internal",
                kind: publicProfile?.warBool("is_published") == true ? .success : .neutral
              )
            }
            if let specialties = publicProfile?.warString("specialties").nilIfBlank {
              Text(specialties).font(HP.Font.callout).foregroundStyle(HP.Color.textTertiary)
            }
            let assigned = workspace.assignments.filter { $0.warUUID("trainer_user_id") == trainerId }.count
            let windows = workspace.availability.filter { $0.warUUID("trainer_user_id") == trainerId }.count
            Text("\(assigned) assigned athletes · \(windows) recurring availability windows")
              .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func lessonsWorkspace(_ workspace: SDWARWorkspace) -> some View {
    let sessions = filteredAppointments
    summaryGrid([
      ("Upcoming", workspace.appointments.filter { isFuture($0.warString("starts_at")) }.count, "calendar"),
      ("Arrived", workspace.appointments.filter { $0.warString("status") == "arrived" }.count, "checkmark.circle"),
      ("In session", workspace.appointments.filter { $0.warString("status") == "in_session" }.count, "figure.strengthtraining.traditional"),
      ("Completed", workspace.appointments.filter { $0.warString("status") == "completed" }.count, "checkmark.seal"),
    ])
    if sessions.isEmpty {
      HPCard {
        HPEmptyState(
          title: query.isEmpty ? "No sessions scheduled" : "No sessions match",
          message: query.isEmpty ? "Book a session using verified services, trainer availability, and shared facility resources." : "Try another service, trainer, or status.",
          systemImage: "calendar.badge.clock",
          actionTitle: "Book session",
          action: { activeSheet = .appointment }
        )
      }
    } else {
      ForEach(sessions, id: \.warRecordID) { appointment in appointmentCard(appointment, workspace: workspace) }
    }
  }

  private func appointmentCard(_ appointment: SDWARRecord, workspace: SDWARWorkspace) -> some View {
    let service = workspace.services.first { $0.warUUID("id") == appointment.warUUID("service_id") }
    let trainerId = appointment.warUUID("trainer_user_id")
    let trainer = workspace.profiles.first { $0.warUUID("id") == trainerId }
    let participantIds = workspace.participants
      .filter { $0.warUUID("appointment_id") == appointment.warUUID("id") }
      .compactMap { $0.warUUID("athlete_id") }
    let athleteNames = workspace.athletes
      .filter { athlete in participantIds.contains(where: { $0 == athlete.warUUID("id") }) }
      .map { $0.warDisplay("display_name") }
    return HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 4) {
            Text(service?.warDisplay("name", fallback: "Training session") ?? "Training session").font(HP.Font.headline)
            Text(formatDate(appointment.warString("starts_at"))).font(HP.Font.callout).foregroundStyle(HP.Color.textTertiary)
          }
          Spacer()
          HPStatusBadge(text: readable(appointment.warDisplay("status")), kind: statusKind(appointment.warString("status")))
        }
        Text(athleteNames.isEmpty ? "No athlete attached" : athleteNames.joined(separator: ", ")).font(HP.Font.callout)
        Text("Trainer: \(trainer?.warDisplay("full_name", fallback: "Unassigned") ?? "Unassigned")")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        if canManageAppointment(appointment), let appointmentId = appointment.warUUID("id") {
          Menu {
            ForEach(["confirmed", "arrived", "in_session", "completed"], id: \.self) { status in
              Button(readable(status)) { Task { await updateAppointment(appointmentId, status: status) } }
            }
            Button("Cancel", role: .destructive) { Task { await updateAppointment(appointmentId, status: "cancelled") } }
          } label: {
            Label("Update session", systemImage: "ellipsis.circle").font(HP.Font.callout.weight(.semibold))
          }
        }
      }
    }
  }

  @ViewBuilder
  private func testingWorkspace(_ workspace: SDWARWorkspace) -> some View {
    summaryGrid([
      ("Templates", workspace.testing_templates.count, "list.clipboard"),
      ("Draft sessions", workspace.testing_sessions.filter { $0.warString("status") == "draft" }.count, "pencil"),
      ("Finalized", workspace.testing_sessions.filter { $0.warString("status") == "finalized" }.count, "checkmark.seal"),
      ("Athlete results", workspace.testing_results.count, "chart.bar.doc.horizontal"),
    ])
    if workspace.testing_templates.isEmpty && workspace.testing_sessions.isEmpty {
      HPCard {
        HPEmptyState(
          title: "No WAR assessments yet",
          message: "Create a reusable hitting, pitching, strength, speed, mobility, recovery, or custom assessment.",
          systemImage: "testtube.2",
          actionTitle: workspace.isManager ? "Create template" : nil,
          action: workspace.isManager ? { activeSheet = .testingTemplate } : nil
        )
      }
    } else {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Assessment templates")
          ForEach(filteredTestingTemplates, id: \.warRecordID) { template in
            HStack {
              VStack(alignment: .leading, spacing: 3) {
                Text(template.warDisplay("name")).font(HP.Font.callout.weight(.semibold))
                Text(readable(template.warDisplay("category"))).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
              }
              Spacer()
              HPStatusBadge(text: template.warBool("active") ? "Active" : "Inactive", kind: template.warBool("active") ? .success : .neutral)
            }.padding(.vertical, 4)
          }
        }
      }
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Recent testing")
          if workspace.testing_sessions.isEmpty { Text("No sessions have been recorded.").foregroundStyle(HP.Color.textMuted) }
          ForEach(workspace.testing_sessions.prefix(20), id: \.warRecordID) { session in
            HStack {
              VStack(alignment: .leading, spacing: 3) {
                Text(session.warDisplay("title")).font(HP.Font.callout.weight(.semibold))
                Text(formatDate(session.warString("tested_at"))).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
              }
              Spacer()
              HPStatusBadge(text: readable(session.warDisplay("status")), kind: statusKind(session.warString("status")))
            }.padding(.vertical, 4)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func dataLabWorkspace(_ workspace: SDWARWorkspace) -> some View {
    summaryGrid([
      ("Athletes", workspace.athletes.count, "figure.run"),
      ("Source files", workspace.imports.count, "externaldrive"),
      ("Ready imports", workspace.imports.filter { $0.warString("status") == "completed" }.count, "checkmark.circle"),
      ("Models", dataLabModules.count, "chart.xyaxis.line"),
    ])
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Source coverage")
        if workspace.imports.isEmpty {
          HPEmptyState(
            title: "No provider files connected",
            message: "Upload Blast, Rapsodo, or 4D files from the web Data Lab. Unsupported models remain disabled without crashing this workspace.",
            systemImage: "externaldrive.badge.exclamationmark"
          )
        } else {
          ForEach(workspace.imports.prefix(30), id: \.warRecordID) { item in
            HStack(alignment: .top) {
              VStack(alignment: .leading, spacing: 3) {
                Text(item.warDisplay("file_name", fallback: "Provider import")).font(HP.Font.callout.weight(.semibold))
                Text("\(item.warDisplay("provider", fallback: "Unknown").capitalized) · \(item.warDisplay("model_version", fallback: "Version pending"))")
                  .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
              }
              Spacer()
              HPStatusBadge(text: readable(item.warDisplay("status")), kind: statusKind(item.warString("status")))
            }
          }
        }
      }
    }
    if model.isAnalyzing { HPCard { HPLoadingState(text: "Running versioned WAR models…") } }
    if let analysis = model.analytics { analyticsResults(analysis) }
  }

  @ViewBuilder
  private func analyticsResults(_ analysis: SDWARAnalyticsResponse) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader(readable(analysis.module)) { HPStatusBadge(text: analysis.model_version, kind: .info) }
        if analysis.summary_metrics.isEmpty {
          Text("No summary metrics were available for this file and model.").foregroundStyle(HP.Color.textMuted)
        }
        ForEach(Array(analysis.summary_metrics.enumerated()), id: \.offset) { _, metric in
          HStack {
            Text(metric.warDisplay("label", fallback: metric.warDisplay("name", fallback: "Metric")))
            Spacer()
            Text(metric.warDisplay("display_value", fallback: metric.warDisplay("value"))).font(HP.Font.callout.weight(.semibold))
          }
        }
        if let guidance = analysis.guidance.warString("summary").nilIfBlank
          ?? analysis.guidance.warString("what_this_means").nilIfBlank {
          Divider()
          Text("What this means").font(HP.Font.callout.weight(.semibold))
          Text(guidance).font(HP.Font.callout).foregroundStyle(HP.Color.textTertiary)
        }
      }
    }
    ForEach(analysis.tables.prefix(4)) { table in
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader(table.title) { HPStatusBadge(text: "\(table.rows.count) rows", kind: .neutral) }
          if let description = table.description { Text(description).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted) }
          ForEach(Array(table.rows.prefix(12).enumerated()), id: \.offset) { _, row in
            VStack(alignment: .leading, spacing: 3) {
              ForEach(table.columns.prefix(4), id: \.key) { column in
                HStack(alignment: .firstTextBaseline) {
                  Text(column.label).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
                  Spacer()
                  Text(row.warDisplay(column.key)).font(HP.Font.caption.weight(.semibold))
                }
              }
            }.padding(.vertical, 5)
          }
        }
      }
    }
  }

  private func summaryGrid(_ metrics: [(String, Int, String)]) -> some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: HP.Space.sm)], spacing: HP.Space.sm) {
      ForEach(metrics, id: \.0) { metric in
        HPCard {
          VStack(alignment: .leading, spacing: 6) {
            Image(systemName: metric.2).foregroundStyle(HP.Color.primary)
            Text("\(metric.1)").font(HP.Font.title)
            Text(metric.0).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }

  @ViewBuilder
  private func operationSheet(_ sheet: WAROperationsSheet) -> some View {
    switch sheet {
    case .athlete: WARAddAthleteSheet(model: model, appState: appState)
    case .appointment: WARBookSessionSheet(model: model, appState: appState)
    case .testingTemplate: WARTestingTemplateSheet(model: model, appState: appState)
    case .availability: WARAvailabilitySheet(model: model, appState: appState)
    }
  }

  private var canCreate: Bool {
    guard let workspace = model.workspace else { return false }
    switch mode {
    case .athletes, .testing: return workspace.isManager
    case .trainers: return workspace.isManager || workspace.access.warString("staff_kind") == "trainer"
    case .lessons: return !workspace.services.isEmpty
    case .dataLab: return false
    }
  }

  private var primaryActionTitle: String {
    switch mode {
    case .athletes: "Add athlete"
    case .trainers: "Add availability"
    case .lessons: "Book session"
    case .testing: "New template"
    case .dataLab: ""
    }
  }

  private var primarySheet: WAROperationsSheet {
    switch mode {
    case .athletes: .athlete
    case .trainers: .availability
    case .lessons: .appointment
    case .testing: .testingTemplate
    case .dataLab: .appointment
    }
  }

  private var filteredAthletes: [SDWARRecord] {
    let records = model.workspace?.athletes ?? []
    guard !query.isEmpty else { return records }
    return records.filter {
      $0.warString("display_name").localizedCaseInsensitiveContains(query)
        || $0.warString("invited_email").localizedCaseInsensitiveContains(query)
    }
  }

  private var filteredTrainers: [SDWARRecord] {
    guard let workspace = model.workspace else { return [] }
    let trainers = workspace.staff.filter { $0.warString("staff_kind") == "trainer" }
    guard !query.isEmpty else { return trainers }
    return trainers.filter { trainer in
      let id = trainer.warUUID("user_id")
      let profile = workspace.profiles.first { $0.warUUID("id") == id }
      let publicProfile = workspace.public_profiles.first { $0.warUUID("user_id") == id }
      return profile?.warString("full_name").localizedCaseInsensitiveContains(query) == true
        || publicProfile?.warString("display_name").localizedCaseInsensitiveContains(query) == true
        || publicProfile?.warString("specialties").localizedCaseInsensitiveContains(query) == true
    }
  }

  private var filteredAppointments: [SDWARRecord] {
    guard let workspace = model.workspace else { return [] }
    let sorted = workspace.appointments.sorted { $0.warString("starts_at") < $1.warString("starts_at") }
    guard !query.isEmpty else { return sorted }
    return sorted.filter { appointment in
      let service = workspace.services.first { $0.warUUID("id") == appointment.warUUID("service_id") }
      return service?.warString("name").localizedCaseInsensitiveContains(query) == true
        || appointment.warString("status").localizedCaseInsensitiveContains(query)
    }
  }

  private var filteredTestingTemplates: [SDWARRecord] {
    let templates = model.workspace?.testing_templates ?? []
    guard !query.isEmpty else { return templates }
    return templates.filter {
      $0.warString("name").localizedCaseInsensitiveContains(query)
        || $0.warString("category").localizedCaseInsensitiveContains(query)
    }
  }

  private var availableProviders: [String] {
    Array(Set((model.workspace?.imports ?? []).map { $0.warString("provider").lowercased() }.filter { !$0.isEmpty })).sorted()
  }

  private var resultCountLabel: String {
    let count: Int = switch mode {
    case .athletes: filteredAthletes.count
    case .trainers: filteredTrainers.count
    case .lessons: filteredAppointments.count
    case .testing: filteredTestingTemplates.count
    case .dataLab: 0
    }
    return "\(count) result\(count == 1 ? "" : "s")"
  }

  private func canManageAppointment(_ appointment: SDWARRecord) -> Bool {
    guard let workspace = model.workspace else { return false }
    return workspace.isManager || workspace.access.warUUID("caller_id") == appointment.warUUID("trainer_user_id")
  }

  private func reload() async {
    await model.load(service: appState.supabase, organizationId: appState.activeOrgId)
    if selectedAthleteId == nil { selectedAthleteId = model.workspace?.athletes.first?.warUUID("id") }
  }

  private func runAnalysis() async {
    await model.analyze(
      service: appState.supabase,
      organizationId: appState.activeOrgId,
      athleteId: selectedAthleteId,
      module: selectedDataLabModule,
      provider: selectedProvider.nilIfBlank
    )
  }

  private func updateAppointment(_ id: UUID, status: String) async {
    var payload: SDWARRecord = [
      "appointment_id": .string(id.uuidString.lowercased()),
      "status": .string(status),
    ]
    if status == "cancelled" { payload["cancellation_reason"] = .string("Cancelled by WAR staff") }
    _ = await model.mutate(
      service: appState.supabase,
      organizationId: appState.activeOrgId,
      action: "update_appointment",
      payload: payload,
      confirmation: "Session updated."
    )
  }
}

private struct WARAddAthleteSheet: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var model: WAROperationsWorkspaceModel
  let appState: AppState
  @State private var name = ""
  @State private var email = ""
  @State private var discipline = "baseball"

  var body: some View {
    NavigationStack {
      Form {
        TextField("Athlete name", text: $name)
        TextField("Email", text: $email)
          .textInputAutocapitalization(.never)
#if os(iOS)
          .keyboardType(.emailAddress)
#endif
        Picker("Primary discipline", selection: $discipline) {
          ForEach(["baseball", "hitting", "pitching", "strength", "speed"], id: \.self) { Text($0.capitalized).tag($0) }
        }
        Text("An athlete record can exist before the athlete creates a Home Plate account.")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
      }
      .navigationTitle("Add WAR Athlete")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create") { Task { await save() } }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSaving)
        }
      }
    }
  }

  private func save() async {
    let didSave = await model.mutate(
      service: appState.supabase,
      organizationId: appState.activeOrgId,
      action: "save_athlete",
      payload: ["athlete": .object([
        "display_name": .string(name),
        "invited_email": .string(email),
        "status": .string("invited"),
        "primary_discipline": .string(discipline),
      ])],
      confirmation: "Athlete added to WAR Performance."
    )
    if didSave { dismiss() }
  }
}

private struct WARBookSessionSheet: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var model: WAROperationsWorkspaceModel
  let appState: AppState
  @State private var athleteId: UUID?
  @State private var serviceId: UUID?
  @State private var trainerId: UUID?
  @State private var locationId: UUID?
  @State private var startsAt = Date().addingTimeInterval(3600)

  private var workspace: SDWARWorkspace? { model.workspace }

  var body: some View {
    NavigationStack {
      Form {
        Picker("Athlete", selection: $athleteId) {
          Text("Select").tag(UUID?.none)
          ForEach(workspace?.athletes ?? [], id: \.warRecordID) { Text($0.warDisplay("display_name")).tag($0.warUUID("id") as UUID?) }
        }
        Picker("Service", selection: $serviceId) {
          Text("Select").tag(UUID?.none)
          ForEach((workspace?.services ?? []).filter { $0.warBool("active") }, id: \.warRecordID) { Text($0.warDisplay("name")).tag($0.warUUID("id") as UUID?) }
        }
        Picker("Trainer", selection: $trainerId) {
          Text("Select").tag(UUID?.none)
          ForEach((workspace?.staff ?? []).filter { $0.warString("staff_kind") == "trainer" }, id: \.warRecordID) { trainer in
            let profile = workspace?.profiles.first { $0.warUUID("id") == trainer.warUUID("user_id") }
            Text(profile?.warDisplay("full_name", fallback: "Trainer") ?? "Trainer").tag(trainer.warUUID("user_id") as UUID?)
          }
        }
        Picker("Location", selection: $locationId) {
          Text("No location").tag(UUID?.none)
          ForEach(workspace?.locations ?? [], id: \.warRecordID) { Text($0.warDisplay("name")).tag($0.warUUID("id") as UUID?) }
        }
        DatePicker("Starts", selection: $startsAt)
        Text("Home Plate checks athlete, trainer, location, and resource conflicts transactionally before saving.")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
      }
      .navigationTitle("Book a Session")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Book") { Task { await save() } }
            .disabled(athleteId == nil || serviceId == nil || trainerId == nil || model.isSaving)
        }
      }
      .onAppear {
        athleteId = athleteId ?? workspace?.athletes.first?.warUUID("id")
        serviceId = serviceId ?? workspace?.services.first(where: { $0.warBool("active") })?.warUUID("id")
        trainerId = trainerId ?? workspace?.staff.first(where: { $0.warString("staff_kind") == "trainer" })?.warUUID("user_id")
        locationId = locationId ?? workspace?.locations.first?.warUUID("id")
      }
    }
  }

  private func save() async {
    guard let athleteId, let serviceId, let trainerId else { return }
    var payload: SDWARRecord = [
      "athlete_ids": .array([.string(athleteId.uuidString.lowercased())]),
      "service_id": .string(serviceId.uuidString.lowercased()),
      "trainer_user_id": .string(trainerId.uuidString.lowercased()),
      "starts_at": .string(ISO8601DateFormatter().string(from: startsAt)),
      "resource_ids": .array([]),
      "idempotency_key": .string(UUID().uuidString.lowercased()),
    ]
    if let locationId { payload["location_id"] = .string(locationId.uuidString.lowercased()) }
    let didSave = await model.mutate(
      service: appState.supabase,
      organizationId: appState.activeOrgId,
      action: "create_appointment",
      payload: payload,
      confirmation: "WAR session booked."
    )
    if didSave { dismiss() }
  }
}

private struct WARTestingTemplateSheet: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var model: WAROperationsWorkspaceModel
  let appState: AppState
  @State private var name = ""
  @State private var category = "hitting"
  @State private var fieldName = ""
  @State private var unit = ""
  @State private var familyReport = false

  var body: some View {
    NavigationStack {
      Form {
        TextField("Template name", text: $name)
        Picker("Category", selection: $category) {
          ForEach(["hitting", "pitching", "strength", "speed", "mobility", "recovery", "custom"], id: \.self) { Text($0.capitalized).tag($0) }
        }
        Section("First measurement") {
          TextField("Field label", text: $fieldName)
          TextField("Unit (optional)", text: $unit)
        }
        Toggle("Allow family report", isOn: $familyReport)
      }
      .navigationTitle("Assessment Template")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create") { Task { await save() } }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || fieldName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSaving)
        }
      }
    }
  }

  private func save() async {
    let key = fieldName.lowercased().replacingOccurrences(of: " ", with: "_")
    let didSave = await model.mutate(
      service: appState.supabase,
      organizationId: appState.activeOrgId,
      action: "save_testing_template",
      payload: ["template": .object([
        "name": .string(name),
        "category": .string(category),
        "family_report_enabled": .bool(familyReport),
        "active": .bool(true),
        "fields": .array([.object([
          "key": .string(key),
          "label": .string(fieldName),
          "type": .string("number"),
          "unit": unit.nilIfBlank.map(SDJSONValue.string) ?? .null,
        ])]),
      ])],
      confirmation: "Assessment template created."
    )
    if didSave { dismiss() }
  }
}

private struct WARAvailabilitySheet: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var model: WAROperationsWorkspaceModel
  let appState: AppState
  @State private var trainerId: UUID?
  @State private var locationId: UUID?
  @State private var weekday = 1
  @State private var startTime = DateComponents(calendar: .current, hour: 9).date ?? Date()
  @State private var endTime = DateComponents(calendar: .current, hour: 17).date ?? Date()

  var body: some View {
    NavigationStack {
      Form {
        Picker("Trainer", selection: $trainerId) {
          Text("Select").tag(UUID?.none)
          ForEach((model.workspace?.staff ?? []).filter { $0.warString("staff_kind") == "trainer" }, id: \.warRecordID) { trainer in
            let profile = model.workspace?.profiles.first { $0.warUUID("id") == trainer.warUUID("user_id") }
            Text(profile?.warDisplay("full_name", fallback: "Trainer") ?? "Trainer").tag(trainer.warUUID("user_id") as UUID?)
          }
        }
        Picker("Day", selection: $weekday) {
          ForEach(Array(Calendar.current.weekdaySymbols.enumerated()), id: \.offset) { index, name in Text(name).tag(index) }
        }
        DatePicker("Starts", selection: $startTime, displayedComponents: .hourAndMinute)
        DatePicker("Ends", selection: $endTime, displayedComponents: .hourAndMinute)
        Picker("Location", selection: $locationId) {
          Text("Any location").tag(UUID?.none)
          ForEach(model.workspace?.locations ?? [], id: \.warRecordID) { Text($0.warDisplay("name")).tag($0.warUUID("id") as UUID?) }
        }
      }
      .navigationTitle("Trainer Availability")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { Task { await save() } }.disabled(trainerId == nil || endTime <= startTime || model.isSaving)
        }
      }
      .onAppear {
        trainerId = trainerId ?? model.workspace?.access.warUUID("caller_id")
          ?? model.workspace?.staff.first(where: { $0.warString("staff_kind") == "trainer" })?.warUUID("user_id")
      }
    }
  }

  private func save() async {
    guard let trainerId else { return }
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    var availability: SDWARRecord = [
      "weekday": .int(weekday),
      "starts_at": .string(formatter.string(from: startTime)),
      "ends_at": .string(formatter.string(from: endTime)),
      "timezone": .string(TimeZone.current.identifier),
      "active": .bool(true),
    ]
    if let locationId { availability["location_id"] = .string(locationId.uuidString.lowercased()) }
    let didSave = await model.mutate(
      service: appState.supabase,
      organizationId: appState.activeOrgId,
      action: "save_availability",
      payload: [
        "trainer_user_id": .string(trainerId.uuidString.lowercased()),
        "availability": .object(availability),
      ],
      confirmation: "Trainer availability saved."
    )
    if didSave { dismiss() }
  }
}

private enum WARRecord {
  static func id(_ record: SDWARRecord) -> String {
    record.warString("id", fallback: "missing-id")
  }
}

private extension String {
  var nilIfBlank: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

private func readable(_ value: String) -> String {
  value.replacingOccurrences(of: "_", with: " ").capitalized
}

private func statusKind(_ value: String) -> HPStatusKind {
  switch value.lowercased() {
  case "active", "completed", "confirmed", "finalized", "ready": .success
  case "arrived", "in_session", "pending", "held", "draft", "invited": .warning
  case "cancelled", "failed", "archived", "inactive", "no_show": .danger
  default: .neutral
  }
}

private func formatDate(_ value: String) -> String {
  let formatter = ISO8601DateFormatter()
  guard let date = formatter.date(from: value) else { return value.nilIfBlank ?? "Date unavailable" }
  return date.formatted(date: .abbreviated, time: .shortened)
}

private func isFuture(_ value: String) -> Bool {
  guard let date = ISO8601DateFormatter().date(from: value) else { return false }
  return date >= Calendar.current.startOfDay(for: Date())
}
