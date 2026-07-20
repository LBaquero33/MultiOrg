import SwiftUI

struct OrgTeamOperationsAdminView: View {
  enum LaunchAction: Equatable {
    case createTeam
    case createSeason
  }

  @EnvironmentObject private var appState: AppState
  @State private var context: SDTeamOperationsContext?
  @State private var seasonName = ""
  @State private var seasonStart = Date()
  @State private var seasonEnd = Date()
  @State private var hasSeasonStart = false
  @State private var hasSeasonEnd = false
  @State private var seasonStatus: SDSeasonLifecycle = .planning
  @State private var seasonIsDefault = false
  @State private var editingSeasonId: UUID?
  @State private var newTeamName = ""
  @State private var newTeamSeasonId: UUID?
  @State private var teamAgeGroup = ""
  @State private var teamCompetitiveLevel = ""
  @State private var teamRosterCapacity = ""
  @State private var teamDescription = ""
  @State private var editingTeamId: UUID?
  @State private var teamRequestId = UUID()
  @State private var selectedCoachId: UUID?
  @State private var selectedCoachTeamId: UUID?
  @State private var selectedResponsibilities: Set<SDTeamResponsibility> = [.readOnly]
  @State private var coachPrimary = false
  @State private var coachAllTeams = false
  @State private var isInitialLoading = false
  @State private var activeMutations: Set<Mutation> = []
  @State private var loadErrorText: String?
  @State private var operationErrorText: String?
  @State private var seasonErrorText: String?
  @State private var seasonRequestId = UUID()
  @State private var loadRequestToken: UUID?
  @State private var rosterQuery = ""
  @State private var optimisticTeamByPlayer: [UUID: UUID] = [:]
  @State private var optimisticUnassignedPlayers: Set<UUID> = []
  @State private var rosterDropTarget: String?
  @State private var selectedTeamId: UUID?
  @State private var selectedSeasonId: UUID?
  @State private var workspaceSection: WorkspaceSection = .teams
  @State private var teamFilter: TeamFilter = .active
  @State private var detailMode: DetailMode = .summary
  @State private var isShowingSeasonEditor = false
  @State private var isShowingTeamEditor = false
  @State private var confirmationText: String?
  let embedded: Bool
  let launchAction: LaunchAction?
  let onLaunchActionHandled: () -> Void

  init(
    embedded: Bool = false,
    launchAction: LaunchAction? = nil,
    onLaunchActionHandled: @escaping () -> Void = {}
  ) {
    self.embedded = embedded
    self.launchAction = launchAction
    self.onLaunchActionHandled = onLaunchActionHandled
  }

  private enum Mutation: Hashable {
    case season, team, teamSeason, player, coach
  }

  private enum WorkspaceSection: String, CaseIterable, Identifiable {
    case teams = "Teams"
    case seasons = "Seasons"
    var id: String { rawValue }
  }

  private enum TeamFilter: String, CaseIterable, Identifiable {
    case active = "Active"
    case archived = "Archived"
    case all = "All Seasons"
    var id: String { rawValue }
  }

  private enum DetailMode: String {
    case summary, roster, staff
  }

  var body: some View {
    Group {
      if embedded {
        pageContent
      } else {
        HPScreenScaffold { _ in pageContent }
      }
    }
    .task(id: appState.activeOrgId) { await reload() }
    .task(id: launchAction) {
      guard let launchAction else { return }
      switch launchAction {
      case .createTeam: beginCreatingTeam()
      case .createSeason: beginCreatingSeason()
      }
      onLaunchActionHandled()
    }
    .sheet(isPresented: $isShowingSeasonEditor) { seasonEditorSheet }
    .sheet(isPresented: $isShowingTeamEditor) { teamEditorSheet }
    .hpToast($confirmationText)
    .accessibilityElement(children: .contain)
  }

  private var pageContent: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      if !embedded {
        HPWorkspaceHeader(
          "Team Management",
          orgLabel: organizationName,
          context: organizationContext
        )
      }
      if isInitialLoading, context == nil {
        HPCard { HPLoadingState(text: "Loading teams and seasons…") }
      }
      if let loadErrorText {
        HPCard {
          HPErrorState(
            title: "Teams and seasons couldn’t be loaded.",
            message: loadErrorText,
            onRetry: { Task { await reload() } }
          )
        }
      }
      teamsAndSeasonsWorkspace
      if let operationErrorText {
        HPCard {
          HPErrorState(
            title: "The update couldn’t be completed.",
            message: operationErrorText
          )
        }
      }
    }
  }

  private var organizationName: String {
    appState.availableOrganizations.first(where: { $0.id == appState.activeOrgId })?.name
      ?? appState.activeOrgSettings?.display_name
      ?? appState.activeOrgSettings?.short_name
      ?? "Organization"
  }

  private var organizationContext: String {
    if let season = context?.activeSeason?.name {
      return "Manage teams, rosters, and staff · \(season)"
    }
    return "Manage teams, rosters, and staff"
  }

  private var activeTeams: [SDTeamOperationsTeam] { context?.teams.filter(\.is_active) ?? [] }
  private var coaches: [Profile] { context?.people.filter(\.isCoach) ?? [] }
  private var players: [Profile] { context?.people.filter(\.isPlayer) ?? [] }

  private var teamsAndSeasonsWorkspace: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      HPCard {
        HStack(spacing: HP.Space.sm) {
          Picker("Management area", selection: $workspaceSection) {
            ForEach(WorkspaceSection.allCases) { section in Text(section.rawValue).tag(section) }
          }
          .pickerStyle(.segmented)
          .accessibilityLabel("Teams and seasons area")
          Spacer(minLength: HP.Space.sm)
          if workspaceSection == .teams {
            HPButton(title: "Create Team", systemImage: "plus", variant: .primary, size: .sm) {
              beginCreatingTeam()
            }
          } else {
            HPButton(title: "Create Season", systemImage: "plus", variant: .primary, size: .sm) {
              beginCreatingSeason()
            }
          }
        }
      }

      if workspaceSection == .teams {
        teamsWorkspace
        if detailMode == .roster { playerAssignmentsCard }
        if detailMode == .staff { coachAssignmentsCard }
      } else {
        seasonsWorkspace
      }
    }
  }

  private var teamsWorkspace: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      HPCard {
        Picker("Team filter", selection: $teamFilter) {
          ForEach(TeamFilter.allCases) { filter in Text(filter.rawValue).tag(filter) }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Team filter")
      }
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: HP.Space.md) {
          teamList
            .frame(minWidth: 270, idealWidth: 320, maxWidth: 360, alignment: .topLeading)
          teamDetail
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        VStack(alignment: .leading, spacing: HP.Space.md) {
          teamList
          teamDetail
        }
      }
    }
  }

  private var teamList: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.xs) {
        HPSectionHeader("Teams") {
          HPStatusBadge(text: "\(filteredTeams.count)", kind: .neutral)
        }
        if filteredTeams.isEmpty {
          HPEmptyState(
            title: teamFilter == .archived ? "No archived teams" : "No teams yet",
            message: teamFilter == .archived
              ? "Archived teams will appear here."
              : "Create a team when you are ready to organize players and staff.",
            systemImage: "person.3"
          )
        } else {
          ForEach(filteredTeams) { team in
            Button {
              selectedTeamId = team.id
              detailMode = .summary
            } label: {
              HStack(spacing: HP.Space.sm) {
                VStack(alignment: .leading, spacing: 3) {
                  Text(team.name).font(HP.Font.callout.weight(.semibold))
                  Text(teamListSubtitle(team))
                    .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
                    .lineLimit(1)
                  Text("\(team.roster_count) players • \(team.staff_count) staff")
                    .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
                }
                Spacer(minLength: HP.Space.xs)
                if !team.is_active { HPStatusBadge(text: "Archived", kind: .neutral) }
                Image(systemName: "chevron.right")
                  .foregroundStyle(HP.Color.textMuted)
                  .accessibilityHidden(true)
              }
              .padding(HP.Space.xs)
              .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
              .background(
                RoundedRectangle(cornerRadius: HP.Radius.sm)
                  .fill(selectedTeamId == team.id ? HP.Color.accent.opacity(0.12) : .clear)
              )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select \(team.name)")
          }
        }
      }
    }
  }

  @ViewBuilder
  private var teamDetail: some View {
    if let team = selectedTeam {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.md) {
          HStack(alignment: .top, spacing: HP.Space.sm) {
            VStack(alignment: .leading, spacing: 3) {
              Text(team.name).font(HP.Font.title).foregroundStyle(HP.Color.text)
              Text(team.is_active ? "Active team" : "Archived team")
                .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            }
            Spacer()
            HPStatusBadge(text: team.is_active ? "Active" : "Archived", kind: team.is_active ? .success : .neutral)
          }
          teamDetailRow("Season", value: seasonName(for: team.season_id))
          teamDetailRow("Age group", value: team.age_group ?? "Not set")
          teamDetailRow("Level", value: team.competitive_level ?? "Not set")
          teamDetailRow("Roster", value: "\(team.roster_count) players")
          teamDetailRow("Staff", value: "\(team.staff_count) assigned")
          teamDetailRow("Next event", value: "Open Schedule to review")
          Divider().overlay(HP.Color.border)
          ViewThatFits(in: .horizontal) {
            HStack(spacing: HP.Space.xs) { teamDetailActions(team) }
            VStack(alignment: .leading, spacing: HP.Space.xs) { teamDetailActions(team) }
          }
        }
      }
    } else {
      HPCard {
        HPEmptyState(
          title: "Select a team",
          message: "Choose a team to review its season, roster, staff, and shortcuts.",
          systemImage: "person.3"
        )
      }
    }
  }

  @ViewBuilder
  private func teamDetailActions(_ team: SDTeamOperationsTeam) -> some View {
    NavigationLink {
      CoachTeamCommandCenterView()
        .onAppear { appState.selectCoachTeam(team.id) }
    } label: {
      Label("Open Current Team", systemImage: "arrow.up.right.square")
        .frame(minHeight: 36)
    }
    .buttonStyle(.borderedProminent)
    Button("Manage Roster") { detailMode = .roster }
      .buttonStyle(.bordered)
    Button("Manage Staff") { detailMode = .staff }
      .buttonStyle(.bordered)
    NavigationLink {
      CoachTeamScheduleView()
        .onAppear { appState.selectCoachTeam(team.id) }
    } label: {
      Label("View Schedule", systemImage: "calendar")
        .frame(minHeight: 36)
    }
    .buttonStyle(.bordered)
    Menu {
      Button("Edit Team") { beginEditing(team) }
      if team.is_active {
        Button("Archive Team", role: .destructive) { Task { await archive(team) } }
      }
    } label: {
      Label("More", systemImage: "ellipsis.circle")
        .frame(minHeight: 36)
    }
  }

  private func teamDetailRow(_ label: String, value: String) -> some View {
    HStack(spacing: HP.Space.sm) {
      Text(label).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
      Spacer()
      Text(value).font(HP.Font.callout.weight(.semibold)).foregroundStyle(HP.Color.text)
    }
    .frame(minHeight: 32)
  }

  private var filteredTeams: [SDTeamOperationsTeam] {
    let teams = context?.teams ?? []
    switch teamFilter {
    case .active: return teams.filter(\.is_active)
    case .archived: return teams.filter { !$0.is_active }
    case .all: return teams
    }
  }

  private var selectedTeam: SDTeamOperationsTeam? {
    if let selectedTeamId,
       let team = context?.teams.first(where: { $0.id == selectedTeamId }) {
      return team
    }
    return filteredTeams.first
  }

  private func teamListSubtitle(_ team: SDTeamOperationsTeam) -> String {
    [seasonName(for: team.season_id), team.age_group, team.competitive_level]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
      .joined(separator: " • ")
  }

  private var seasonsWorkspace: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Seasons") {
          HPStatusBadge(text: "\(context?.seasons.count ?? 0)", kind: .neutral)
        }
        Text("Create seasons to organize teams, schedules, and registration.")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        if context?.seasons.isEmpty != false {
          HPEmptyState(
            title: "No seasons yet",
            message: "Create a season before adding teams.",
            systemImage: "calendar"
          )
        } else {
          ForEach(context?.seasons ?? []) { season in
            HStack(spacing: HP.Space.sm) {
              VStack(alignment: .leading, spacing: 2) {
                Text(season.name).font(HP.Font.callout.weight(.semibold))
                Text(seasonDateSummary(season))
                  .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
              }
              Spacer()
              if season.is_default { HPStatusBadge(text: "Default", kind: .success) }
              HPStatusBadge(text: season.status.label, kind: season.status == .archived ? .neutral : .info)
              Menu {
                Button("Edit") { beginEditing(season) }
                if !season.is_default {
                  Button("Set Default") { Task { await setDefault(season) } }
                }
                if season.status != .archived {
                  Button("Archive", role: .destructive) { Task { await archive(season) } }
                }
              } label: {
                Image(systemName: "ellipsis.circle").frame(width: 36, height: 36)
              }
              .menuStyle(.borderlessButton)
              .accessibilityLabel("Actions for \(season.name)")
            }
            .frame(minHeight: 52)
            Divider().overlay(HP.Color.border.opacity(0.5))
          }
        }
      }
    }
  }

  private func seasonDateSummary(_ season: SDSeason) -> String {
    let dates = [season.start_date, season.end_date].compactMap { $0 }
    return dates.isEmpty ? "Dates not set" : dates.joined(separator: " – ")
  }

  private var seasonEditorSheet: some View {
    NavigationStack {
      Form {
        Section("Season details") {
          TextField("Season name", text: $seasonName, prompt: Text("Example: 2027 Spring"))
          Toggle("Add start date", isOn: $hasSeasonStart)
          if hasSeasonStart { DatePicker("Start date", selection: $seasonStart, displayedComponents: .date) }
          Toggle("Add end date", isOn: $hasSeasonEnd)
          if hasSeasonEnd { DatePicker("End date", selection: $seasonEnd, displayedComponents: .date) }
          Picker("Lifecycle", selection: $seasonStatus) {
            ForEach(SDSeasonLifecycle.allCases) { status in Text(status.label).tag(status) }
          }
          Toggle("Make default season", isOn: $seasonIsDefault)
          if let validation = seasonDraft.validationIssue {
            Text(validation.message).foregroundStyle(HP.Color.warning)
          }
          if let seasonErrorText {
            Text(seasonErrorText).foregroundStyle(HP.Color.danger)
          }
        }
      }
      .navigationTitle(editingSeasonId == nil ? "Create Season" : "Edit Season")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { isShowingSeasonEditor = false; resetSeasonDraft() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(editingSeasonId == nil ? "Create Season" : "Save Season") {
            Task { await createSeason() }
          }
          .disabled(!seasonDraft.isValid || activeMutations.contains(.season))
        }
      }
    }
    #if os(macOS)
    .frame(minWidth: 480, minHeight: 460)
    #endif
  }

  private var teamEditorSheet: some View {
    NavigationStack {
      Form {
        Section("Team details") {
          TextField("Team name", text: $newTeamName, prompt: Text("Example: 10u"))
          Picker("Season", selection: $newTeamSeasonId) {
            Text("Select season").tag(UUID?.none)
            ForEach(context?.seasons ?? []) { season in Text(season.name).tag(Optional(season.id)) }
          }
          TextField("Age group", text: $teamAgeGroup, prompt: Text("Example: 10U"))
          TextField("Level", text: $teamCompetitiveLevel, prompt: Text("Example: Club"))
          TextField("Roster capacity (optional)", text: $teamRosterCapacity)
          if let operationErrorText {
            Text(operationErrorText).foregroundStyle(HP.Color.danger)
          }
        }
      }
      .navigationTitle(editingTeamId == nil ? "Create Team" : "Edit Team")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { isShowingTeamEditor = false; resetTeamDraft() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(editingTeamId == nil ? "Create Team" : "Save Team") {
            Task { await createTeam() }
          }
          .disabled(
            newTeamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || newTeamSeasonId == nil
              || activeMutations.contains(.team)
          )
        }
      }
    }
    #if os(macOS)
    .frame(minWidth: 480, minHeight: 420)
    #endif
  }

  private var schedulingCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Organization Scheduling") {
          HPStatusBadge(text: "\(activeTeams.count) teams", kind: .info)
        }
        Text("View authorized team schedules, switch season/team context, create events, and resolve facility or staffing conflicts with an audited override reason.")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        NavigationLink {
          CoachTeamScheduleView()
        } label: {
          Label("Open Unified Schedule", systemImage: "calendar")
            .font(HP.Font.callout.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        NavigationLink {
          OrgEventOperationsAdminView()
        } label: {
          Label("Review Event Operations", systemImage: "checklist.checked")
            .font(HP.Font.callout.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
      }
    }
  }

  private var seasonCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Seasons") {
          if activeMutations.contains(.season) { ProgressView().controlSize(.small) }
        }
        Text("Create the organization lifecycle used by team operations.")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        HPFormField(label: "Season name", text: $seasonName, placeholder: "2027 Spring")
        Toggle("Add start date", isOn: $hasSeasonStart)
        if hasSeasonStart {
          DatePicker("Start date", selection: $seasonStart, displayedComponents: .date)
        }
        Toggle("Add end date", isOn: $hasSeasonEnd)
        if hasSeasonEnd {
          DatePicker("End date", selection: $seasonEnd, displayedComponents: .date)
        }
        Picker("Lifecycle", selection: $seasonStatus) {
          ForEach(SDSeasonLifecycle.allCases) { status in Text(status.label).tag(status) }
        }
        Toggle("Default season", isOn: $seasonIsDefault)
        HPButton(
          title: editingSeasonId == nil ? "Create Season" : "Save Season",
          systemImage: editingSeasonId == nil ? "plus" : "checkmark",
          variant: .primary,
          size: .md,
          action: { Task { await createSeason() } }
        )
        .disabled(!seasonDraft.isValid || activeMutations.contains(.season))
        .accessibilityHint(seasonDraft.validationIssue?.message ?? "Saves this season to the organization")
        if let validation = seasonDraft.validationIssue {
          Text(validation.message)
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.warning)
            .accessibilityLabel("Season form error: \(validation.message)")
        }
        if let seasonErrorText {
          HPErrorState(
            title: "The season could not be created.",
            message: seasonErrorText,
            onRetry: { Task { await createSeason() } }
          )
        }
        ForEach(context?.seasons ?? []) { season in
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(season.name).font(HP.Font.callout.weight(.semibold))
              Text([season.start_date, season.end_date].compactMap { $0 }.joined(separator: " – "))
                .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            }
            Spacer()
            HPStatusBadge(text: season.status.label, kind: season.is_default ? .success : .neutral)
            Button("Edit") { beginEditing(season) }
              .buttonStyle(.borderless)
          }
          .frame(minHeight: 44)
        }
      }
    }
  }

  private var teamSeasonCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Team Seasons")
        Text("Each active team is associated with one season.")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        HPFormField(label: editingTeamId == nil ? "New team" : "Team name", text: $newTeamName, placeholder: "Team name")
        Picker("Season", selection: $newTeamSeasonId) {
          Text("Select season").tag(UUID?.none)
          ForEach(context?.seasons ?? []) { season in Text(season.name).tag(Optional(season.id)) }
        }
        HStack {
          HPFormField(label: "Age group", text: $teamAgeGroup, placeholder: "14U")
          HPFormField(label: "Competitive level", text: $teamCompetitiveLevel, placeholder: "Club")
          HPFormField(label: "Roster capacity", text: $teamRosterCapacity, placeholder: "18")
        }
        HPFormField(label: "Description", text: $teamDescription, placeholder: "Optional team details")
        HPButton(
          title: editingTeamId == nil ? "Create Team" : "Save Team",
          systemImage: editingTeamId == nil ? "plus" : "checkmark",
          variant: .primary,
          size: .md,
          action: { Task { await createTeam() } }
        )
        .disabled(newTeamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newTeamSeasonId == nil || activeMutations.contains(.team))
        if editingTeamId != nil {
          Button("Cancel Editing") { resetTeamDraft() }
            .buttonStyle(.borderless)
        }
        Divider()
        ForEach(context?.teams ?? []) { team in
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(team.name).font(HP.Font.callout.weight(.semibold))
              Text([team.age_group, team.competitive_level].compactMap { $0 }.joined(separator: " • "))
                .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            }
            Spacer()
            if !team.is_active { HPStatusBadge(text: "Archived", kind: .neutral) }
            Menu(seasonName(for: team.season_id)) {
              ForEach(context?.seasons ?? []) { season in
                Button(season.name) { Task { await assign(team: team, to: season) } }
              }
            }
            Button("Edit") { beginEditing(team) }
              .buttonStyle(.borderless)
            if team.is_active {
              Button("Archive", role: .destructive) { Task { await archive(team) } }
                .buttonStyle(.borderless)
            }
          }
          .frame(minHeight: 44)
        }
      }
    }
  }

  private var playerAssignmentsCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Roster assignments")
        Text("Move players between teams while keeping their history intact.")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        #if os(macOS)
        rosterBoard
        #else
        ForEach(players) { player in
          HStack {
            Text(player.displayName).font(HP.Font.callout.weight(.semibold))
            Spacer()
            Menu(playerTeamName(player.id)) {
              ForEach(activeTeams) { team in
                Button(team.name) { Task { await assign(player: player, to: team) } }
              }
            }
          }
          .frame(minHeight: 44)
        }
        #endif
      }
    }
  }

  #if os(macOS)
  private var rosterBoard: some View {
    VStack(alignment: .leading, spacing: HP.Space.sm) {
      HPSearchBar(text: $rosterQuery, placeholder: "Search roster")
      ScrollView(.horizontal, showsIndicators: true) {
        HStack(alignment: .top, spacing: HP.Space.sm) {
          rosterColumn(title: "Unassigned", team: nil, players: playersForRoster(teamId: nil))
          ForEach(activeTeams) { team in
            rosterColumn(title: team.name, team: team, players: playersForRoster(teamId: team.id))
          }
        }
        .padding(.bottom, HP.Space.xs)
      }
      Text("Drag player cards between columns, or use each card’s Move menu. Team history remains intact.")
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
    }
  }

  private func rosterColumn(
    title: String,
    team: SDTeamOperationsTeam?,
    players columnPlayers: [Profile]
  ) -> some View {
    let targetKey = team?.id.uuidString ?? "unassigned"
    return VStack(alignment: .leading, spacing: HP.Space.xs) {
      HStack {
        Text(title).font(HP.Font.headline)
        Spacer()
        HPStatusBadge(text: "\(columnPlayers.count)", kind: .neutral)
      }
      ForEach(columnPlayers) { player in
        rosterPlayerCard(player)
      }
      if columnPlayers.isEmpty {
        Text("Drop players here")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .frame(maxWidth: .infinity, minHeight: 72)
      }
    }
    .padding(HP.Space.sm)
    .frame(width: 240, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
        .fill(rosterDropTarget == targetKey ? HP.Color.accent.opacity(0.14) : HP.Color.surfaceRaised)
    )
    .overlay(
      RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
        .stroke(rosterDropTarget == targetKey ? HP.Color.accent : HP.Color.border, lineWidth: 1)
    )
    .dropDestination(for: String.self) { values, _ in
      guard let value = values.first, let playerId = UUID(uuidString: value) else { return false }
      Task { await movePlayer(playerId, to: team) }
      return true
    } isTargeted: { targeted in
      rosterDropTarget = targeted ? targetKey : nil
    }
  }

  private func rosterPlayerCard(_ player: Profile) -> some View {
    HStack(spacing: HP.Space.xs) {
      HPAvatar(name: player.displayName, size: .sm)
      Text(player.displayName)
        .font(HP.Font.callout.weight(.semibold))
        .lineLimit(2)
      Spacer(minLength: 0)
      Menu {
        Button("Unassigned") { Task { await movePlayer(player.id, to: nil) } }
        Divider()
        ForEach(activeTeams) { team in
          Button(team.name) { Task { await movePlayer(player.id, to: team) } }
        }
      } label: {
        Image(systemName: "ellipsis.circle")
          .frame(width: 32, height: 32)
      }
      .menuStyle(.borderlessButton)
      .accessibilityLabel("Move \(player.displayName)")
    }
    .padding(HP.Space.xs)
    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
    .background(HP.Color.surface)
    .clipShape(RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: HP.Radius.sm).stroke(HP.Color.border))
    .draggable(player.id.uuidString)
  }

  private func playersForRoster(teamId: UUID?) -> [Profile] {
    let query = rosterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    return players.filter { player in
      playerTeamId(player.id) == teamId
        && (query.isEmpty || player.displayName.localizedCaseInsensitiveContains(query))
    }
  }
  #endif

  private var coachAssignmentsCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Staff assignments")
        Picker("Coach", selection: $selectedCoachId) {
          Text("Select coach").tag(UUID?.none)
          ForEach(coaches) { coach in Text(coach.displayName).tag(Optional(coach.id)) }
        }
        Picker("Team", selection: $selectedCoachTeamId) {
          Text("Select team").tag(UUID?.none)
          ForEach(activeTeams) { team in Text(team.name).tag(Optional(team.id)) }
        }
        Text("Responsibilities").font(HP.Font.callout.weight(.semibold))
        ForEach(SDTeamResponsibility.allCases) { responsibility in
          Toggle(responsibility.label, isOn: Binding(
            get: { selectedResponsibilities.contains(responsibility) },
            set: { enabled in
              if enabled { selectedResponsibilities.insert(responsibility) }
              else { selectedResponsibilities.remove(responsibility) }
            }
          ))
        }
        Toggle("Primary team", isOn: $coachPrimary)
        Toggle("Access to all teams", isOn: $coachAllTeams)
        HPButton(
          title: "Save Assignment",
          systemImage: "person.badge.shield.checkmark",
          variant: .primary,
          size: .md,
          action: { Task { await saveCoachAssignment() } }
        )
        .disabled(selectedCoachId == nil || selectedCoachTeamId == nil || selectedResponsibilities.isEmpty || activeMutations.contains(.coach))
        capabilityPreview
      }
    }
  }

  @ViewBuilder
  private var capabilityPreview: some View {
    if let assignment = selectedAssignment {
      Divider()
      HPSectionHeader("Team access") {
        HPStatusBadge(text: "\(assignment.capabilities.count)", kind: .info)
      }
      Text(assignment.capabilities.map(\.label).joined(separator: " • "))
        .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
    }
  }

  private var selectedAssignment: SDCoachTeamAssignment? {
    guard let coachId = selectedCoachId, let teamId = selectedCoachTeamId else { return nil }
    return context?.coach_assignments.first { $0.coach_id == coachId && $0.team_id == teamId && $0.active }
  }

  private func seasonName(for id: UUID) -> String {
    context?.seasons.first(where: { $0.id == id })?.name ?? "Select season"
  }

  private func playerTeamName(_ playerId: UUID) -> String {
    guard let teamId = playerTeamId(playerId) else { return "Unassigned" }
    return activeTeams.first(where: { $0.id == teamId })?.name ?? "Unassigned"
  }

  private func playerTeamId(_ playerId: UUID) -> UUID? {
    if optimisticUnassignedPlayers.contains(playerId) { return nil }
    if let optimistic = optimisticTeamByPlayer[playerId] { return optimistic }
    return context?.player_memberships.first(where: {
      $0.player_id == playerId && $0.active && $0.ended_at == nil
    })?.team_id
  }

  private func reload() async {
    guard let orgId = appState.activeOrgId, let supabase = appState.supabase else { return }
    let token = UUID()
    loadRequestToken = token
    isInitialLoading = true
    loadErrorText = nil
    defer {
      if loadRequestToken == token { isInitialLoading = false }
    }
    do {
      let loaded = try await supabase.fetchTeamOperationsContext(orgId: orgId)
      guard SDAsyncRequestGuard.accepts(
        responseContext: orgId,
        responseToken: token,
        activeContext: appState.activeOrgId,
        currentToken: loadRequestToken,
        taskIsCancelled: Task.isCancelled
      ) else { return }
      context = loaded
      optimisticTeamByPlayer = [:]
      optimisticUnassignedPlayers = []
      newTeamSeasonId = loaded.activeSeason?.id
      if selectedTeamId == nil || !loaded.teams.contains(where: { $0.id == selectedTeamId }) {
        selectedTeamId = loaded.teams.first(where: \.is_active)?.id ?? loaded.teams.first?.id
      }
      if selectedSeasonId == nil || !loaded.seasons.contains(where: { $0.id == selectedSeasonId }) {
        selectedSeasonId = loaded.activeSeason?.id ?? loaded.seasons.first?.id
      }
      await appState.refreshTeamOperationsContext()
    } catch {
      guard SDAsyncRequestGuard.accepts(
        responseContext: orgId,
        responseToken: token,
        activeContext: appState.activeOrgId,
        currentToken: loadRequestToken,
        taskIsCancelled: Task.isCancelled
      ) else { return }
      loadErrorText = workflowMessage(for: error)
    }
  }

  private func createSeason() async {
    guard let orgId = appState.activeOrgId, let supabase = appState.supabase else { return }
    guard seasonDraft.isValid, activeMutations.insert(.season).inserted else { return }
    let requestId = seasonRequestId
    seasonErrorText = nil
    defer { activeMutations.remove(.season) }
    do {
      let saved = try await supabase.adminSaveSeason(
        orgId: orgId,
        seasonId: editingSeasonId,
        name: seasonName.trimmingCharacters(in: .whitespacesAndNewlines),
        startDate: hasSeasonStart ? dateString(seasonStart) : nil,
        endDate: hasSeasonEnd ? dateString(seasonEnd) : nil,
        status: seasonStatus,
        isDefault: seasonIsDefault,
        requestId: requestId
      )
      guard !Task.isCancelled, appState.activeOrgId == orgId else { return }
      let loaded = try await supabase.fetchTeamOperationsContext(orgId: orgId)
      guard !Task.isCancelled, appState.activeOrgId == orgId else { return }
      context = loaded
      selectedSeasonId = saved.id
      newTeamSeasonId = loaded.activeSeason?.id
      isShowingSeasonEditor = false
      confirmationText = editingSeasonId == nil ? "Season created." : "Season saved."
      resetSeasonDraft()
      if !loaded.seasons.contains(where: { $0.id == saved.id }) {
        loadErrorText = "The season was saved, but the season list could not be refreshed."
      }
    } catch {
      guard !Task.isCancelled, appState.activeOrgId == orgId else { return }
      seasonErrorText = workflowMessage(for: error, currentEnvironment: true)
    }
  }

  private func beginEditing(_ season: SDSeason) {
    editingSeasonId = season.id
    seasonName = season.name
    hasSeasonStart = season.start_date != nil
    hasSeasonEnd = season.end_date != nil
    seasonStart = date(from: season.start_date) ?? Date()
    seasonEnd = date(from: season.end_date) ?? Date()
    seasonStatus = season.status
    seasonIsDefault = season.is_default
    seasonRequestId = UUID()
    seasonErrorText = nil
    isShowingSeasonEditor = true
  }

  private func beginCreatingSeason() {
    resetSeasonDraft()
    isShowingSeasonEditor = true
  }

  private func resetSeasonDraft() {
    seasonName = ""
    hasSeasonStart = false
    hasSeasonEnd = false
    seasonStatus = .planning
    seasonIsDefault = false
    editingSeasonId = nil
    seasonErrorText = nil
    seasonRequestId = UUID()
  }

  private func setDefault(_ season: SDSeason) async {
    await update(season, status: season.status, isDefault: true, confirmation: "Default season updated.")
  }

  private func archive(_ season: SDSeason) async {
    await update(season, status: .archived, isDefault: false, confirmation: "Season archived.")
  }

  private func update(
    _ season: SDSeason,
    status: SDSeasonLifecycle,
    isDefault: Bool,
    confirmation: String
  ) async {
    guard let orgId = appState.activeOrgId, let supabase = appState.supabase else { return }
    guard activeMutations.insert(.season).inserted else { return }
    defer { activeMutations.remove(.season) }
    do {
      _ = try await supabase.adminSaveSeason(
        orgId: orgId,
        seasonId: season.id,
        name: season.name,
        startDate: season.start_date,
        endDate: season.end_date,
        status: status,
        isDefault: isDefault,
        requestId: UUID()
      )
      guard !Task.isCancelled, appState.activeOrgId == orgId else { return }
      await reload()
      confirmationText = confirmation
    } catch {
      publishOperationError(error, organizationId: orgId)
    }
  }

  private func assign(team: SDTeamOperationsTeam, to season: SDSeason) async {
    guard let orgId = appState.activeOrgId, let supabase = appState.supabase else { return }
    guard activeMutations.insert(.teamSeason).inserted else { return }
    defer { activeMutations.remove(.teamSeason) }
    do {
      try await supabase.adminAssignTeamToSeason(orgId: orgId, teamId: team.id, seasonId: season.id)
      await reload()
    } catch { publishOperationError(error, organizationId: orgId) }
  }

  private func createTeam() async {
    guard let orgId = appState.activeOrgId,
          let seasonId = newTeamSeasonId,
          let supabase = appState.supabase else { return }
    guard activeMutations.insert(.team).inserted else { return }
    let targetName = newTeamName.trimmingCharacters(in: .whitespacesAndNewlines)
    let targetSeasonId = seasonId
    let wasEditing = editingTeamId != nil
    defer { activeMutations.remove(.team) }
    do {
      if let editingTeamId,
         let existing = context?.teams.first(where: { $0.id == editingTeamId }) {
        try await supabase.adminUpdateTeam(
          orgId: orgId,
          teamId: editingTeamId,
          name: newTeamName.trimmingCharacters(in: .whitespacesAndNewlines),
          colorHex: existing.color_hex,
          description: teamDescription.sdNilIfBlank,
          seasonId: seasonId,
          ageGroup: teamAgeGroup.sdNilIfBlank,
          competitiveLevel: teamCompetitiveLevel.sdNilIfBlank,
          rosterCapacity: Int(teamRosterCapacity),
          isActive: existing.is_active
        )
      } else {
        try await supabase.adminCreateTeam(
          orgId: orgId,
          name: newTeamName.trimmingCharacters(in: .whitespacesAndNewlines),
          colorHex: nil,
          description: teamDescription.sdNilIfBlank,
          seasonId: seasonId,
          ageGroup: teamAgeGroup.sdNilIfBlank,
          competitiveLevel: teamCompetitiveLevel.sdNilIfBlank,
          rosterCapacity: Int(teamRosterCapacity),
          requestId: teamRequestId
        )
      }
      resetTeamDraft()
      await reload()
      selectedTeamId = context?.teams.first(where: {
        $0.name.caseInsensitiveCompare(targetName) == .orderedSame && $0.season_id == targetSeasonId
      })?.id ?? selectedTeamId
      isShowingTeamEditor = false
      detailMode = .summary
      confirmationText = wasEditing ? "Team saved." : "Team created."
    } catch { publishOperationError(error, organizationId: orgId) }
  }

  private func beginCreatingTeam() {
    resetTeamDraft()
    newTeamSeasonId = context?.activeSeason?.id ?? context?.seasons.first?.id
    operationErrorText = nil
    isShowingTeamEditor = true
  }

  private func beginEditing(_ team: SDTeamOperationsTeam) {
    editingTeamId = team.id
    newTeamName = team.name
    newTeamSeasonId = team.season_id
    teamAgeGroup = team.age_group ?? ""
    teamCompetitiveLevel = team.competitive_level ?? ""
    teamRosterCapacity = team.roster_capacity.map(String.init) ?? ""
    teamDescription = team.description ?? ""
    operationErrorText = nil
    isShowingTeamEditor = true
  }

  private func resetTeamDraft() {
    editingTeamId = nil
    newTeamName = ""
    teamAgeGroup = ""
    teamCompetitiveLevel = ""
    teamRosterCapacity = ""
    teamDescription = ""
    teamRequestId = UUID()
    operationErrorText = nil
  }

  private func archive(_ team: SDTeamOperationsTeam) async {
    guard let orgId = appState.activeOrgId, let supabase = appState.supabase else { return }
    guard activeMutations.insert(.team).inserted else { return }
    defer { activeMutations.remove(.team) }
    do {
      try await supabase.adminUpdateTeam(
        orgId: orgId,
        teamId: team.id,
        name: team.name,
        colorHex: team.color_hex,
        description: team.description,
        seasonId: team.season_id,
        ageGroup: team.age_group,
        competitiveLevel: team.competitive_level,
        rosterCapacity: team.roster_capacity,
        isActive: false
      )
      await reload()
    } catch { publishOperationError(error, organizationId: orgId) }
  }

  private func assign(player: Profile, to team: SDTeamOperationsTeam) async {
    guard let orgId = appState.activeOrgId, let supabase = appState.supabase else { return }
    guard activeMutations.insert(.player).inserted else { return }
    defer { activeMutations.remove(.player) }
    do {
      try await supabase.adminAssignPlayerToTeam(
        orgId: orgId,
        playerId: player.id,
        teamId: team.id,
        reason: "organization_admin_assignment"
      )
      await reload()
    } catch { publishOperationError(error, organizationId: orgId) }
  }

  private func movePlayer(_ playerId: UUID, to team: SDTeamOperationsTeam?) async {
    guard let orgId = appState.activeOrgId, let supabase = appState.supabase else { return }
    let previousTeamId = playerTeamId(playerId)
    if let team {
      optimisticTeamByPlayer[playerId] = team.id
      optimisticUnassignedPlayers.remove(playerId)
    } else {
      optimisticTeamByPlayer.removeValue(forKey: playerId)
      optimisticUnassignedPlayers.insert(playerId)
    }
    do {
      if let team {
        try await supabase.adminAssignPlayerToTeam(
          orgId: orgId,
          playerId: playerId,
          teamId: team.id,
          reason: "organization_admin_roster_board"
        )
      } else {
        try await supabase.adminUnassignPlayerFromTeam(
          orgId: orgId,
          playerId: playerId,
          reason: "organization_admin_roster_board"
        )
      }
      guard !Task.isCancelled, appState.activeOrgId == orgId else { return }
      await reload()
    } catch {
      guard !Task.isCancelled, appState.activeOrgId == orgId else { return }
      optimisticTeamByPlayer.removeValue(forKey: playerId)
      optimisticUnassignedPlayers.remove(playerId)
      if let previousTeamId { optimisticTeamByPlayer[playerId] = previousTeamId }
      publishOperationError(error, organizationId: orgId)
    }
  }

  private func saveCoachAssignment() async {
    guard let orgId = appState.activeOrgId,
          let coachId = selectedCoachId,
          let teamId = selectedCoachTeamId,
          let supabase = appState.supabase else { return }
    guard activeMutations.insert(.coach).inserted else { return }
    defer { activeMutations.remove(.coach) }
    do {
      _ = try await supabase.adminAssignCoachToTeam(
        orgId: orgId,
        coachId: coachId,
        teamId: teamId,
        responsibilities: selectedResponsibilities,
        isPrimary: coachPrimary,
        organizationWideAccess: coachAllTeams
      )
      let loaded = try await supabase.fetchTeamOperationsContext(orgId: orgId)
      guard !Task.isCancelled, appState.activeOrgId == orgId else { return }
      context = loaded
      await appState.refreshTeamOperationsContext()
    } catch { publishOperationError(error, organizationId: orgId) }
  }

  private var seasonDraft: SDSeasonDraft {
    SDSeasonDraft(
      organizationId: appState.activeOrgId,
      name: seasonName,
      startDate: hasSeasonStart ? dateString(seasonStart) : nil,
      endDate: hasSeasonEnd ? dateString(seasonEnd) : nil,
      lifecycle: seasonStatus,
      isDefault: seasonIsDefault
    )
  }

  private func publishOperationError(_ error: Error, organizationId: UUID) {
    guard !Task.isCancelled, appState.activeOrgId == organizationId else { return }
    operationErrorText = workflowMessage(for: error)
  }

  private func workflowMessage(for error: Error, currentEnvironment: Bool = false) -> String? {
    guard let presentation = SDApplicationErrorClassifier.presentation(
      for: error,
      taskIsCancelled: Task.isCancelled
    ) else { return nil }
    if currentEnvironment,
       [.unsupportedAction, .notDeployed, .serviceUnavailable].contains(presentation.category) {
      return "This action is not available in the current environment."
    }
    return presentation.message
  }

  private func dateString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  private func date(from value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    return formatter.date(from: value)
  }
}
