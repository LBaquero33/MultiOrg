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
    Group {
      #if os(macOS)
      macBoard
      #else
      mobileList
      #endif
    }
    .dhdPageBackground()
    .navigationTitle("Teams")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
      }
    }
    .alert("Teams", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .task { await reload() }
  }

  #if os(macOS)
  private var macBoard: some View {
    VStack(alignment: .leading, spacing: 12) {
      teamCreator
      if isLoading { ProgressView("Loading teams…") }
      ScrollView(.horizontal) {
        HStack(alignment: .top, spacing: 12) {
          teamColumn(title: "Unassigned", teamId: nil, people: people.filter { assignments[$0.id] == nil })
          ForEach(teams.filter(\.is_active)) { team in
            teamColumn(title: team.name, teamId: team.id, people: people.filter { assignments[$0.id] == team.id })
          }
        }
        .padding(DHDTheme.pagePadding)
      }
    }
    .padding(.top, DHDTheme.pagePadding)
  }

  private func teamColumn(title: String, teamId: UUID?, people: [Profile]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.headline)
      Text("\(people.count) assigned").font(.caption).foregroundStyle(DHDTheme.textSecondary)
      Divider()
      ForEach(people) { person in
        HStack(spacing: 8) {
          DHDAvatarView(url: nil, initials: initials(for: person), size: 30)
          VStack(alignment: .leading, spacing: 3) {
            Text(person.displayName)
              .lineLimit(1)
            DHDStatusBadge(text: person.isCoach ? "COACH" : "PLAYER", color: person.isCoach ? .green : DHDTheme.accent)
          }
          Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
          .padding(10)
          .background(DHDTheme.surfaceElevated)
          .clipShape(RoundedRectangle(cornerRadius: 7))
          .draggable(person.id.uuidString)
      }
      Spacer(minLength: 32)
    }
    .padding(12)
    .frame(width: 230, alignment: .topLeading)
    .frame(minHeight: 390, alignment: .topLeading)
    .background(DHDTheme.cardBackground)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .dropDestination(for: String.self) { ids, _ in
      guard let raw = ids.first, let playerId = UUID(uuidString: raw) else { return false }
      Task { await assign(playerId, to: teamId) }
      return true
    }
  }
  #else
  private var mobileList: some View {
    List {
      Section { teamCreator }
      Section("Roster") {
        if isLoading { ProgressView("Loading teams…") }
        ForEach(people) { person in
          HStack {
            VStack(alignment: .leading) {
              Text(person.displayName)
              HStack(spacing: 6) {
                DHDStatusBadge(text: person.isCoach ? "COACH" : "PLAYER", color: person.isCoach ? .green : DHDTheme.accent)
                Text(teamName(for: person.id) ?? "Unassigned").font(.caption).foregroundStyle(.secondary)
              }
            }
            Spacer()
            Menu {
              Button("Unassigned") { Task { await assign(person.id, to: nil) } }
              ForEach(teams.filter(\.is_active)) { team in
                Button(team.name) { Task { await assign(person.id, to: team.id) } }
              }
            } label: { Image(systemName: "person.3.sequence") }
          }
        }
      }
    }
  }
  #endif

  private var teamCreator: some View {
    HStack {
      TextField("New team name", text: $newTeamName)
        .textFieldStyle(.roundedBorder)
      Button("Add Team") { Task { await createTeam() } }
        .disabled(newTeamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    .padding(.horizontal, DHDTheme.pagePadding)
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
      assignments = Dictionary(uniqueKeysWithValues: response.members.map { ($0.player_id, $0.team_id) })
    } catch {
      errorText = "Teams could not be loaded. \(friendlyError(error))"
    }
  }

  private func createTeam() async {
    guard let supabase = appState.supabase, let orgId = appState.activeOrgId else { return }
    do {
      try await supabase.adminCreateTeam(orgId: orgId, name: newTeamName.trimmingCharacters(in: .whitespacesAndNewlines), colorHex: nil, description: nil)
      newTeamName = ""
      await reload()
    } catch { errorText = "Team could not be created." }
  }

  private func assign(_ memberId: UUID, to teamId: UUID?) async {
    guard let supabase = appState.supabase, let orgId = appState.activeOrgId else { return }
    do {
      try await supabase.adminAssignTeam(orgId: orgId, teamId: teamId, memberId: memberId)
      if let teamId { assignments[memberId] = teamId } else { assignments.removeValue(forKey: memberId) }
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
