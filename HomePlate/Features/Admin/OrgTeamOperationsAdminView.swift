import SwiftUI

struct OrgTeamOperationsAdminView: View {
  enum LaunchAction: Equatable {
    case createTeam
  }

  @EnvironmentObject private var appState: AppState
  @State private var context: SDTeamOperationsContext?
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
  @State private var loadRequestToken: UUID?
  @State private var rosterQuery = ""
  @State private var optimisticTeamByPlayer: [UUID: UUID] = [:]
  @State private var optimisticUnassignedPlayers: Set<UUID> = []
  @State private var rosterDropTarget: String?
  @State private var selectedTeamId: UUID?
  @State private var teamFilter: TeamFilter = .active
  @State private var detailMode: DetailMode = .summary
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
    case team, player, coach
  }

  private enum TeamFilter: String, CaseIterable, Identifiable {
    case active = "Active"
    case archived = "Archived"
    case all = "All"
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
      }
      onLaunchActionHandled()
    }
    .sheet(isPresented: $isShowingTeamEditor) { teamEditorSheet }
    .hpToast($confirmationText)
    .accessibilityElement(children: .contain)
  }

  private var pageContent: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      if !embedded {
        HPWorkspaceHeader(
          "Teams",
          orgLabel: organizationName,
          context: organizationContext
        )
      }
      if isInitialLoading, context == nil {
        HPCard { HPLoadingState(text: "Loading teams…") }
      }
      if let loadErrorText {
        HPCard {
          HPErrorState(
            title: "Teams couldn’t be loaded.",
            message: loadErrorText,
            onRetry: { Task { await reload() } }
          )
        }
      }
      teamsWorkspace
      if detailMode == .roster { playerAssignmentsCard }
      if detailMode == .staff { coachAssignmentsCard }
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
    return "Manage teams, rosters, and staff"
  }

  private var activeTeams: [SDTeamOperationsTeam] { context?.teams.filter(\.is_active) ?? [] }
  private var coaches: [Profile] { context?.people.filter(\.isCoach) ?? [] }
  private var players: [Profile] { context?.people.filter(\.isPlayer) ?? [] }

  private var teamsWorkspace: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HStack(spacing: HP.Space.sm) {
            HPSectionHeader("Teams")
            Spacer()
            HPButton(title: "Create Team", systemImage: "plus", variant: .primary, size: .sm) {
              beginCreatingTeam()
            }
          }
          Picker("Team filter", selection: $teamFilter) {
            ForEach(TeamFilter.allCases) { filter in Text(filter.rawValue).tag(filter) }
          }
          .pickerStyle(.segmented)
          .accessibilityLabel("Team filter")
        }
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
          message: "Choose a team to review its roster, staff, schedule, and shortcuts.",
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
      Label("Open Team", systemImage: "arrow.up.right.square")
        .frame(minHeight: 36)
    }
    .buttonStyle(.borderedProminent)
    Button("Manage Roster") { detailMode = .roster }
      .buttonStyle(.bordered)
    Button("Manage Staff") { detailMode = .staff }
      .buttonStyle(.bordered)
    NavigationLink {
      CoachTeamCommandCenterView(initialSection: .schedule)
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
    [team.age_group, team.competitive_level]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
      .joined(separator: " • ")
  }

  private var teamEditorSheet: some View {
    NavigationStack {
      Form {
        Section("Team details") {
          LabeledContent("Team name") {
            TextField("Example: 10U", text: $newTeamName)
              .multilineTextAlignment(.trailing)
          }
          LabeledContent("Age group") {
            TextField("Optional", text: $teamAgeGroup)
              .multilineTextAlignment(.trailing)
          }
          LabeledContent("Competitive level") {
            TextField("Optional", text: $teamCompetitiveLevel)
              .multilineTextAlignment(.trailing)
          }
          LabeledContent("Roster capacity") {
            TextField("Optional", text: $teamRosterCapacity)
              .multilineTextAlignment(.trailing)
              #if os(iOS)
              .keyboardType(.numberPad)
              #endif
          }
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
        Text("View authorized team schedules, switch teams, create events, and resolve facility or staffing conflicts with an audited override reason.")
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
      HPProfileAvatarButton(profile: player, size: .sm)
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
      newTeamSeasonId = loaded.activeSeason?.id ?? loaded.seasons.first?.id
      if selectedTeamId == nil || !loaded.teams.contains(where: { $0.id == selectedTeamId }) {
        selectedTeamId = loaded.teams.first(where: \.is_active)?.id ?? loaded.teams.first?.id
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

  private func createTeam() async {
    guard let orgId = appState.activeOrgId,
          let seasonId = newTeamSeasonId,
          let supabase = appState.supabase else { return }
    guard activeMutations.insert(.team).inserted else { return }
    let wasEditing = editingTeamId != nil
    var savedTeamId = editingTeamId
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
        let createdTeam = try await supabase.adminCreateTeam(
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
        savedTeamId = createdTeam.id
      }
      resetTeamDraft()
      await reload()
      if let savedTeamId, context?.teams.contains(where: { $0.id == savedTeamId }) == true {
        selectedTeamId = savedTeamId
      }
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

}
