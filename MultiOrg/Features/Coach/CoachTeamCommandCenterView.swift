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
  @State private var events: [SDTeamEvent] = []
  @State private var operations: [UUID: SDEventOperationSummary] = [:]
  @State private var practicePlans: [UUID: SDPracticePlanSummary] = [:]

  var body: some View {
    NavigationStack {
      HPWorkspaceScreenLayout {
        HPWorkspaceHeader("Today", orgLabel: organizationName, context: contextLabel) {
          CoachTeamSelector()
        }
      } attention: {
        HPCard {
          if attentionItems.isEmpty {
            HPEmptyState(title: "No mission attention items", message: "Today’s event details and initialized operations have no unresolved warnings.", systemImage: "checkmark.circle")
          } else {
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              HPSectionHeader("Mission attention") { HPStatusBadge(text: "\(attentionItems.count)", kind: .warning) }
              ForEach(Array(attentionItems.enumerated()), id: \.offset) { _, item in
                Label(item, systemImage: "exclamationmark.triangle")
                  .font(HP.Font.callout).foregroundStyle(HP.Color.text)
              }
            }
          }
        }
      } metrics: {
        if let team = appState.selectedTeam {
          HPMetricCard(title: "Players", value: "\(team.roster_count)", context: team.name)
          HPMetricCard(title: "Staff", value: "\(team.staff_count)", context: appState.selectedSeason?.name ?? "Season")
        }
      } supporting: {
        HPCard {
          if let team = appState.selectedTeam {
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              HPSectionHeader(team.name) {
                HPStatusBadge(text: appState.selectedSeason?.status.label ?? "Season", kind: .info)
              }
              Text(appState.selectedSeason?.name ?? "No active season")
                .font(HP.Font.callout).foregroundStyle(HP.Color.textMuted)
              if todayEvents.isEmpty {
                if let nextEvent {
                  HPEmptyState(title: "No event today", message: "The next published mission is \(nextEvent.title) on \(nextEvent.startDate.formatted(date: .abbreviated, time: .shortened)).", systemImage: "calendar")
                } else {
                  HPEmptyState(title: "No event today", message: "The team has no published event scheduled today or in the next 30 days.", systemImage: "calendar")
                }
              } else {
                ForEach(todayEvents) { event in
                  NavigationLink {
                    CoachEventOperationView(event: event, teamName: team.name)
                  } label: {
                    coachMissionRow(event, teamName: team.name)
                  }
                  .buttonStyle(.plain)
                }
              }
            }
          } else {
            noTeamState
          }
        }
      }
      .navigationTitle("Today")
      .task(id: appState.selectedTeamId) { await reloadEvents() }
      .refreshable { await appState.refreshTeamOperationsContext(); await reloadEvents() }
    }
  }

  private var contextLabel: String {
    appState.isAllTeamsSelected ? "All authorized teams" : appState.selectedTeam?.name ?? "Team assignment required"
  }

  private var organizationName: String {
    appState.availableOrganizations.first(where: { $0.id == appState.activeOrgId })?.displayName ?? "Home Plate"
  }

  private var noTeamState: some View {
    HPEmptyState(
      title: appState.isAllTeamsSelected ? "All Teams selected" : "No active team assignment",
      message: appState.isAllTeamsSelected
        ? "Choose Team for individual team operations."
        : "An organization administrator can assign a team from Organization settings.",
      systemImage: "person.3"
    )
  }

  private var todayEvents: [SDTeamEvent] {
    let calendar = Calendar.current
    return events.filter { calendar.isDateInToday($0.startDate) && $0.status != .draft && $0.status != .cancelled }
      .sorted { $0.startDate < $1.startDate }
  }

  private var incompleteEvents: [SDTeamEvent] {
    todayEvents.filter { ($0.location_name ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
  }

  private var nextEvent: SDTeamEvent? {
    events.first { $0.startDate > Date() && !Calendar.current.isDateInToday($0.startDate) && $0.status != .draft && $0.status != .cancelled }
  }

  private var attentionItems: [String] {
    var items = incompleteEvents.map { "\($0.title) needs a location" }
    for event in todayEvents {
      guard let operation = operations[event.id] else { continue }
      if operation.unresolved_availability > 0 {
        items.append("\(event.title) has \(operation.unresolved_availability) unresolved availability response(s)")
      }
      if event.event_type == .practice {
        switch practicePlans[event.id]?.status {
        case nil: items.append("\(event.title) has no practice plan")
        case .draft: items.append("\(event.title) practice plan is still a draft")
        case .ready: items.append("\(event.title) practice plan is not published")
        case .active: items.append("\(event.title) practice is active")
        default: break
        }
      }
      if operation.checklist_total > operation.checklist_completed {
        items.append("\(event.title) has \(operation.checklist_total - operation.checklist_completed) checklist item(s) remaining")
      }
    }
    return items
  }

  private func coachMissionRow(_ event: SDTeamEvent, teamName: String) -> some View {
    let operation = operations[event.id]
    return VStack(alignment: .leading, spacing: HP.Space.sm) {
      HStack {
        Label(event.event_type.label, systemImage: event.event_type.systemImage)
          .font(HP.Font.headline).foregroundStyle(HP.Color.text)
        Spacer()
        HPStatusBadge(text: operation?.status.label ?? "Not Prepared", kind: operation?.status == .completed ? .success : .info)
      }
      TeamEventRow(event: event, teamName: teamName)
      Text(missionPosition(event))
        .font(HP.Font.caption.weight(.semibold)).foregroundStyle(HP.Color.accent)
      if let operation {
        Text("\(operation.unresolved_availability) availability unresolved • \(operation.unrecorded_attendance) attendance not recorded • \(operation.checklist_completed)/\(operation.checklist_total) checklist")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
      }
      if event.event_type == .practice {
        Text("Practice plan: \(practicePlans[event.id]?.status.label ?? "No Plan")")
          .font(HP.Font.caption.weight(.semibold)).foregroundStyle(HP.Color.textMuted)
      }
      Label(primaryMissionAction(operation), systemImage: "arrow.right.circle.fill")
        .font(HP.Font.callout.weight(.semibold)).foregroundStyle(HP.Color.accent)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }

  private func missionPosition(_ event: SDTeamEvent) -> String {
    let now = Date()
    if event.startDate <= now && event.endDate >= now { return "Current mission" }
    if event.id == todayEvents.first(where: { $0.startDate > now })?.id { return "Next mission" }
    return event.startDate < now ? "Earlier today" : "Later today"
  }

  private func primaryMissionAction(_ operation: SDEventOperationSummary?) -> String {
    guard let operation else { return "Prepare" }
    switch operation.status {
    case .notStarted:
      return operation.unresolved_availability > 0 ? "Review Availability" : "Prepare"
    case .ready:
      if operation.operation_type == .gameDay { return "Start Game Day" }
      if operation.operation_type == .practiceDay { return "Start Practice" }
      return "Start Check-In"
    case .paused: return "Resume"
    case .inProgress: return "Complete Event"
    case .completed, .cancelled: return "Review Event"
    }
  }

  private func reloadEvents() async {
    guard let service = appState.supabase, let orgId = appState.activeOrgId else { events = []; return }
    let start = Calendar.current.startOfDay(for: Date())
    let end = Calendar.current.date(byAdding: .day, value: 30, to: start)!
    do {
      events = try await service.listTeamEvents(organizationId: orgId, teamId: appState.selectedTeam?.id, rangeStart: start, rangeEnd: end)
      if let team = appState.selectedTeam {
        do {
          let summaries = try await service.listEventOperations(
            organizationId: orgId,
            teamId: team.id,
            eventIds: events.map(\.id)
          )
          operations = Dictionary(uniqueKeysWithValues: summaries.map { ($0.event_id, $0) })
        } catch {
          operations = [:]
        }
        do {
          let plans = try await service.practicePlanSummaries(
            organizationId: orgId,
            seasonId: team.season_id,
            teamId: team.id
          )
          practicePlans = Dictionary(uniqueKeysWithValues: plans.map { ($0.event_id, $0) })
        } catch {
          practicePlans = [:]
        }
      } else {
        operations = [:]
        practicePlans = [:]
      }
    } catch {
      events = []
      operations = [:]
      practicePlans = [:]
    }
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
      .task(id: appState.selectedTeamId) { await reloadTeamEvents() }
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
    if appState.isAllTeamsSelected {
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
    do {
      teamEvents = try await service.listTeamEvents(
        organizationId: orgId,
        teamId: team.id,
        rangeStart: Calendar.current.date(byAdding: .day, value: -7, to: Date())!,
        rangeEnd: Calendar.current.date(byAdding: .day, value: 60, to: Date())!
      ).filter { $0.status != .cancelled }
      do {
        let operations = try await service.listEventOperations(
          organizationId: orgId,
          teamId: team.id,
          eventIds: teamEvents.map(\.id)
        )
        operationSummaries = Dictionary(uniqueKeysWithValues: operations.map { ($0.event_id, $0) })
      } catch {
        operationSummaries = [:]
      }
      do {
        let plans = try await service.practicePlanSummaries(
          organizationId: orgId,
          seasonId: team.season_id,
          teamId: team.id
        )
        practicePlanSummaries = Dictionary(uniqueKeysWithValues: plans.map { ($0.event_id, $0) })
      } catch {
        practicePlanSummaries = [:]
      }
    } catch {
      teamEvents = []
      operationSummaries = [:]
      practicePlanSummaries = [:]
    }
  }

  private func normalizeSection() {
    if !visibleSections.contains(section) { section = .overview }
  }
}
