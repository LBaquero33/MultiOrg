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
  @State private var isLoadingPlayers = false
  @State private var isLoadingWorkspace = false
  @State private var errorText: String?

  private let visibleSections = [
    "Player Hub",
    "Calendar",
    "Programs",
    "Testing",
    "Sessions & Data",
    "Media",
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPWorkspaceHeader(
          "Programs & Development",
          orgLabel: organizationName,
          context: "The same programs, results, sessions, and media shown on the website."
        )

        sectionPicker

        if isLoadingPlayers && players.isEmpty {
          HPLoadingState(text: "Loading players…")
        } else if let errorText, players.isEmpty {
          HPErrorState(message: errorText, onRetry: { Task { await reloadPlayers() } })
        } else if players.isEmpty {
          HPEmptyState(
            title: "No players available",
            message: "Your organization and team access determine which players appear here.",
            systemImage: "person.3"
          )
        } else {
          playerSelector
          workspaceContent
        }
      }
      .padding(HP.Space.md)
      .frame(maxWidth: 1100, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .background(HP.Color.bg)
    .task(id: contextKey) { await reloadPlayers() }
    .sheet(item: $selectedDay) { day in
      DevelopmentDayDetailSheet(
        playerName: workspace?.player.name ?? "Player",
        day: day
      )
      .environmentObject(appState)
    }
  }

  private var contextKey: String {
    "\(appState.activeOrgId?.uuidString ?? "none"):\(appState.selectedTeamId?.uuidString ?? "all"):\(appState.teamContextToken.uuidString)"
  }

  private var initialSection: String {
    if appState.myProfile?.isPlayer == true || appState.myProfile?.isParent == true {
      return "Calendar"
    }
    return "Player Hub"
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
    guard !query.isEmpty else { return players }
    return players.filter { $0.name.localizedCaseInsensitiveContains(query) }
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
                Task { await reloadWorkspace(playerId: player.id) }
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
          onRetry: { Task { await reloadWorkspace(playerId: workspace.player.id) } }
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
        Task { await reloadWorkspace(playerId: selectedPlayerId) }
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
    selectedSection = initialSection
    players = []
    workspace = nil
    selectedPlayerId = nil
    errorText = nil
    guard let service = appState.supabase, let orgId = appState.activeOrgId else {
      errorText = "Choose an organization to view player development."
      return
    }
    isLoadingPlayers = true
    defer { isLoadingPlayers = false }
    do {
      let loaded = try await service.listDevelopmentWorkspacePlayers(
        orgId: orgId,
        teamId: appState.selectedTeamId
      )
      guard appState.activeOrgId == orgId else { return }
      players = loaded
      if let first = loaded.first {
        selectedPlayerId = first.id
        await reloadWorkspace(playerId: first.id)
      }
    } catch {
      errorText = "Player development could not be loaded. Check your access and try again."
    }
  }

  @MainActor
  private func reloadWorkspace(playerId: UUID) async {
    errorText = nil
    guard let service = appState.supabase, let orgId = appState.activeOrgId else { return }
    isLoadingWorkspace = true
    defer { isLoadingWorkspace = false }
    let calendar = Calendar(identifier: .gregorian)
    let now = Date()
    let start = calendar.date(byAdding: .year, value: -1, to: now) ?? now
    let end = calendar.date(byAdding: .year, value: 1, to: now) ?? now
    do {
      let loaded = try await service.fetchDevelopmentWorkspace(
        orgId: orgId,
        playerId: playerId,
        teamId: appState.selectedTeamId,
        startDate: Self.isoDate(start),
        endDate: Self.isoDate(end)
      )
      guard appState.activeOrgId == orgId, selectedPlayerId == playerId else { return }
      workspace = loaded
    } catch {
      errorText = "The latest player results could not be refreshed."
    }
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
        ForEach(activity.details.sorted(by: { $0.key < $1.key }).filter { !$0.value.compactText.isEmpty }, id: \.key) { key, value in
          HStack(alignment: .top) {
            Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
              .font(HP.Font.caption.weight(.semibold))
              .foregroundStyle(HP.Color.textMuted)
              .frame(maxWidth: 140, alignment: .leading)
            Text(value.compactText)
              .font(HP.Font.body)
              .foregroundStyle(HP.Color.text)
              .frame(maxWidth: .infinity, alignment: .leading)
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
