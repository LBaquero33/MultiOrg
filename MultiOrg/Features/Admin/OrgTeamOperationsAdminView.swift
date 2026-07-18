import SwiftUI

struct OrgTeamOperationsAdminView: View {
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

  private enum Mutation: Hashable {
    case season, team, teamSeason, player, coach
  }

  var body: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      HPWorkspaceHeader(
        "Team Management",
        orgLabel: organizationName,
        context: organizationContext
      )
      if isInitialLoading, context == nil {
        HPCard { HPLoadingState(text: "Loading team operations…") }
      }
      if let loadErrorText {
        HPCard {
          HPErrorState(
            title: "Team operations couldn’t be loaded.",
            message: loadErrorText,
            onRetry: { Task { await reload() } }
          )
        }
      }
      seasonCard
      teamSeasonCard
      schedulingCard
      playerAssignmentsCard
      coachAssignmentsCard
      if let operationErrorText {
        HPCard {
          HPErrorState(
            title: "Team operations couldn’t be updated.",
            message: operationErrorText
          )
        }
      }
    }
    .task(id: appState.activeOrgId) { await reload() }
    .accessibilityElement(children: .contain)
  }

  private var organizationName: String {
    appState.availableOrganizations.first(where: { $0.id == appState.activeOrgId })?.name
      ?? appState.activeOrgSettings?.display_name
      ?? appState.activeOrgSettings?.short_name
      ?? "Organization"
  }

  private var organizationContext: String {
    if let season = context?.activeSeason?.name {
      return "Organization Administration · \(season) · Organization-wide"
    }
    return "Organization Administration · Organization-wide"
  }

  private var activeTeams: [SDTeamOperationsTeam] { context?.teams.filter(\.is_active) ?? [] }
  private var coaches: [Profile] { context?.people.filter(\.isCoach) ?? [] }
  private var players: [Profile] { context?.people.filter(\.isPlayer) ?? [] }

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
        HPFormField(label: "New team", text: $newTeamName, placeholder: "Team name")
        Picker("Season", selection: $newTeamSeasonId) {
          Text("Select season").tag(UUID?.none)
          ForEach(context?.seasons ?? []) { season in Text(season.name).tag(Optional(season.id)) }
        }
        HPButton(
          title: "Create Team",
          systemImage: "plus",
          variant: .primary,
          size: .md,
          action: { Task { await createTeam() } }
        )
        .disabled(newTeamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newTeamSeasonId == nil || activeMutations.contains(.team))
        Divider()
        ForEach(activeTeams) { team in
          HStack {
            Text(team.name).font(HP.Font.callout.weight(.semibold))
            Spacer()
            Menu(seasonName(for: team.season_id)) {
              ForEach(context?.seasons ?? []) { season in
                Button(season.name) { Task { await assign(team: team, to: season) } }
              }
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
        HPSectionHeader("Player Team Membership")
        Text("Moving a player closes the current assignment and preserves team history.")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
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
      }
    }
  }

  private var coachAssignmentsCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Coach Team Responsibilities")
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
        Toggle("Explicit All Teams access", isOn: $coachAllTeams)
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
      HPSectionHeader("Resolved Capabilities") {
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
    guard let membership = context?.player_memberships.first(where: {
      $0.player_id == playerId && $0.active && $0.ended_at == nil
    }) else { return "Unassigned" }
    return activeTeams.first(where: { $0.id == membership.team_id })?.name ?? "Unassigned"
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
      newTeamSeasonId = loaded.activeSeason?.id
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
      seasonName = ""
      hasSeasonStart = false
      hasSeasonEnd = false
      seasonStatus = .planning
      seasonIsDefault = false
      editingSeasonId = nil
      seasonRequestId = UUID()
      context = loaded
      newTeamSeasonId = loaded.activeSeason?.id
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
    defer { activeMutations.remove(.team) }
    do {
      try await supabase.adminCreateTeam(
        orgId: orgId,
        name: newTeamName.trimmingCharacters(in: .whitespacesAndNewlines),
        colorHex: nil,
        description: nil,
        seasonId: seasonId
      )
      newTeamName = ""
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
