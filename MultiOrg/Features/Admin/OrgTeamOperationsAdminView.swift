import SwiftUI

struct OrgTeamOperationsAdminView: View {
  @EnvironmentObject private var appState: AppState
  @State private var context: SDTeamOperationsContext?
  @State private var seasonName = ""
  @State private var seasonStart = ""
  @State private var seasonEnd = ""
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
  @State private var isLoading = false
  @State private var errorText: String?

  var body: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      seasonCard
      teamSeasonCard
      schedulingCard
      playerAssignmentsCard
      coachAssignmentsCard
    }
    .task { await reload() }
    .alert("Team Operations", isPresented: Binding(
      get: { errorText != nil },
      set: { if !$0 { errorText = nil } }
    )) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorText ?? "")
    }
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
      }
    }
  }

  private var seasonCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Seasons") {
          if isLoading { ProgressView().controlSize(.small) }
        }
        Text("Create the organization lifecycle used by team operations.")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        HPFormField(label: "Season name", text: $seasonName, placeholder: "2027 Spring")
        HStack(spacing: HP.Space.sm) {
          HPFormField(label: "Start date", text: $seasonStart, placeholder: "YYYY-MM-DD")
          HPFormField(label: "End date", text: $seasonEnd, placeholder: "YYYY-MM-DD")
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
        .disabled(seasonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
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
        .disabled(newTeamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newTeamSeasonId == nil || isLoading)
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
        .disabled(selectedCoachId == nil || selectedCoachTeamId == nil || selectedResponsibilities.isEmpty || isLoading)
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
    isLoading = true
    defer { isLoading = false }
    do {
      context = try await supabase.fetchTeamOperationsContext(orgId: orgId)
      newTeamSeasonId = context?.activeSeason?.id
      await appState.refreshTeamOperationsContext()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func createSeason() async {
    guard let orgId = appState.activeOrgId, let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      _ = try await supabase.adminSaveSeason(
        orgId: orgId,
        seasonId: editingSeasonId,
        name: seasonName.trimmingCharacters(in: .whitespacesAndNewlines),
        startDate: seasonStart.isEmpty ? nil : seasonStart,
        endDate: seasonEnd.isEmpty ? nil : seasonEnd,
        status: seasonStatus,
        isDefault: seasonIsDefault
      )
      seasonName = ""
      seasonStart = ""
      seasonEnd = ""
      seasonStatus = .planning
      seasonIsDefault = false
      editingSeasonId = nil
      context = try await supabase.fetchTeamOperationsContext(orgId: orgId)
    } catch { errorText = error.localizedDescription }
  }

  private func beginEditing(_ season: SDSeason) {
    editingSeasonId = season.id
    seasonName = season.name
    seasonStart = season.start_date ?? ""
    seasonEnd = season.end_date ?? ""
    seasonStatus = season.status
    seasonIsDefault = season.is_default
  }

  private func assign(team: SDTeamOperationsTeam, to season: SDSeason) async {
    guard let orgId = appState.activeOrgId, let supabase = appState.supabase else { return }
    do {
      try await supabase.adminAssignTeamToSeason(orgId: orgId, teamId: team.id, seasonId: season.id)
      await reload()
    } catch { errorText = error.localizedDescription }
  }

  private func createTeam() async {
    guard let orgId = appState.activeOrgId,
          let seasonId = newTeamSeasonId,
          let supabase = appState.supabase else { return }
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
    } catch { errorText = error.localizedDescription }
  }

  private func assign(player: Profile, to team: SDTeamOperationsTeam) async {
    guard let orgId = appState.activeOrgId, let supabase = appState.supabase else { return }
    do {
      try await supabase.adminAssignPlayerToTeam(
        orgId: orgId,
        playerId: player.id,
        teamId: team.id,
        reason: "organization_admin_assignment"
      )
      await reload()
    } catch { errorText = error.localizedDescription }
  }

  private func saveCoachAssignment() async {
    guard let orgId = appState.activeOrgId,
          let coachId = selectedCoachId,
          let teamId = selectedCoachTeamId,
          let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      _ = try await supabase.adminAssignCoachToTeam(
        orgId: orgId,
        coachId: coachId,
        teamId: teamId,
        responsibilities: selectedResponsibilities,
        isPrimary: coachPrimary,
        organizationWideAccess: coachAllTeams
      )
      context = try await supabase.fetchTeamOperationsContext(orgId: orgId)
      await appState.refreshTeamOperationsContext()
    } catch { errorText = error.localizedDescription }
  }
}
