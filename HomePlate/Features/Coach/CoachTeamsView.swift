import SwiftUI

struct CoachTeamsView: View {
  @EnvironmentObject private var appState: AppState
  @State private var people: [Profile] = []
  @State private var teams: [SDTeam] = []
  @State private var assignments: [UUID: UUID] = [:]
  @State private var newTeamName = ""
  @State private var isLoading = false
  @State private var errorText: String?

  var body: some View {
    HPListScreenLayout {
      HPWorkspaceHeader(
        "Teams",
        orgLabel: activeOrganizationName,
        context: "Organize coaches and players"
      )
    } controls: {
      teamCreator
    } results: { context in
      #if os(macOS)
        macBoard(context)
      #else
        mobileList(context)
      #endif
    }
    .navigationTitle("Teams")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          Task { await reload() }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .accessibilityLabel("Refresh teams")
      }
    }
    .alert("Teams", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil }))
    {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorText ?? "")
    }
    .task { await reload() }
  }

  #if os(macOS)
    private func macBoard(_ context: HPScreenLayoutContext) -> some View {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        if isLoading {
          HPCard { HPLoadingState(text: "Loading teams…") }
        }
        if people.isEmpty, !isLoading {
          HPCard {
            HPEmptyState(
              title: "No roster members",
              message: "Players and coaches will appear after they join this organization.",
              systemImage: "person.3"
            )
          }
        }
        ScrollView(.horizontal) {
          HStack(alignment: .top, spacing: HP.Space.sm) {
            teamColumn(
              title: "Unassigned",
              teamId: nil,
              people: people.filter { assignments[$0.id] == nil },
              context: context
            )
            ForEach(teams.filter(\.is_active)) { team in
              teamColumn(
                title: team.name,
                teamId: team.id,
                people: people.filter { assignments[$0.id] == team.id },
                context: context
              )
            }
          }
          .padding(.vertical, HP.Space.xs)
        }
      }
    }

    private func teamColumn(
      title: String,
      teamId: UUID?,
      people: [Profile],
      context: HPScreenLayoutContext
    ) -> some View {
      HPCard(style: .flat) {
        VStack(alignment: .leading, spacing: HP.Space.xs) {
          HPSectionHeader(title) {
            HPStatusBadge(text: "\(people.count)", kind: .neutral)
          }
          Text("\(people.count) assigned")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
          Divider().overlay(HP.Color.border)
          ForEach(people) { person in
            let layout =
              context.isAccessibilitySize
              ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.xs))
              : AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.xs))
            layout {
              HPAvatar(name: person.displayName, size: .sm)
              VStack(alignment: .leading, spacing: 3) {
                Text(person.displayName)
                  .font(HP.Font.callout.weight(.semibold))
                  .foregroundStyle(HP.Color.text)
                  .lineLimit(context.isAccessibilitySize ? nil : 1)
                  .fixedSize(horizontal: false, vertical: true)
                HPStatusBadge(
                  text: person.isCoach ? "COACH" : "PLAYER",
                  kind: person.isCoach ? .success : .info
                )
              }
              Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(HP.Space.xs)
            .background(HP.Color.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous))
            .draggable(person.id.uuidString)
          }
          Spacer(minLength: HP.Space.lg)
        }
      }
      .frame(width: context.isAccessibilitySize ? 320 : 250, alignment: .topLeading)
      .frame(minHeight: 390, alignment: .topLeading)
      .dropDestination(for: String.self) { ids, _ in
        guard let raw = ids.first, let playerId = UUID(uuidString: raw) else { return false }
        Task { await assign(playerId, to: teamId) }
        return true
      }
    }
  #else
    private func mobileList(_ context: HPScreenLayoutContext) -> some View {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Roster") {
            HPStatusBadge(text: "\(people.count)", kind: .neutral)
          }
          if isLoading {
            HPLoadingState(text: "Loading teams…")
          }
          if people.isEmpty, !isLoading {
            HPEmptyState(
              title: "No roster members",
              message: "Players and coaches will appear after they join this organization.",
              systemImage: "person.3"
            )
          }
          ForEach(people) { person in
            let layout =
              context.isAccessibilitySize
              ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
              : AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.sm))
            layout {
              HStack(spacing: HP.Space.sm) {
                HPAvatar(name: person.displayName, size: .sm)
                VStack(alignment: .leading, spacing: 4) {
                  Text(person.displayName)
                    .font(HP.Font.callout.weight(.semibold))
                    .foregroundStyle(HP.Color.text)
                    .fixedSize(horizontal: false, vertical: true)
                  ViewThatFits(in: .horizontal) {
                    HStack(spacing: HP.Space.xs) {
                      personRoleBadge(person)
                      teamAssignmentLabel(person)
                    }
                    VStack(alignment: .leading, spacing: HP.Space.xs) {
                      personRoleBadge(person)
                      teamAssignmentLabel(person)
                    }
                  }
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              Menu {
                Button("Unassigned") { Task { await assign(person.id, to: nil) } }
                ForEach(teams.filter(\.is_active)) { team in
                  Button(team.name) { Task { await assign(person.id, to: team.id) } }
                }
              } label: {
                Image(systemName: "person.3.sequence")
                  .foregroundStyle(HP.Color.accent)
                  .frame(minWidth: 44, minHeight: 44)
                  .contentShape(Rectangle())
              }
              .accessibilityLabel("Assign \(person.displayName) to a team")
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)

            if person.id != people.last?.id {
              Divider().overlay(HP.Color.border.opacity(0.5))
            }
          }
        }
      }
    }
  #endif

  private func personRoleBadge(_ person: Profile) -> some View {
    HPStatusBadge(
      text: person.isCoach ? "COACH" : "PLAYER",
      kind: person.isCoach ? .success : .info
    )
  }

  private func teamAssignmentLabel(_ person: Profile) -> some View {
    Text(teamName(for: person.id) ?? "Unassigned")
      .font(HP.Font.caption)
      .foregroundStyle(HP.Color.textMuted)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var teamCreator: some View {
    HPCard {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .bottom, spacing: HP.Space.sm) {
          HPFormField(
            label: "New team name",
            text: $newTeamName,
            placeholder: "Team name"
          )
          .frame(maxWidth: .infinity)
          addTeamButton(fullWidth: false)
        }
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPFormField(
            label: "New team name",
            text: $newTeamName,
            placeholder: "Team name"
          )
          addTeamButton(fullWidth: true)
        }
      }
    }
  }

  private func addTeamButton(fullWidth: Bool) -> some View {
    HPButton(
      title: "Add Team",
      systemImage: "plus",
      variant: .primary,
      size: .lg,
      fullWidth: fullWidth,
      action: { Task { await createTeam() } }
    )
    .disabled(newTeamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  private var activeOrganizationName: String {
    appState.availableOrganizations.first(where: { $0.id == appState.activeOrgId })?.name
      ?? appState.activeOrgSettings?.display_name
      ?? appState.activeOrgSettings?.short_name
      ?? "Home Plate"
  }

  private func teamName(for playerId: UUID) -> String? {
    guard let id = assignments[playerId] else { return nil }
    return teams.first(where: { $0.id == id })?.name
  }

  private func reload() async {
    guard let supabase = appState.supabase, let orgId = appState.activeOrgId else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let response = try await supabase.adminListTeams(orgId: orgId)
      teams = response.teams
      people = response.roster.sorted {
        if $0.isCoach != $1.isCoach { return !$0.isCoach }
        return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
      }
      assignments = Dictionary(
        uniqueKeysWithValues: response.members.map { ($0.player_id, $0.team_id) })
    } catch {
      errorText = "Teams could not be loaded. \(friendlyError(error))"
    }
  }

  private func createTeam() async {
    guard let supabase = appState.supabase, let orgId = appState.activeOrgId else { return }
    do {
      try await supabase.adminCreateTeam(
        orgId: orgId, name: newTeamName.trimmingCharacters(in: .whitespacesAndNewlines),
        colorHex: nil, description: nil)
      newTeamName = ""
      await reload()
    } catch { errorText = "Team could not be created." }
  }

  private func assign(_ memberId: UUID, to teamId: UUID?) async {
    guard let supabase = appState.supabase, let orgId = appState.activeOrgId else { return }
    do {
      try await supabase.adminAssignTeam(orgId: orgId, teamId: teamId, memberId: memberId)
      if let teamId {
        assignments[memberId] = teamId
      } else {
        assignments.removeValue(forKey: memberId)
      }
    } catch {
      errorText = "This person could not be moved to that team. \(friendlyError(error))"
    }
  }

  private func initials(for profile: Profile) -> String {
    let parts = profile.displayName.split(separator: " ")
    let initials = parts.prefix(2).compactMap(\.first).map(String.init).joined()
    return initials.isEmpty ? profile.shortId.prefix(2).uppercased() : initials.uppercased()
  }

  private func friendlyError(_ error: Error) -> String {
    let text = error.localizedDescription
    if text.localizedCaseInsensitiveContains("coach_team_management_disabled") {
      return "An organization admin has limited coach team management."
    }
    return text
  }
}
