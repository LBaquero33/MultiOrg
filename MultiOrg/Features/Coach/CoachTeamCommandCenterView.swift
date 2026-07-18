import SwiftUI

struct CoachTeamSelector: View {
  @EnvironmentObject private var appState: AppState

  var body: some View {
    if appState.authorizedCoachTeams.count > 1 {
      Menu {
        if appState.teamOperationsContext?.can_access_all_teams == true {
          Button { appState.selectCoachTeam(nil) } label: {
            Label("All Teams", systemImage: appState.isAllTeamsSelected ? "checkmark" : "person.3")
          }
          Divider()
        }
        ForEach(appState.authorizedCoachTeams) { team in
          Button { appState.selectCoachTeam(team.id) } label: {
            Label(team.name, systemImage: appState.selectedTeamId == team.id ? "checkmark" : "shield")
          }
        }
      } label: {
        HStack(spacing: HP.Space.xs) {
          Image(systemName: "shield.lefthalf.filled")
          Text(appState.isAllTeamsSelected ? "All Teams" : appState.selectedTeam?.name ?? "Select Team")
          Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold))
        }
        .font(HP.Font.callout.weight(.semibold))
        .foregroundStyle(HP.Color.accent)
        .frame(minHeight: 44)
      }
      .accessibilityLabel("Selected team")
    }
  }
}

struct CoachTodayFoundationView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.scenePhase) private var scenePhase
  @State private var today: SDTodayResponse?
  @State private var events: [SDTeamEvent] = []
  @State private var loadError: String?
  @State private var loadToken: UUID?
  @State private var publishedContext: String?

  var body: some View {
    NavigationStack {
      HPWorkspaceScreenLayout {
        HPWorkspaceHeader(screenTitle, orgLabel: organizationName, context: contextLabel) {
          if !isOwnerOverview { CoachTeamSelector() }
        }
      } attention: {
        topPriorityCard
      } metrics: {
        ForEach(today?.summaries ?? []) { summary in
          HPMetricCard(title: summary.label, value: summary.value, context: summary.status ?? "As of now")
        }
      } supporting: {
        missionSection
        attentionSection
        serviceStateSection
        if isOwnerOverview {
          if let organizationId = appState.activeOrgId {
            OrganizationSetupOverviewCard(
              organizationId: organizationId,
              organizationName: organizationName
            )
          }
          ownerOperationalLinks
        }
      }
      .navigationTitle(screenTitle)
      .task(id: todayContextIdentity) { await reloadToday() }
      .refreshable { await appState.refreshTeamOperationsContext(); await reloadToday() }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { Task { await reloadToday() } }
      }
    }
  }

  private var isOwnerOverview: Bool { appState.activeOrgMembership?.canAdministerOrganization == true }
  private var screenTitle: String { isOwnerOverview ? "Overview" : "Today" }

  private var contextLabel: String {
    if isOwnerOverview { return "Organization-wide • \(appState.selectedSeason?.name ?? "No active season")" }
    return appState.isAllTeamsSelected ? "All authorized teams" : appState.selectedTeam?.name ?? "Team assignment required"
  }

  private var organizationName: String {
    appState.availableOrganizations.first(where: { $0.id == appState.activeOrgId })?.displayName ?? "Home Plate"
  }

  @ViewBuilder private var topPriorityCard: some View {
    if let error = loadError, today == nil {
      HPCard { HPErrorState(title: "Today unavailable", message: error, onRetry: { Task { await reloadToday() } }) }
    } else if let primary = today?.primary_action {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader(isOwnerOverview ? "Top organization priority" : "Next action") { HPStatusBadge(text: "Priority", kind: .warning) }
          Text(primary.label).font(HP.Font.title).foregroundStyle(HP.Color.text)
          Text("This action uses the existing authorized workflow and current context.")
            .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
          primaryActionLink(primary)
        }
      }
    }
  }

  @ViewBuilder private func primaryActionLink(_ action: SDTodayAction) -> some View {
    if action.route == "event",
       let mission = today?.missions.first(where: { $0.primary_action?.id == action.id }),
       let event = events.first(where: { $0.id == mission.source_id }) {
      NavigationLink {
        CoachEventOperationView(event: event, teamName: mission.team_name ?? "Team")
      } label: { primaryActionLabel(action.label) }
    } else if action.route == "finance", let organizationId = appState.activeOrgId {
      NavigationLink {
        FinanceDashboardView(organizationId: organizationId, organizationName: organizationName, platformSupportMode: false)
      } label: { primaryActionLabel(action.label) }
    } else if action.route == "communication" {
      NavigationLink { ChatChannelListView() } label: { primaryActionLabel(action.label) }
    } else if action.route.hasPrefix("organization/") {
      NavigationLink { OrgAdminConsoleView() } label: { primaryActionLabel(action.label) }
    }
  }

  private func primaryActionLabel(_ label: String) -> some View {
    Label(label, systemImage: "arrow.right.circle.fill")
      .font(HP.Font.callout.weight(.semibold))
      .foregroundStyle(HP.Color.accent)
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
  }

  @ViewBuilder private var missionSection: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader(isOwnerOverview ? "Today’s Operations" : "Baseball missions") {
          HPStatusBadge(text: "\(todayMissions.count)", kind: todayMissions.isEmpty ? .neutral : .info)
        }
        if today == nil, loadError != nil {
          Label("Today’s schedule couldn’t be loaded.", systemImage: "wifi.exclamationmark")
            .font(HP.Font.caption).foregroundStyle(HP.Color.warning)
        } else if today?.service("scheduling").preservesAuthoritativeEmptyState == false {
          compactServiceState("scheduling", fallback: "Today’s schedule couldn’t be loaded.")
        } else if !isOwnerOverview && appState.selectedTeam == nil {
          HPEmptyState(title: "No active team assignment", message: "An organization administrator can assign a team. No team data is shown without an authorized assignment.", systemImage: "person.crop.circle.badge.exclamationmark")
        } else if displayedMissions.isEmpty {
          HPEmptyState(title: "No event today", message: isOwnerOverview ? "No organization event is scheduled today. Business and setup attention remains available below." : "No team mission is scheduled today. Upcoming preparation and attention remain available below.", systemImage: "calendar")
        } else {
          if todayMissions.isEmpty {
            Text("No event today • Next upcoming mission")
              .font(HP.Font.caption.weight(.semibold)).foregroundStyle(HP.Color.textMuted)
          }
          ForEach(displayedMissions) { mission in missionLink(mission) }
        }
      }
    }
  }

  @ViewBuilder private func missionLink(_ mission: SDTodayMission) -> some View {
    if let event = events.first(where: { $0.id == mission.source_id }) {
      NavigationLink {
        CoachEventOperationView(event: event, teamName: mission.team_name ?? "Team")
      } label: { missionRow(mission) }
      .buttonStyle(.plain)
    } else {
      missionRow(mission)
    }
  }

  private func missionRow(_ mission: SDTodayMission) -> some View {
    VStack(alignment: .leading, spacing: HP.Space.xs) {
      HStack {
        Text(mission.title).font(HP.Font.headline).foregroundStyle(HP.Color.text)
        Spacer()
        HPStatusBadge(text: mission.operation_state?.replacingOccurrences(of: "_", with: " ").capitalized ?? mission.status.capitalized, kind: mission.requires_review ? .warning : .info)
      }
      Text([mission.child_name, mission.team_name, mission.subtitle].compactMap { $0 }.joined(separator: " • "))
        .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
      if let arrival = mission.arrivalDate { Label("Arrive \(arrival.formatted(date: .omitted, time: .shortened))", systemImage: "figure.walk.arrival") }
      if let start = mission.startDate { Label("Starts \(start.formatted(date: .omitted, time: .shortened))", systemImage: "clock") }
      if let location = mission.location { Label(location, systemImage: "mappin") }
      if let plan = mission.plan_state { Text("Plan: \(plan.replacingOccurrences(of: "_", with: " ").capitalized)") }
      if let mode = mission.lineup_mode { Text("Lineup: \(mode.replacingOccurrences(of: "_", with: " ").capitalized)\(mission.eh_count.map { " • \($0) EH" } ?? "")") }
      if let availability = mission.availability_unresolved, let attendance = mission.attendance_unresolved {
        Text("\(availability) availability unresolved • \(attendance) attendance unresolved")
      }
      if let action = mission.primary_action {
        Label(action.label, systemImage: "arrow.right.circle.fill").font(HP.Font.callout.weight(.semibold)).foregroundStyle(HP.Color.accent)
      }
    }
    .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder private var attentionSection: some View {
    if let items = today?.attention_items, !items.isEmpty {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Attention") { HPStatusBadge(text: "\(items.count)", kind: .warning) }
          ForEach(items) { item in
            Label {
              VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(HP.Font.callout.weight(.semibold))
                if let detail = item.detail { Text(detail).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted) }
              }
            } icon: { Image(systemName: item.severity == .urgent ? "exclamationmark.triangle.fill" : "exclamationmark.circle") }
            .foregroundStyle(item.severity == .urgent ? HP.Color.danger : HP.Color.text)
          }
        }
      }
    }
  }

  @ViewBuilder private var serviceStateSection: some View {
    let failures = (today?.services ?? [:]).filter { ![.available, .unauthorized].contains($0.value.state) }
    if !failures.isEmpty || (loadError != nil && today != nil) {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Service status")
          if let loadError, today != nil {
            Label("Today couldn’t be refreshed. Previously loaded information remains visible. \(loadError)", systemImage: "clock.arrow.circlepath")
              .font(HP.Font.caption).foregroundStyle(HP.Color.warning)
          }
          ForEach(failures.keys.sorted(), id: \.self) { name in compactServiceState(name, fallback: "This section is temporarily unavailable.") }
          HPButton(title: "Retry unavailable sections", systemImage: "arrow.clockwise", variant: .secondary, size: .sm) { Task { await reloadToday() } }
        }
      }
    }
  }

  private func compactServiceState(_ name: String, fallback: String) -> some View {
    Label(today?.service(name).message ?? fallback, systemImage: "wifi.exclamationmark")
      .font(HP.Font.caption).foregroundStyle(HP.Color.warning)
      .accessibilityLabel(today?.service(name).message ?? fallback)
  }

  @ViewBuilder private var ownerOperationalLinks: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Open authoritative workspace")
        NavigationLink("Review Today’s Events") { OrgEventOperationsAdminView() }
        if let organizationId = appState.activeOrgId {
          NavigationLink("Review Receivables and Expenses") {
            FinanceDashboardView(organizationId: organizationId, organizationName: organizationName, platformSupportMode: false)
          }
        }
        NavigationLink("Open Communication") { ChatChannelListView() }
        NavigationLink("Registration and Organization Administration") { OrgAdminConsoleView() }
      }
      .font(HP.Font.callout.weight(.semibold)).foregroundStyle(HP.Color.accent)
    }
  }

  private var todayMissions: [SDTodayMission] {
    SDTodayMissionOrdering.ordered(today?.missions ?? []).filter { mission in
      guard let date = mission.startDate else { return false }
      var calendar = Calendar.current
      calendar.timeZone = TimeZone(identifier: today?.context.timezone ?? "") ?? .current
      return calendar.isDate(date, inSameDayAs: Date())
    }
  }

  private var displayedMissions: [SDTodayMission] {
    if !todayMissions.isEmpty { return todayMissions }
    return SDTodayMissionOrdering.ordered(today?.missions ?? []).filter { $0.startDate ?? .distantPast > Date() }.prefix(1).map { $0 }
  }

  private func reloadToday() async {
    guard let service = appState.supabase, let orgId = appState.activeOrgId else { today = nil; events = []; return }
    let context = todayContextIdentity
    if publishedContext != context {
      today = nil
      events = []
    }
    let token = UUID()
    loadToken = token
    loadError = nil
    do {
      let response = try await service.today(organizationId: orgId, seasonId: appState.selectedSeason?.id, teamId: isOwnerOverview ? nil : appState.selectedTeam?.id, contextToken: context)
      let start = Calendar.current.startOfDay(for: Date())
      let end = Calendar.current.date(byAdding: .day, value: 30, to: start) ?? start
      let routeEvents = try? await service.listTeamEvents(organizationId: orgId, seasonId: appState.selectedSeason?.id, teamId: isOwnerOverview ? nil : appState.selectedTeam?.id, rangeStart: start, rangeEnd: end)
      guard acceptsToday(context: context, token: token) else { return }
      guard response.context.organization_id == orgId,
            isOwnerOverview || response.context.team_id == appState.selectedTeam?.id else { return }
      today = response
      events = routeEvents ?? []
      publishedContext = context
    } catch {
      guard acceptsToday(context: context, token: token) else { return }
      guard let message = SDApplicationErrorClassifier.alertMessage(for: error) else { return }
      loadError = message
    }
  }

  private var todayContextIdentity: String {
    "\(appState.activeOrgAuthorizationKey):\(appState.selectedSeason?.id.uuidString ?? "none"):\(isOwnerOverview ? "organization" : appState.selectedTeamId?.uuidString ?? "none"):\(DateUtils.toISODate(Date())):\(TimeZone.current.identifier)"
  }

  private func acceptsToday(context: String, token: UUID) -> Bool {
    SDAsyncRequestGuard.accepts(
      responseContext: context,
      responseToken: token,
      activeContext: todayContextIdentity,
      currentToken: loadToken,
      taskIsCancelled: Task.isCancelled
    )
  }
}

struct CoachScheduleFoundationView: View {
  var body: some View {
    CoachTeamScheduleView()
  }
}

struct CoachTeamCommandCenterView: View {
  @EnvironmentObject private var appState: AppState
  @State private var section: Section = .overview
  @State private var teamEvents: [SDTeamEvent] = []
  @State private var operationSummaries: [UUID: SDEventOperationSummary] = [:]
  @State private var practicePlanSummaries: [UUID: SDPracticePlanSummary] = [:]
  @State private var gamePlanSummaries: [UUID: SDGamePlanSummary] = [:]
  @State private var loadError: String?
  @State private var loadToken: UUID?

  enum Section: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case players = "Players"
    case schedule = "Schedule"
    case development = "Development"
    case communication = "Communication"
    case staff = "Staff"
    case documents = "Documents"
    case settings = "Settings"
    var id: String { rawValue }
  }

  var body: some View {
    NavigationStack {
      HPListScreenLayout {
        HPWorkspaceHeader(
          "Team",
          orgLabel: appState.selectedSeason?.name ?? "Season",
          context: appState.isAllTeamsSelected ? "All authorized teams" : appState.selectedTeam?.name ?? "Team assignment required"
        ) { CoachTeamSelector() }
      } controls: {
        if appState.selectedTeam != nil {
          HPCard {
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: HP.Space.xs) {
                ForEach(visibleSections) { item in
                  HPButton(
                    title: item.rawValue,
                    variant: section == item ? .primary : .secondary,
                    size: .sm,
                    action: { section = item }
                  )
                }
              }
            }
          }
        }
      } results: { _ in
        content
      }
      .navigationTitle("Team")
      .refreshable { await appState.refreshTeamOperationsContext() }
      .onChange(of: appState.selectedTeamId) { _, _ in normalizeSection() }
      .onChange(of: appState.isAllTeamsSelected) { _, _ in normalizeSection() }
      .task(id: teamContextIdentity) { await reloadTeamEvents() }
    }
  }

  private var visibleSections: [Section] {
    guard let team = appState.selectedTeam else { return [.overview] }
    let capabilities = team.capabilitySet
    return Section.allCases.filter { item in
      switch item {
      case .overview, .players: capabilities.contains(.viewTeam)
      case .schedule: capabilities.contains(.viewTeamSchedule)
      case .development: capabilities.contains(.viewDevelopment)
      case .communication: capabilities.contains(.messageTeam)
      case .staff, .settings: capabilities.contains(.manageStaff)
      case .documents: capabilities.contains(.viewDocuments)
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    if let loadError {
      HPCard {
        HPErrorState(
          title: "Team unavailable",
          message: loadError,
          onRetry: { Task { await reloadTeamEvents() } }
        )
      }
    } else if appState.isAllTeamsSelected {
      allTeamsOverview
    } else if let team = appState.selectedTeam {
      switch section {
      case .overview: overview(team)
      case .players: peopleCard(title: "Players", people: appState.teamOperationsContext?.players(for: team.id) ?? [])
      case .staff: peopleCard(title: "Assigned Staff", people: appState.teamOperationsContext?.staff(for: team.id) ?? [])
      case .schedule: scheduleCard(team)
      case .development: placeholder("Development", "Player development tools are available through authorized player profiles.", "chart.line.uptrend.xyaxis")
      case .communication: placeholder("Communication", "Team-scoped communication will use this authorized roster.", "bubble.left.and.bubble.right")
      case .documents: placeholder("Documents", "Team documents will appear here when added.", "doc")
      case .settings: placeholder("Settings", "Team settings are managed by authorized staff.", "gearshape")
      }
    } else {
      HPCard {
        HPEmptyState(
          title: "No active team assignment",
          message: "An organization administrator can assign this coach to a team.",
          systemImage: "person.crop.circle.badge.exclamationmark"
        )
      }
    }
  }

  private var allTeamsOverview: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("All Teams") {
          HPStatusBadge(text: "\(appState.authorizedCoachTeams.count)", kind: .neutral)
        }
        ForEach(appState.authorizedCoachTeams) { team in
          Button { appState.selectCoachTeam(team.id) } label: {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(team.name).font(HP.Font.headline).foregroundStyle(HP.Color.text)
                Text("\(team.roster_count) players • \(team.staff_count) staff")
                  .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
              }
              Spacer()
              Image(systemName: "chevron.right").foregroundStyle(HP.Color.textMuted)
            }
            .frame(minHeight: 44)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private func overview(_ team: SDTeamOperationsTeam) -> some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader(team.name) {
            HPStatusBadge(text: appState.selectedSeason?.status.label ?? "Season", kind: .info)
          }
          Text(appState.selectedSeason?.name ?? "No active season")
            .font(HP.Font.callout).foregroundStyle(HP.Color.textMuted)
          Text("\(team.roster_count) players • \(team.staff_count) assigned staff")
            .font(HP.Font.body).foregroundStyle(HP.Color.text)
        }
      }
      HPCard {
        if let next = teamEvents.first(where: { $0.startDate >= Date() && $0.status != .draft && $0.status != .cancelled }) {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Next Event") { HPStatusBadge(text: next.event_type.label, kind: .info) }
            TeamEventRow(event: next, teamName: team.name)
            if next.event_type == .practice {
              Text("Plan readiness: \(practicePlanSummaries[next.id]?.status.label ?? "No Plan")")
                .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            }
            if next.event_type == .game {
              let gamePlan = gamePlanSummaries[next.id]
              Text("Game readiness: \(gamePlan?.status.label ?? "No Plan") • \(gamePlan?.lineup_mode.label ?? "Lineup not started")")
                .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            }
          }
        } else {
          HPEmptyState(title: "No upcoming event", message: "Published team schedule items will appear here.", systemImage: "calendar")
        }
      }
      HPCard {
        if let today = teamEvents.first(where: { Calendar.current.isDateInToday($0.startDate) && $0.status != .draft && $0.status != .cancelled }) {
          let operation = operationSummaries[today.id]
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Today’s Mission") {
              HPStatusBadge(text: operation?.status.label ?? "Not Prepared", kind: operation?.status == .completed ? .success : .info)
            }
            TeamEventRow(event: today, teamName: team.name)
            if today.event_type == .practice {
              Text("Practice plan: \(practicePlanSummaries[today.id]?.status.label ?? "No Plan")")
                .font(HP.Font.caption.weight(.semibold)).foregroundStyle(HP.Color.textMuted)
            }
            if today.event_type == .game {
              let gamePlan = gamePlanSummaries[today.id]
              Text("Game plan: \(gamePlan?.status.label ?? "No Plan") • \(gamePlan?.lineup_mode.label ?? "Lineup not started")")
                .font(HP.Font.caption.weight(.semibold)).foregroundStyle(HP.Color.textMuted)
            }
            Text("\(operation?.unresolved_availability ?? 0) unresolved availability • \(operation?.unrecorded_attendance ?? 0) attendance remaining • \(operation?.checklist_completed ?? 0)/\(operation?.checklist_total ?? 0) checklist")
              .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            if team.capabilitySet.contains(.viewEventOperation) {
              NavigationLink {
                CoachEventOperationView(event: today, teamName: team.name)
              } label: {
                Label(operation?.status == .completed ? "Review Event" : operation?.status == .paused ? "Resume" : "Open Mission", systemImage: "arrow.right.circle.fill")
                  .font(HP.Font.callout.weight(.semibold)).frame(minHeight: 44)
              }
            }
          }
        } else {
          HPEmptyState(title: "No mission today", message: "Day-of operations appear here when a canonical event is scheduled.", systemImage: "baseball.diamond.bases")
        }
      }
      if let completed = teamEvents.last(where: { operationSummaries[$0.id]?.status == .completed }) {
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Recently Completed") { HPStatusBadge(text: "Completed", kind: .success) }
            TeamEventRow(event: completed, teamName: team.name)
          }
        }
      }
    }
  }

  private func peopleCard(title: String, people: [Profile]) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader(title) { HPStatusBadge(text: "\(people.count)", kind: .neutral) }
        if people.isEmpty {
          HPEmptyState(title: "No \(title.lowercased())", message: "No active assignments are available.", systemImage: "person.2")
        } else {
          ForEach(people) { person in
            HStack(spacing: HP.Space.sm) {
              HPAvatar(name: person.displayName, size: .sm)
              Text(person.displayName).font(HP.Font.callout.weight(.semibold)).foregroundStyle(HP.Color.text)
              Spacer()
            }
            .frame(minHeight: 44)
          }
        }
      }
    }
  }

  private func placeholder(_ title: String, _ message: String, _ image: String) -> some View {
    HPCard { HPEmptyState(title: title, message: message, systemImage: image) }
  }

  private func scheduleCard(_ team: SDTeamOperationsTeam) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Upcoming Schedule") { HPStatusBadge(text: "\(teamEvents.count)", kind: .neutral) }
        if teamEvents.isEmpty {
          HPEmptyState(title: "No upcoming events", message: "Create events from Schedule.", systemImage: "calendar")
        } else {
          ForEach(teamEvents.prefix(5)) { TeamEventRow(event: $0, teamName: team.name) }
        }
      }
    }
  }

  private func reloadTeamEvents() async {
    guard let service = appState.supabase, let orgId = appState.activeOrgId, let team = appState.selectedTeam else { teamEvents = []; return }
    let context = teamContextIdentity
    let token = UUID()
    loadToken = token
    loadError = nil
    do {
      let loadedEvents = try await service.listTeamEvents(
        organizationId: orgId,
        teamId: team.id,
        rangeStart: Calendar.current.date(byAdding: .day, value: -7, to: Date())!,
        rangeEnd: Calendar.current.date(byAdding: .day, value: 60, to: Date())!
      ).filter { $0.status != .cancelled }
      let operations = try await service.listEventOperations(
        organizationId: orgId,
        teamId: team.id,
        eventIds: loadedEvents.map(\.id)
      )
      let plans = try await service.practicePlanSummaries(
        organizationId: orgId,
        seasonId: team.season_id,
        teamId: team.id
      )
      let games = try await service.gamePlanSummaries(
        organizationId: orgId,
        seasonId: team.season_id,
        teamId: team.id
      )
      guard acceptsTeam(context: context, token: token) else { return }
      teamEvents = loadedEvents
      operationSummaries = Dictionary(uniqueKeysWithValues: operations.map { ($0.event_id, $0) })
      practicePlanSummaries = Dictionary(uniqueKeysWithValues: plans.map { ($0.event_id, $0) })
      gamePlanSummaries = Dictionary(uniqueKeysWithValues: games.map { ($0.event_id, $0) })
    } catch {
      guard acceptsTeam(context: context, token: token) else { return }
      loadError = SDApplicationErrorClassifier.alertMessage(for: error)
    }
  }

  private var teamContextIdentity: String {
    "\(appState.activeOrgId?.uuidString ?? "none"):\(appState.selectedTeamId?.uuidString ?? "none")"
  }

  private func acceptsTeam(context: String, token: UUID) -> Bool {
    SDAsyncRequestGuard.accepts(
      responseContext: context,
      responseToken: token,
      activeContext: teamContextIdentity,
      currentToken: loadToken,
      taskIsCancelled: Task.isCancelled
    )
  }

  private func normalizeSection() {
    if !visibleSections.contains(section) { section = .overview }
  }
}
