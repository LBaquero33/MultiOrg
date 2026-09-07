import AVKit
import SwiftUI

struct UnifiedPlayerDevelopmentWorkspaceView: View {
  @EnvironmentObject private var appState: AppState

  @State private var players: [SDDevelopmentPlayer] = []
  @State private var selectedPlayerId: UUID?
  @State private var workspace: SDPlayerDevelopmentWorkspace?
  @State private var selectedSection = "Player Hub"
  @State private var selectedDay: SDDevelopmentDay?
  @State private var searchText = ""
  @State private var rosterStatus = "All"
  @State private var isLoadingPlayers = false
  @State private var isLoadingWorkspace = false
  @State private var errorText: String?
  @State private var playersRequestToken = UUID()
  @State private var workspaceRequestToken = UUID()
  @State private var showTemplateBuilder = false

  private let visibleSections = [
    "Player Hub", "Calendar", "Programs", "Testing", "Sessions & Data", "Media",
  ]

  private var initialSection: String {
    appState.myProfile?.isPlayer == true || appState.myProfile?.isParent == true ? "Calendar" : "Player Hub"
  }

  private struct LoadContext: Equatable {
    let organizationId: UUID
    let teamId: UUID?
    let token: UUID
  }

  var body: some View {
    Group {
      if isCurrentUserPlayer {
        selfPlayerWorkspace
      } else {
        rosterWorkspace
      }
    }
    .task(id: contextKey) { await reloadPlayers() }
    .fullScreenCover(item: selectedPlayerBinding) { player in
      DevelopmentPlayerWorkspaceScreen(
        player: player,
        workspace: $workspace,
        isLoading: isLoadingWorkspace,
        errorText: errorText,
        onRetry: {
          Task { await reloadWorkspace(playerId: player.id, context: loadContext) }
        }
      )
      .environmentObject(appState)
    }
    .sheet(isPresented: $showTemplateBuilder) {
      CoachProgramsView(initialWorkspace: .templates)
        .environmentObject(appState)
    }
  }

  private var isCurrentUserPlayer: Bool {
    appState.myProfile?.isPlayer == true
  }

  private var selectedPlayerBinding: Binding<SDDevelopmentPlayer?> {
    Binding(
      get: {
        guard !isCurrentUserPlayer, let selectedPlayerId else { return nil }
        return players.first(where: { $0.id == selectedPlayerId })
      },
      set: { value in
        if value == nil {
          selectedPlayerId = nil
          workspace = nil
          errorText = nil
        }
      }
    )
  }

  private var rosterWorkspace: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPWorkspaceHeader(
          "Player Roster",
          orgLabel: organizationName,
          context: "Select a player to review their calendar, programs, testing, sessions, and media."
        )
        if appState.canAdminActiveOrg || appState.myProfile?.isCoach == true {
          HPButton(
            title: "Template Builder",
            systemImage: "rectangle.stack.badge.plus",
            variant: .primary,
            size: .md
          ) {
            showTemplateBuilder = true
          }
        }
        HPCard {
          VStack(spacing: HP.Space.sm) {
            HPSearchBar(text: $searchText, placeholder: "Search players")
            Picker("Status", selection: $rosterStatus) {
              ForEach(["All", "Submitted", "Missed", "Upcoming", "No Activity"], id: \.self) {
                Text($0).tag($0)
              }
            }
            .pickerStyle(.segmented)
          }
        }

        if isLoadingPlayers && players.isEmpty {
          HPLoadingState(text: "Loading players…")
        } else if let errorText, players.isEmpty {
          HPErrorState(message: errorText, onRetry: { Task { await reloadPlayers() } })
        } else if filteredPlayers.isEmpty {
          HPEmptyState(
            title: "No players match",
            message: "Adjust the team, status, or player search.",
            systemImage: "person.3"
          )
        } else {
          HPCard {
            VStack(spacing: 0) {
              ForEach(Array(filteredPlayers.enumerated()), id: \.element.id) { index, player in
                Button {
                  selectedPlayerId = player.id
                  workspace = nil
                  Task { await reloadWorkspace(playerId: player.id, context: loadContext) }
                } label: {
                  rosterRow(player)
                }
                .buttonStyle(.plain)
                if index < filteredPlayers.count - 1 {
                  Divider().overlay(HP.Color.border)
                }
              }
            }
          }
        }
      }
      .padding(HP.Space.md)
      .frame(maxWidth: 1100, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .background(HP.Color.bg)
  }

  @ViewBuilder
  private var selfPlayerWorkspace: some View {
    if let player = players.first {
      DevelopmentPlayerWorkspaceScreen(
        player: player,
        workspace: $workspace,
        isLoading: isLoadingWorkspace,
        errorText: errorText,
        onRetry: { Task { await reloadWorkspace(playerId: player.id, context: loadContext) } }
      )
      .environmentObject(appState)
    } else if isLoadingPlayers {
      HPLoadingState(text: "Loading your development workspace…")
    } else if let errorText {
      HPErrorState(message: errorText, onRetry: { Task { await reloadPlayers() } })
    } else {
      HPEmptyState(title: "Player workspace unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
    }
  }

  private var contextKey: String {
    "\(appState.activeOrgId?.uuidString ?? "none"):\(appState.selectedTeamId?.uuidString ?? "all"):\(appState.teamContextToken.uuidString)"
  }

  private var organizationName: String {
    if let organizationId = appState.activeOrgId,
       let organization = appState.availableOrganizations.first(where: { $0.id == organizationId }) {
      return organization.displayName
    }
    return appState.activeOrgSettings?.display_name
      ?? appState.activeOrgSettings?.short_name
      ?? "Home Plate"
  }

  private var filteredPlayers: [SDDevelopmentPlayer] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    return players.filter { player in
      let matchesSearch = query.isEmpty || player.name.localizedCaseInsensitiveContains(query)
      let summary = player.summary_status?.replacingOccurrences(of: "_", with: " ").capitalized
        ?? "No Activity"
      return matchesSearch && (rosterStatus == "All" || summary == rosterStatus)
    }
  }

  private func rosterRow(_ player: SDDevelopmentPlayer) -> some View {
    HStack(spacing: HP.Space.sm) {
      HPAvatar(
        name: player.name,
        size: .md,
        imageURL: player.avatar_path.flatMap { appState.supabase?.publicAvatarURL(path: $0) }
      )
      VStack(alignment: .leading, spacing: 4) {
        Text(player.name)
          .font(HP.Font.body.weight(.semibold))
          .foregroundStyle(HP.Color.text)
        Text(player.team_names?.isEmpty == false ? player.team_names!.joined(separator: " · ") : "No team")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
        Text("\(player.active_program_count ?? 0) active · Next \(player.next_due_date ?? "Not scheduled")")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
      }
      Spacer()
      HPStatusBadge(
        text: player.summary_status?.replacingOccurrences(of: "_", with: " ").capitalized ?? "No Activity",
        kind: rosterBadge(player.summary_status)
      )
      Image(systemName: "chevron.right").foregroundStyle(HP.Color.textMuted)
    }
    .padding(.vertical, HP.Space.sm)
    .contentShape(Rectangle())
  }

  private func rosterBadge(_ status: String?) -> HPStatusKind {
    switch status {
    case "submitted": .success
    case "missed": .danger
    case "upcoming": .warning
    default: .neutral
    }
  }

  private var sectionPicker: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: HP.Space.xs) {
        ForEach(visibleSections, id: \.self) { section in
          Button {
            selectedSection = section
          } label: {
            Text(section)
              .font(HP.Font.body.weight(.semibold))
              .foregroundStyle(selectedSection == section ? HP.Color.bg : HP.Color.text)
              .padding(.horizontal, HP.Space.md)
              .frame(minHeight: 44)
              .background(selectedSection == section ? HP.Color.accent : HP.Color.surface)
              .clipShape(RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous))
              .overlay {
                RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous)
                  .strokeBorder(HP.Color.border, lineWidth: 1)
              }
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var playerSelector: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HStack {
          Text("Player Hub")
            .font(HP.Font.title.weight(.semibold))
            .foregroundStyle(HP.Color.text)
          Spacer()
          Text("\(filteredPlayers.count)")
            .font(HP.Font.caption.weight(.semibold))
            .foregroundStyle(HP.Color.textMuted)
        }
        TextField("Search players", text: $searchText)
          .textFieldStyle(.roundedBorder)

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: HP.Space.sm) {
            ForEach(filteredPlayers) { player in
              Button {
                selectedPlayerId = player.id
                Task { await reloadWorkspace(playerId: player.id, context: loadContext) }
              } label: {
                HStack(spacing: HP.Space.xs) {
                  HPAvatar(
                    name: player.name,
                    size: .sm,
                    imageURL: player.avatar_path.flatMap { appState.supabase?.publicAvatarURL(path: $0) }
                  )
                  Text(player.name)
                    .font(HP.Font.body.weight(.semibold))
                    .lineLimit(1)
                }
                .foregroundStyle(HP.Color.text)
                .padding(.horizontal, HP.Space.sm)
                .frame(minHeight: 48)
                .background(selectedPlayerId == player.id ? HP.Color.accent.opacity(0.18) : HP.Color.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous))
                .overlay {
                  RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous)
                    .strokeBorder(selectedPlayerId == player.id ? HP.Color.accent : HP.Color.border, lineWidth: 1)
                }
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private var workspaceContent: some View {
    if isLoadingWorkspace && workspace == nil {
      HPLoadingState(text: "Loading player development…")
    } else if let workspace {
      if let errorText {
        HPErrorState(
          title: "Showing saved results",
          message: errorText,
          retryTitle: "Refresh",
          onRetry: {
            Task { await reloadWorkspace(playerId: workspace.player.id, context: loadContext) }
          }
        )
      }
      switch selectedSection {
      case "Player Hub": playerHub(workspace)
      case "Programs": programs(workspace)
      case "Testing": dayList(workspace.days.filter { day in
        day.activities.contains { $0.kind == .testing }
      }, emptyTitle: "No testing activity")
      case "Sessions & Data": dayList(workspace.days.filter { day in
        day.activities.contains { [.session, .providerImport, .providerMetric].contains($0.kind) }
      }, emptyTitle: "No sessions or imported data")
      case "Media": dayList(workspace.days.filter { !$0.media.isEmpty }, emptyTitle: "No media")
      default: dayList(workspace.days, emptyTitle: "No development dates")
      }
    } else if let errorText {
      HPErrorState(message: errorText, onRetry: {
        guard let selectedPlayerId else { return }
        Task { await reloadWorkspace(playerId: selectedPlayerId, context: loadContext) }
      })
    }
  }

  private func playerHub(_ workspace: SDPlayerDevelopmentWorkspace) -> some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      HPCard {
        HStack(alignment: .top, spacing: HP.Space.md) {
          HPAvatar(
            name: workspace.player.name,
            size: .lg,
            imageURL: workspace.player.avatar_path.flatMap { appState.supabase?.publicAvatarURL(path: $0) }
          )
          VStack(alignment: .leading, spacing: HP.Space.xs) {
            Text(workspace.player.name)
              .font(HP.Font.title.weight(.bold))
              .foregroundStyle(HP.Color.text)
            if let bio = workspace.player.bio, !bio.isEmpty {
              Text(bio).font(HP.Font.body).foregroundStyle(HP.Color.textMuted)
            }
            HStack(spacing: HP.Space.sm) {
              if let instagram = workspace.player.instagram_url, let url = URL(string: instagram) {
                Link("Instagram", destination: url)
              }
              if let perfectGame = workspace.player.perfect_game_url, let url = URL(string: perfectGame) {
                Link("Perfect Game", destination: url)
              }
            }
            .font(HP.Font.caption.weight(.semibold))
          }
          Spacer(minLength: 0)
        }
      }

      HStack(spacing: HP.Space.sm) {
        summaryMetric("Active programs", value: workspace.assignments.filter { $0.status == "active" }.count)
        summaryMetric("Submitted", value: workspace.days.filter { $0.status == .submitted }.count)
        summaryMetric("Media", value: workspace.days.reduce(0) { $0 + $1.media_count })
      }
      dayList(Array(workspace.days.prefix(8)), emptyTitle: "No recent activity")
    }
  }

  private func summaryMetric(_ title: String, value: Int) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.xs) {
        Text("\(value)").font(HP.Font.title.weight(.bold)).foregroundStyle(HP.Color.text)
        Text(title).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted).lineLimit(2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func programs(_ workspace: SDPlayerDevelopmentWorkspace) -> some View {
    VStack(alignment: .leading, spacing: HP.Space.sm) {
      if workspace.assignments.isEmpty {
        HPEmptyState(title: "No assigned programs", systemImage: "list.clipboard")
      } else {
        ForEach(workspace.assignments) { assignment in
          HPCard {
            HStack(alignment: .top, spacing: HP.Space.sm) {
              VStack(alignment: .leading, spacing: HP.Space.xs) {
                Text(assignment.template_name)
                  .font(HP.Font.headline)
                  .foregroundStyle(HP.Color.text)
                Text("\(assignment.start_date) – \(assignment.end_date)")
                  .font(HP.Font.caption)
                  .foregroundStyle(HP.Color.textMuted)
                if let notes = assignment.notes, !notes.isEmpty {
                  Text(notes).font(HP.Font.body).foregroundStyle(HP.Color.textMuted)
                }
              }
              Spacer()
              HPStatusBadge(text: assignment.status.capitalized, kind: assignment.status == "active" ? .success : .neutral)
            }
          }
        }
      }
      dayList(workspace.days.filter(\.scheduled), emptyTitle: "No scheduled program days")
    }
  }

  private func dayList(_ days: [SDDevelopmentDay], emptyTitle: String) -> some View {
    Group {
      if days.isEmpty {
        HPEmptyState(title: emptyTitle, systemImage: "calendar.badge.exclamationmark")
      } else {
        HPCard {
          VStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
              Button {
                selectedDay = day
              } label: {
                HStack(spacing: HP.Space.sm) {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(day.date)
                      .font(HP.Font.body.weight(.semibold))
                      .foregroundStyle(HP.Color.text)
                    Text("\(day.activity_count) activities · \(day.media_count) files or videos")
                      .font(HP.Font.caption)
                      .foregroundStyle(HP.Color.textMuted)
                  }
                  Spacer()
                  HPStatusBadge(text: day.status.title, kind: day.status.badgeKind)
                  Image(systemName: "chevron.right")
                    .foregroundStyle(HP.Color.textMuted)
                }
                .padding(.vertical, HP.Space.sm)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              if index < days.count - 1 {
                Divider().overlay(HP.Color.border)
              }
            }
          }
        }
      }
    }
  }

  @MainActor
  private func reloadPlayers() async {
    let requestToken = UUID()
    playersRequestToken = requestToken
    selectedSection = initialSection
    players = []
    workspace = nil
    selectedPlayerId = nil
    errorText = nil
    guard let service = appState.supabase, let context = loadContext else {
      errorText = "Choose an organization to view player development."
      return
    }
    isLoadingPlayers = true
    defer {
      if playersRequestToken == requestToken {
        isLoadingPlayers = false
      }
    }
    do {
      let loaded = try await service.listDevelopmentWorkspacePlayers(
        orgId: context.organizationId,
        teamId: context.teamId
      )
      guard !Task.isCancelled,
            playersRequestToken == requestToken,
            loadContext == context else { return }
      players = loaded
      if isCurrentUserPlayer, let first = loaded.first {
        selectedPlayerId = first.id
        await reloadWorkspace(playerId: first.id, context: context)
      }
    } catch {
      guard !SDApplicationErrorClassifier.isCancellation(
        error,
        taskIsCancelled: Task.isCancelled
      ), playersRequestToken == requestToken, loadContext == context else { return }
      errorText = "Player development could not be loaded. Check your access and try again."
    }
  }

  @MainActor
  private func reloadWorkspace(playerId: UUID, context: LoadContext?) async {
    guard let context else { return }
    let requestToken = UUID()
    workspaceRequestToken = requestToken
    errorText = nil
    guard let service = appState.supabase else { return }
    isLoadingWorkspace = true
    defer {
      if workspaceRequestToken == requestToken {
        isLoadingWorkspace = false
      }
    }
    let calendar = Calendar(identifier: .gregorian)
    let now = Date()
    let start = calendar.date(byAdding: .year, value: -1, to: now) ?? now
    let end = calendar.date(byAdding: .year, value: 1, to: now) ?? now
    do {
      let loaded = try await service.fetchDevelopmentWorkspace(
        orgId: context.organizationId,
        playerId: playerId,
        teamId: context.teamId,
        startDate: Self.isoDate(start),
        endDate: Self.isoDate(end)
      )
      guard !Task.isCancelled,
            workspaceRequestToken == requestToken,
            loadContext == context,
            selectedPlayerId == playerId else { return }
      workspace = loaded
    } catch {
      guard !SDApplicationErrorClassifier.isCancellation(
        error,
        taskIsCancelled: Task.isCancelled
      ), workspaceRequestToken == requestToken,
         loadContext == context,
         selectedPlayerId == playerId else { return }
      errorText = "The latest player results could not be refreshed."
    }
  }

  private var loadContext: LoadContext? {
    guard let organizationId = appState.activeOrgId else { return nil }
    return LoadContext(
      organizationId: organizationId,
      teamId: appState.selectedTeamId,
      token: appState.teamContextToken
    )
  }

  private static func isoDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }
}

private struct DevelopmentPlayerWorkspaceScreen: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appState: AppState

  let player: SDDevelopmentPlayer
  @Binding var workspace: SDPlayerDevelopmentWorkspace?
  let isLoading: Bool
  let errorText: String?
  let onRetry: () -> Void

  @State private var selectedTab: Tab = .calendar
  @State private var selectedDay: SDDevelopmentDay?
  @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
  @State private var timelineFilter: TimelineFilter = .all
  @State private var focusedDay: SDDevelopmentDay?
  @State private var showPlayerManagement = false

  private enum Tab: String, CaseIterable, Identifiable {
    case calendar = "Calendar"
    case timeline = "Timeline"
    case programs = "Programs"
    case dataLab = "Data Lab"
    case profile = "Profile"
    var id: String { rawValue }
  }

  private enum TimelineFilter: String, CaseIterable, Identifiable {
    case all = "All Activity"
    case programs = "Programs"
    case testing = "Testing"
    case sessions = "Sessions & Data"
    case media = "Media"
    var id: String { rawValue }
  }

  private var canManage: Bool {
    ["owner", "admin", "coach"].contains(appState.activeOrgMembership?.normalizedRole ?? "")
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        playerHeader
        HPSegmentedControl(
          options: Tab.allCases.map { (value: $0, label: $0.rawValue) },
          selection: $selectedTab
        )
        .padding(.horizontal, HP.Space.md)
        .padding(.vertical, HP.Space.sm)
        .background(HP.Color.bg)

        Group {
          if isLoading && workspace == nil {
            HPLoadingState(text: "Loading \(player.name)…")
          } else if let errorText, workspace == nil {
            HPErrorState(message: errorText, onRetry: onRetry)
          } else if let workspace {
            workspaceContent(workspace)
          } else {
            HPEmptyState(title: "Player workspace unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .background(HP.Color.bg)
      .toolbar(.hidden, for: .navigationBar)
    }
    .onChange(of: workspace?.player.id) { _, _ in
      guard let workspace else { return }
      selectedDay = initialDay(workspace)
      if let selectedDay, let date = Self.date(selectedDay.date) {
        month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
      }
    }
    .sheet(item: $focusedDay) { day in
      DevelopmentDayDetailSheet(playerName: player.name, day: day)
        .environmentObject(appState)
    }
    .sheet(isPresented: $showPlayerManagement) {
      CoachPlayerProfileView(
        player: Profile(id: player.id, role: "player", full_name: player.name, avatar_path: player.avatar_path)
      )
      .environmentObject(appState)
    }
  }

  private var playerHeader: some View {
    HStack(spacing: HP.Space.sm) {
      HPAvatar(
        name: player.name,
        size: .md,
        imageURL: player.avatar_path.flatMap { appState.supabase?.publicAvatarURL(path: $0) }
      )
      VStack(alignment: .leading, spacing: 3) {
        Text(player.name).font(HP.Font.headline).foregroundStyle(HP.Color.text)
        Text((player.team_names ?? []).joined(separator: " · "))
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .lineLimit(1)
      }
      Spacer()
      if let workspace {
        VStack(alignment: .trailing, spacing: 2) {
          Text("\(workspace.assignments.filter { $0.status == "active" }.count) active")
            .font(HP.Font.caption.weight(.semibold))
          Text("\(completionPercent(workspace))% complete")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
        }
      }
      if canManage {
        Button {
          showPlayerManagement = true
        } label: {
          Image(systemName: "plus")
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel("Assign program")
      }
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark").frame(width: 40, height: 40)
      }
      .buttonStyle(.bordered)
      .accessibilityLabel("Close player workspace")
    }
    .padding(HP.Space.md)
    .background(HP.Color.surface)
    .overlay(alignment: .bottom) { Divider().overlay(HP.Color.border) }
  }

  @ViewBuilder
  private func workspaceContent(_ workspace: SDPlayerDevelopmentWorkspace) -> some View {
    switch selectedTab {
    case .calendar:
      ScrollView {
        VStack(alignment: .leading, spacing: HP.Space.md) {
          calendar(workspace)
          if let selectedDay {
            daySummary(selectedDay)
          } else {
            HPEmptyState(title: "Select a date", message: "Choose a colored day to inspect its work and results.", systemImage: "calendar")
          }
        }
        .padding(HP.Space.md)
      }
    case .timeline:
      timeline(workspace)
    case .programs:
      programAssignments(workspace)
    case .dataLab:
      NativePlayerAnalyticsView(playerId: player.id, playerName: player.name)
    case .profile:
      profile(workspace)
    }
  }

  private func calendar(_ workspace: SDPlayerDevelopmentWorkspace) -> some View {
    VStack(alignment: .leading, spacing: HP.Space.sm) {
      HStack {
        Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }
          .buttonStyle(.bordered)
        Spacer()
        Text(month.formatted(.dateTime.month(.wide).year()))
          .font(HP.Font.title.weight(.semibold))
          .foregroundStyle(HP.Color.text)
        Spacer()
        Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }
          .buttonStyle(.bordered)
      }

      HStack(spacing: HP.Space.sm) {
        legend("Submitted", color: HP.Color.success)
        legend("Missed", color: HP.Color.danger)
        legend("Scheduled", color: HP.Color.warning)
      }

      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
        ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { weekday in
          Text(weekday).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        }
        ForEach(Array(monthCells(workspace).enumerated()), id: \.offset) { _, cell in
          if let cell {
            dayCell(cell)
          } else {
            Color.clear.aspectRatio(1, contentMode: .fit)
          }
        }
      }
    }
  }

  private func legend(_ title: String, color: Color) -> some View {
    HStack(spacing: 4) {
      Circle().fill(color).frame(width: 7, height: 7)
      Text(title).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
    }
  }

  private func dayCell(_ cell: (date: Date, day: SDDevelopmentDay?)) -> some View {
    let selected = selectedDay?.date == Self.isoDate(cell.date)
    let color = dayColor(cell.day)
    return Button {
      selectedDay = cell.day
    } label: {
      ZStack(alignment: .topTrailing) {
        Text(cell.date.formatted(.dateTime.day()))
          .font(HP.Font.body.weight(.semibold))
          .foregroundStyle(HP.Color.text)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .padding(7)
        if let day = cell.day, day.media_count > 0 {
          Image(systemName: "camera.fill")
            .font(.caption2)
            .foregroundStyle(color)
            .padding(6)
        }
      }
      .aspectRatio(1, contentMode: .fit)
      .background(color.opacity(cell.day == nil ? 0.03 : 0.18))
      .clipShape(RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous)
          .strokeBorder(selected ? HP.Color.accent : color.opacity(cell.day == nil ? 0.15 : 0.75), lineWidth: selected ? 2 : 1)
      }
    }
    .buttonStyle(.plain)
    .disabled(cell.day == nil)
  }

  private func daySummary(_ day: SDDevelopmentDay) -> some View {
    VStack(alignment: .leading, spacing: HP.Space.sm) {
      HStack {
        Text("\(day.date) · \(day.status.title)")
          .font(HP.Font.title.weight(.semibold))
          .foregroundStyle(HP.Color.text)
        Spacer()
        HPStatusBadge(text: day.status.title, kind: day.status.badgeKind)
      }
      ForEach(dayGroups(day), id: \.title) { group in
        VStack(alignment: .leading, spacing: HP.Space.xs) {
          Text(group.title.uppercased())
            .font(HP.Font.eyebrow)
            .tracking(HP.Font.eyebrowTracking)
            .foregroundStyle(HP.Color.textMuted)
          if group.activities.isEmpty && group.media.isEmpty {
            Text("No activity").font(HP.Font.body).foregroundStyle(HP.Color.textMuted)
          } else {
            ForEach(group.activities) { activity in
              Button { focusedDay = day } label: {
                HStack {
                  VStack(alignment: .leading, spacing: 3) {
                    Text(activity.title).font(HP.Font.body.weight(.semibold)).foregroundStyle(HP.Color.text)
                    Text(activity.subtitle ?? activity.source.capitalized).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
                  }
                  Spacer()
                  Image(systemName: "chevron.right").foregroundStyle(HP.Color.textMuted)
                }
                .padding(.vertical, 7)
              }
              .buttonStyle(.plain)
            }
            ForEach(group.media) { media in
              Button { focusedDay = day } label: {
                Label(media.title, systemImage: media.kind == .importFile ? "doc" : "play.rectangle")
                  .font(HP.Font.body.weight(.semibold))
                  .foregroundStyle(HP.Color.text)
                  .padding(.vertical, 7)
              }
              .buttonStyle(.plain)
            }
          }
        }
        .padding(.vertical, HP.Space.xs)
        Divider().overlay(HP.Color.border)
      }
    }
  }

  private func timeline(_ workspace: SDPlayerDevelopmentWorkspace) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack {
            ForEach(TimelineFilter.allCases) { filter in
              Button {
                timelineFilter = filter
              } label: {
                Text(filter.rawValue)
                  .font(HP.Font.caption.weight(.semibold))
                  .foregroundStyle(timelineFilter == filter ? HP.Color.bg : HP.Color.text)
              }
              .buttonStyle(.bordered)
              .tint(timelineFilter == filter ? HP.Color.accent : HP.Color.border)
            }
          }
        }
        ForEach(filteredTimeline(workspace), id: \.day.id) { row in
          Button { focusedDay = row.day } label: {
            HStack(alignment: .top, spacing: HP.Space.sm) {
              VStack(alignment: .leading, spacing: 2) {
                Text(row.day.date).font(HP.Font.caption.weight(.semibold)).foregroundStyle(HP.Color.textMuted)
                Text(row.title).font(HP.Font.body.weight(.semibold)).foregroundStyle(HP.Color.text)
                Text(row.source).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
              }
              Spacer()
              HPStatusBadge(text: row.day.status.title, kind: row.day.status.badgeKind)
              if row.day.media_count > 0 { Image(systemName: "camera.fill").foregroundStyle(HP.Color.info) }
            }
            .padding(HP.Space.sm)
            .background(HP.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous))
          }
          .buttonStyle(.plain)
        }
      }
      .padding(HP.Space.md)
    }
  }

  private func programAssignments(_ workspace: SDPlayerDevelopmentWorkspace) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        ForEach(workspace.assignments.sorted { $0.status == "active" && $1.status != "active" }) { assignment in
          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.xs) {
              HStack {
                Text(assignment.template_name).font(HP.Font.headline).foregroundStyle(HP.Color.text)
                Spacer()
                HPStatusBadge(text: assignment.status.capitalized, kind: assignment.status == "active" ? .success : .neutral)
              }
              Text("\(assignment.start_date) – \(assignment.end_date)")
                .font(HP.Font.caption)
                .foregroundStyle(HP.Color.textMuted)
              let scheduled = workspace.days.filter(\.scheduled)
              let complete = scheduled.filter { $0.status == .submitted }.count
              let missed = scheduled.filter { $0.status == .missed }.count
              Text("\(complete) completed · \(missed) missed · \(max(0, scheduled.count - complete - missed)) upcoming")
                .font(HP.Font.body)
                .foregroundStyle(HP.Color.text)
            }
          }
        }
        if workspace.assignments.isEmpty {
          HPEmptyState(title: "No assigned programs", systemImage: "list.clipboard")
        }
      }
      .padding(HP.Space.md)
    }
  }

  private func profile(_ workspace: SDPlayerDevelopmentWorkspace) -> some View {
    ScrollView {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.md) {
          HPAvatar(
            name: workspace.player.name,
            size: .lg,
            imageURL: workspace.player.avatar_path.flatMap { appState.supabase?.publicAvatarURL(path: $0) }
          )
          Text(workspace.player.name).font(HP.Font.title.weight(.bold)).foregroundStyle(HP.Color.text)
          if let bio = workspace.player.bio, !bio.isEmpty {
            Text(bio).font(HP.Font.body).foregroundStyle(HP.Color.textMuted)
          }
          if let instagram = workspace.player.instagram_url, let url = URL(string: instagram) {
            Link("Instagram", destination: url)
          }
          if let perfectGame = workspace.player.perfect_game_url, let url = URL(string: perfectGame) {
            Link("Perfect Game", destination: url)
          }
        }
      }
      .padding(HP.Space.md)
    }
  }

  private func completionPercent(_ workspace: SDPlayerDevelopmentWorkspace) -> Int {
    let scheduled = workspace.days.filter(\.scheduled)
    guard !scheduled.isEmpty else { return 0 }
    return Int((Double(scheduled.filter { $0.status == .submitted }.count) / Double(scheduled.count) * 100).rounded())
  }

  private func initialDay(_ workspace: SDPlayerDevelopmentWorkspace) -> SDDevelopmentDay? {
    let today = Self.isoDate(Date())
    return workspace.days.first(where: { $0.date == today }) ?? workspace.days.sorted { $0.date > $1.date }.first
  }

  private func changeMonth(_ value: Int) {
    month = Calendar.current.date(byAdding: .month, value: value, to: month) ?? month
  }

  private func monthCells(_ workspace: SDPlayerDevelopmentWorkspace) -> [(date: Date, day: SDDevelopmentDay?)?] {
    let calendar = Calendar.current
    guard let interval = calendar.dateInterval(of: .month, for: month),
          let days = calendar.range(of: .day, in: .month, for: month) else { return [] }
    let firstWeekday = calendar.component(.weekday, from: interval.start)
    let byDate = Dictionary(uniqueKeysWithValues: workspace.days.map { ($0.date, $0) })
    var cells: [(date: Date, day: SDDevelopmentDay?)?] = Array(repeating: nil, count: max(0, firstWeekday - 1))
    for number in days {
      if let date = calendar.date(bySetting: .day, value: number, of: interval.start) {
        cells.append((date, byDate[Self.isoDate(date)]))
      }
    }
    return cells
  }

  private func dayColor(_ day: SDDevelopmentDay?) -> Color {
    guard let day else { return HP.Color.border }
    switch day.status {
    case .submitted: return HP.Color.success
    case .missed: return HP.Color.danger
    case .upcoming: return HP.Color.warning
    }
  }

  private struct DayGroup {
    let title: String
    let activities: [SDDevelopmentActivity]
    let media: [SDDevelopmentMedia]
  }

  private func dayGroups(_ day: SDDevelopmentDay) -> [DayGroup] {
    [
      DayGroup(title: "Program Work", activities: day.activities.filter { $0.kind == .program }, media: day.media.filter { $0.kind == .programSetVideo }),
      DayGroup(title: "Testing", activities: day.activities.filter { $0.kind == .testing }, media: day.media.filter { $0.kind == .testingFieldVideo }),
      DayGroup(title: "Sessions & Data", activities: day.activities.filter { [.session, .providerImport, .providerMetric].contains($0.kind) }, media: day.media.filter { [.sessionVideo, .importFile].contains($0.kind) }),
      DayGroup(title: "Media & Files", activities: [], media: day.media),
    ]
  }

  private struct TimelineRow {
    let day: SDDevelopmentDay
    let title: String
    let source: String
  }

  private func filteredTimeline(_ workspace: SDPlayerDevelopmentWorkspace) -> [TimelineRow] {
    workspace.days.sorted { $0.date > $1.date }.compactMap { day in
      let activities: [SDDevelopmentActivity]
      switch timelineFilter {
      case .all: activities = day.activities
      case .programs: activities = day.activities.filter { [.program, .dailyLog].contains($0.kind) }
      case .testing: activities = day.activities.filter { $0.kind == .testing }
      case .sessions: activities = day.activities.filter { [.session, .providerImport, .providerMetric].contains($0.kind) }
      case .media: activities = day.media.isEmpty ? [] : day.activities
      }
      if let activity = activities.first {
        return TimelineRow(day: day, title: activity.title, source: activity.source.capitalized)
      }
      if timelineFilter == .all || timelineFilter == .media, let media = day.media.first {
        return TimelineRow(day: day, title: media.title, source: media.source.capitalized)
      }
      return nil
    }
  }

  private static func date(_ value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value)
  }

  private static func isoDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }
}

struct TestingSetupWorkspaceView: View {
  @EnvironmentObject private var appState: AppState

  @State private var players: [SDDevelopmentPlayer] = []
  @State private var selectedPlayerId: UUID?
  @State private var isLoading = false
  @State private var errorText: String?

  var body: some View {
    Group {
      if isLoading && players.isEmpty {
        HPLoadingState(text: "Loading testing setup…")
          .padding(HP.Space.md)
      } else if let errorText, players.isEmpty {
        HPErrorState(message: errorText, onRetry: { Task { await reload() } })
          .padding(HP.Space.md)
      } else if let selectedPlayer {
        VStack(spacing: 0) {
          Picker("Player", selection: $selectedPlayerId) {
            ForEach(players) { player in
              Text(player.name).tag(Optional(player.id))
            }
          }
          .pickerStyle(.menu)
          .padding(.horizontal, HP.Space.md)
          .padding(.top, HP.Space.sm)

          CoachPlayerTestingCRUDView(
            player: Profile(
              id: selectedPlayer.id,
              role: "player",
              full_name: selectedPlayer.name,
              avatar_path: selectedPlayer.avatar_path
            ),
            canManagePlayer: true
          )
        }
      } else {
        HPEmptyState(
          title: "No players available",
          message: "Testing fields become available when your assigned team has players.",
          systemImage: "slider.horizontal.3"
        )
        .padding(HP.Space.md)
      }
    }
    .background(HP.Color.bg)
    .task(id: contextKey) { await reload() }
  }

  private var selectedPlayer: SDDevelopmentPlayer? {
    players.first(where: { $0.id == selectedPlayerId })
  }

  private var contextKey: String {
    "\(appState.activeOrgId?.uuidString ?? "none"):\(appState.selectedTeamId?.uuidString ?? "all"):\(appState.teamContextToken.uuidString)"
  }

  @MainActor
  private func reload() async {
    players = []
    selectedPlayerId = nil
    errorText = nil
    guard let service = appState.supabase, let orgId = appState.activeOrgId else {
      errorText = "Choose an organization to manage testing."
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      players = try await service.listDevelopmentWorkspacePlayers(
        orgId: orgId,
        teamId: appState.selectedTeamId
      )
      selectedPlayerId = players.first?.id
    } catch {
      errorText = "Testing setup could not be loaded."
    }
  }
}

private struct DevelopmentDayDetailSheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appState: AppState
  let playerName: String
  let day: SDDevelopmentDay

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: HP.Space.md) {
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text(playerName).font(HP.Font.title.weight(.bold)).foregroundStyle(HP.Color.text)
              Text(day.date).font(HP.Font.body).foregroundStyle(HP.Color.textMuted)
            }
            Spacer()
            HPStatusBadge(text: day.status.title, kind: day.status.badgeKind)
          }

          if day.activities.isEmpty {
            HPEmptyState(title: "No recorded activity", systemImage: "clipboard")
          } else {
            ForEach(day.activities) { activity in
              DevelopmentActivityCard(activity: activity)
            }
          }

          if !day.media.isEmpty {
            Text("Media & Files")
              .font(HP.Font.title.weight(.semibold))
              .foregroundStyle(HP.Color.text)
            ForEach(day.media) { media in
              DevelopmentMediaCard(media: media)
                .environmentObject(appState)
            }
          }
        }
        .padding(HP.Space.md)
      }
      .background(HP.Color.bg)
      .navigationTitle("Day Details")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}

private struct DevelopmentActivityCard: View {
  let activity: SDDevelopmentActivity

  var body: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 4) {
            Text(activity.title).font(HP.Font.headline).foregroundStyle(HP.Color.text)
            Text(activity.source.capitalized).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
          }
          Spacer()
          HPStatusBadge(text: activity.kind.rawValue.replacingOccurrences(of: "_", with: " ").capitalized, kind: .info)
        }
        if let subtitle = activity.subtitle, !subtitle.isEmpty {
          Text(subtitle).font(HP.Font.body).foregroundStyle(HP.Color.textMuted)
        }
        if let warning = activity.warning, !warning.isEmpty {
          Label(warning, systemImage: "exclamationmark.triangle")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.warning)
        }
        ForEach(activity.fields ?? [], id: \.key) { field in
          HStack(alignment: .top) {
            Text(field.label)
              .font(HP.Font.caption.weight(.semibold))
              .foregroundStyle(HP.Color.textMuted)
              .frame(maxWidth: 140, alignment: .leading)
            Text([field.value, field.unit].compactMap { $0 }.joined(separator: " "))
              .font(HP.Font.body)
              .foregroundStyle(HP.Color.text)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        if let notes = activity.notes, !notes.isEmpty {
          VStack(alignment: .leading, spacing: 3) {
            Text("Notes").font(HP.Font.caption.weight(.semibold)).foregroundStyle(HP.Color.textMuted)
            Text(notes).font(HP.Font.body).foregroundStyle(HP.Color.text)
          }
        }
      }
    }
  }
}

private struct DevelopmentMediaCard: View {
  @EnvironmentObject private var appState: AppState
  let media: SDDevelopmentMedia

  @State private var playbackURL: URL?
  @State private var isLoading = false
  @State private var errorText: String?

  var body: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(media.title).font(HP.Font.headline).foregroundStyle(HP.Color.text)
            Text(media.file_name ?? media.source.capitalized)
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.textMuted)
          }
          Spacer()
          HPStatusBadge(
            text: media.playback_status == .ready ? "Ready" : "Needs conversion",
            kind: media.playback_status == .ready ? .success : .warning
          )
        }

        if media.playback_status == .needsConversion {
          Text("This legacy file needs conversion to H.264/AAC MP4 before it can play on web and iOS.")
            .font(HP.Font.body)
            .foregroundStyle(HP.Color.textMuted)
        } else if let playbackURL {
          if media.kind == .importFile {
            Link(destination: playbackURL) {
              Label("Open source file", systemImage: "doc")
            }
          } else {
            VideoPlayer(player: AVPlayer(url: playbackURL))
              .frame(minHeight: 220)
              .clipShape(RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous))
          }
        } else if isLoading {
          HPLoadingState(text: "Preparing secure playback…")
        } else if let errorText {
          HPErrorState(message: errorText, onRetry: { Task { await loadPlayback() } })
        } else {
          HPButton(
            title: media.kind == .importFile ? "Open source file" : "Play video",
            systemImage: media.kind == .importFile ? "doc" : "play.fill",
            variant: .secondary,
            size: .sm,
            action: { Task { await loadPlayback() } }
          )
        }
      }
    }
    .task(id: playbackURL) {
      guard playbackURL != nil else { return }
      try? await Task.sleep(for: .seconds(840))
      guard !Task.isCancelled else { return }
      await loadPlayback()
    }
  }

  @MainActor
  private func loadPlayback() async {
    guard let service = appState.supabase, let orgId = appState.activeOrgId else {
      errorText = "Choose an organization before opening this file."
      return
    }
    isLoading = true
    errorText = nil
    defer { isLoading = false }
    do {
      let response = try await service.developmentMediaPlaybackURL(
        orgId: orgId,
        teamId: appState.selectedTeamId,
        mediaId: media.id
      )
      guard response.playback_status == .ready, let url = URL(string: response.url) else {
        errorText = "This file needs conversion before it can be opened."
        return
      }
      playbackURL = url
    } catch {
      errorText = "Secure playback could not be prepared. Try again."
    }
  }
}

private extension SDJSONValue {
  var compactText: String {
    switch self {
    case .string(let value): value
    case .bool(let value): value ? "Yes" : "No"
    case .int(let value): String(value)
    case .double(let value): String(format: "%g", value)
    case .object(let value):
      value.sorted(by: { $0.key < $1.key })
        .map { "\($0.key): \($0.value.compactText)" }
        .joined(separator: ", ")
    case .array(let value): value.map(\.compactText).joined(separator: ", ")
    case .null: ""
    }
  }
}
