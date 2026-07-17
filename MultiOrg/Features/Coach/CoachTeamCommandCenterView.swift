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

  var body: some View {
    NavigationStack {
      HPWorkspaceScreenLayout {
        HPWorkspaceHeader("Today", orgLabel: organizationName, context: contextLabel) {
          CoachTeamSelector()
        }
      } attention: {
        HPCard {
          HPEmptyState(
            title: "No team attention items",
            message: "Attendance, practice, and game attention will appear here as team operations are scheduled.",
            systemImage: "checkmark.circle"
          )
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
              Text("The next scheduled team item will appear here when one is available.")
                .font(HP.Font.body).foregroundStyle(HP.Color.text)
            }
          } else {
            noTeamState
          }
        }
      }
      .navigationTitle("Today")
      .refreshable { await appState.refreshTeamOperationsContext() }
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
}

struct CoachScheduleFoundationView: View {
  @EnvironmentObject private var appState: AppState

  var body: some View {
    NavigationStack {
      HPListScreenLayout {
        HPWorkspaceHeader(
          "Schedule",
          orgLabel: appState.selectedSeason?.name ?? "Season",
          context: appState.isAllTeamsSelected ? "All authorized teams" : appState.selectedTeam?.name ?? "Team assignment required"
        ) { CoachTeamSelector() }
      } controls: {
        EmptyView()
      } results: { _ in
        HPCard {
          HPEmptyState(
            title: "Team schedule foundation ready",
            message: "Existing team events will appear here as scheduling is connected. Full scheduling is outside Phase 12A.",
            systemImage: "calendar"
          )
        }
      }
      .navigationTitle("Schedule")
      .refreshable { await appState.refreshTeamOperationsContext() }
    }
  }
}

struct CoachTeamCommandCenterView: View {
  @EnvironmentObject private var appState: AppState
  @State private var section: Section = .overview

  enum Section: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case players = "Players"
    case schedule = "Schedule"
    case development = "Development"
    case attendance = "Attendance"
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
    }
  }

  private var visibleSections: [Section] {
    guard let team = appState.selectedTeam else { return [.overview] }
    let capabilities = team.capabilitySet
    return Section.allCases.filter { item in
      switch item {
      case .overview, .players, .schedule: capabilities.contains(.viewTeam)
      case .development: capabilities.contains(.viewDevelopment)
      case .attendance: capabilities.contains(.manageAttendance)
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
      case .schedule: placeholder("Schedule", "Scheduled team operations will appear here.", "calendar")
      case .development: placeholder("Development", "Player development tools are available through authorized player profiles.", "chart.line.uptrend.xyaxis")
      case .attendance: placeholder("Attendance", "Attendance operations will use this team context.", "checklist")
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
        HPEmptyState(
          title: "No recent team activity",
          message: "Authorized team operations will appear here as they occur.",
          systemImage: "clock.arrow.circlepath"
        )
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

  private func normalizeSection() {
    if !visibleSections.contains(section) { section = .overview }
  }
}
