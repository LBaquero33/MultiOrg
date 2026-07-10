import SwiftUI

struct ChatChannelListView: View {
  @EnvironmentObject private var appState: AppState

  enum Filter: String, CaseIterable, Identifiable {
    case dms = "DMs"
    case groups = "Groups"
    case announcements = "Announcements"
    var id: String { rawValue }
  }

  @State private var filter: Filter = .dms
  @State private var channels: [SDChatChannel] = []
  @State private var membershipsByChannelId: [UUID: [SDChatMembership]] = [:]
  @State private var myMembershipByChannelId: [UUID: SDChatMembership] = [:]
  @State private var lastByChannelId: [UUID: SDChatLastMessageRow] = [:]
  @State private var profileById: [UUID: Profile] = [:]

  @State private var isLoading = false
  @State private var errorText: String?
  @State private var query = ""

  @State private var showCreate = false

#if os(macOS)
  @State private var selectedChannelId: UUID?
  @State private var detailRevision = UUID()
#else
  @State private var navigationPath = NavigationPath()
#endif

  private var myId: UUID? { appState.myProfile?.id }

  var body: some View {
    Group {
#if os(macOS)
      HStack(spacing: 0) {
        sidebar
          .frame(width: 320)
          .background(DHDTheme.pageBackground)
          .overlay(alignment: .trailing) {
            Rectangle()
              .fill(Color.white.opacity(0.08))
              .frame(width: 1)
          }

        detail
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
#else
      NavigationStack(path: $navigationPath) {
        sidebar
          .navigationTitle("Chat")
          .navigationDestination(for: UUID.self) { channelId in
            if let channel = channels.first(where: { $0.id == channelId }) {
              ChatThreadView(channel: channel)
                .id(channel.id)
                .environmentObject(appState)
            } else {
              VStack(spacing: 10) {
                ProgressView()
                Text("Opening chat...")
                  .foregroundStyle(.secondary)
              }
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .task { await reload() }
            }
          }
      }
#endif
    }
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorText ?? "")
    }
    .task { await reload() }
    .onChange(of: appState.chatLastInsert) { _, ins in
      guard let ins else { return }
      // Update last message cache for quick UI refresh.
      lastByChannelId[ins.channelId] = SDChatLastMessageRow(
        channel_id: ins.channelId,
        body_preview: String(ins.body.prefix(140)),
        message_created_at: ins.createdAt
      )
    }
    .onChange(of: appState.requestedChatChannelId) { _, channelId in
      guard let channelId else { return }
      Task { await openRequestedChannel(channelId) }
    }
#if os(macOS)
    .onChange(of: filter) { _, _ in
      syncSelectedChannel()
    }
    .onChange(of: query) { _, _ in
      syncSelectedChannel()
    }
    .onChange(of: channels.map(\.id)) { _, _ in
      syncSelectedChannel()
    }
#endif
    .sheet(isPresented: $showCreate) {
      NavigationStack {
        ChatCreateView { channelId in
          Task { await handleCreatedChannel(channelId) }
        }
        .environmentObject(appState)
      }
      #if os(macOS)
      .frame(minWidth: 720, minHeight: 640)
      #endif
    }
  }

  private var filteredChannels: [SDChatChannel] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let base = channels.filter { c in
      switch filter {
      case .dms: return c.isDM
      case .groups: return c.isGroup
      case .announcements: return c.isAnnouncement
      }
    }

    guard !q.isEmpty else { return sortChannels(base) }
    return sortChannels(base).filter { c in
      titleForChannel(c).lowercased().contains(q)
    }
  }

  @MainActor
  private func handleCreatedChannel(_ channelId: UUID) async {
    query = ""
    await reload()
    if let channel = channels.first(where: { $0.id == channelId }) {
      filter = filterForChannel(channel)
    }
#if os(macOS)
    select(channelId)
#else
    if !navigationPath.isEmpty {
      navigationPath.removeLast(navigationPath.count)
    }
    navigationPath.append(channelId)
#endif
  }

  private func sortChannels(_ items: [SDChatChannel]) -> [SDChatChannel] {
    // Announcements: pinned_rank asc, then newest
    if filter == .announcements {
      return items.sorted { a, b in
        let ar = a.pinned_rank ?? 999
        let br = b.pinned_rank ?? 999
        if ar != br { return ar < br }
        let at = lastByChannelId[a.id]?.message_created_at ?? a.created_at ?? .distantPast
        let bt = lastByChannelId[b.id]?.message_created_at ?? b.created_at ?? .distantPast
        return at > bt
      }
    }

    // DM/Group: newest message first
    return items.sorted { a, b in
      let at = lastByChannelId[a.id]?.message_created_at ?? a.created_at ?? .distantPast
      let bt = lastByChannelId[b.id]?.message_created_at ?? b.created_at ?? .distantPast
      return at > bt
    }
  }

  @ViewBuilder
  private var sidebar: some View {
    List {
      Section {
        Picker("Chat filter", selection: $filter) {
          ForEach(Filter.allCases) { f in
            Text(f.rawValue).tag(f)
          }
        }
        .pickerStyle(.segmented)

        TextField("Search", text: $query)
          .textFieldStyle(.roundedBorder)
      }

      if isLoading {
        Section {
          HStack(spacing: 10) { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
        }
      } else if filteredChannels.isEmpty {
        Section {
          Text("No chats yet.")
            .foregroundStyle(.secondary)
        }
      } else {
        Section {
          ForEach(filteredChannels) { c in
#if os(macOS)
            Button {
              select(c.id)
            } label: {
              ChatChannelRowView(
                title: titleForChannel(c),
                subtitle: subtitleForChannel(c),
                unread: isUnread(c),
                isAnnouncement: c.isAnnouncement
              )
            }
            .buttonStyle(.plain)
#else
            NavigationLink(value: c.id) {
              ChatChannelRowView(
                title: titleForChannel(c),
                subtitle: subtitleForChannel(c),
                unread: isUnread(c),
                isAnnouncement: c.isAnnouncement
              )
            }
#endif
          }
        }
      }
    }
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        Button {
          Task { await reload() }
        } label: { Image(systemName: "arrow.clockwise") }

        if filter != .announcements {
          Button {
            showCreate = true
          } label: { Image(systemName: "square.and.pencil") }
        }
      }
    }
  }

#if os(macOS)
  @ViewBuilder
  private var detail: some View {
    if let selectedChannelId, let channel = channels.first(where: { $0.id == selectedChannelId }) {
      ChatThreadView(channel: channel)
        .id(detailRevision)
        .environmentObject(appState)
    } else {
      VStack(spacing: 10) {
        Text("Select a chat")
          .font(.title3.weight(.semibold))
        Text("Choose a DM, group, or announcement to view messages.")
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(DHDTheme.pageBackground)
    }
  }
#endif

  private func titleForChannel(_ c: SDChatChannel) -> String {
    if c.isAnnouncement { return c.title ?? "Announcements" }
    if c.isGroup { return c.title ?? "Group chat" }
    // DM: show other participant name.
    guard let me = myId else { return "DM" }
    let members = membershipsByChannelId[c.id] ?? []
    let other = members.first(where: { $0.user_id != me })?.user_id
    if let other, let p = profileById[other] { return p.displayName }
    return "Direct message"
  }

  private func subtitleForChannel(_ c: SDChatChannel) -> String {
    if let last = lastByChannelId[c.id], let preview = last.body_preview, !preview.isEmpty {
      return preview
    }
    if c.isAnnouncement { return "Coach announcements" }
    return "No messages yet"
  }

  private func isUnread(_ c: SDChatChannel) -> Bool {
    guard let last = lastByChannelId[c.id]?.message_created_at else { return false }
    let mine = myMembershipByChannelId[c.id]?.last_read_at
    if let mine { return last > mine }
    // No membership row yet (common for announcements): treat as unread if there is any message.
    return true
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let ch = try await supabase.listChatChannels()
      channels = ch

      let ids = ch.map(\.id)
      let last = try await supabase.listChatLastMessages(channelIds: ids)
      lastByChannelId = Dictionary(uniqueKeysWithValues: last.map { ($0.channel_id, $0) })

      let myMemberships = try await supabase.listMyChatMemberships()
      myMembershipByChannelId = Dictionary(uniqueKeysWithValues: myMemberships.map { ($0.channel_id, $0) })

      let allMemberships = try await supabase.listChatMemberships(channelIds: ids)
      membershipsByChannelId = Dictionary(grouping: allMemberships, by: \.channel_id)

      // Load participant profiles so DMs can display the other user name.
      let userIds = Set(allMemberships.map(\.user_id))
      let profiles = try await supabase.listProfiles(ids: Array(userIds))
      profileById = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

#if os(macOS)
      syncSelectedChannel()
#endif
    } catch {
      errorText = error.localizedDescription
    }
  }

#if os(macOS)
  private func select(_ channelId: UUID) {
    guard selectedChannelId != channelId else { return }
    selectedChannelId = channelId
    detailRevision = UUID()
  }

  private func syncSelectedChannel() {
    let validIds = Set(filteredChannels.map(\.id))
    if let selectedChannelId, validIds.contains(selectedChannelId) {
      return
    }
    if let first = filteredChannels.first {
      select(first.id)
    } else {
      selectedChannelId = nil
      detailRevision = UUID()
    }
  }
#endif

  private func filterForChannel(_ channel: SDChatChannel) -> Filter {
    if channel.isGroup { return .groups }
    if channel.isAnnouncement { return .announcements }
    return .dms
  }

  private func openRequestedChannel(_ channelId: UUID) async {
    if !channels.contains(where: { $0.id == channelId }) {
      await reload()
    }
    guard let channel = channels.first(where: { $0.id == channelId }) else { return }
    filter = filterForChannel(channel)
#if os(macOS)
    select(channelId)
#else
    navigationPath = NavigationPath()
    navigationPath.append(channelId)
#endif
    appState.requestedChatChannelId = nil
  }
}

private struct ChatChannelRowView: View {
  let title: String
  let subtitle: String
  let unread: Bool
  let isAnnouncement: Bool

  var body: some View {
    HStack(spacing: 12) {
      ChatAvatarView(title: title, isAnnouncement: isAnnouncement, size: 42)

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 8) {
          Text(title)
            .font(.subheadline.weight(unread ? .semibold : .medium))
            .foregroundStyle(DHDTheme.textPrimary)
            .lineLimit(1)
          Spacer(minLength: 8)
          if unread {
            Text("New")
              .font(.caption2.weight(.bold))
              .foregroundStyle(.white)
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(Capsule().fill(DHDTheme.accent))
          }
        }

        Text(subtitle.isEmpty ? "No messages yet" : subtitle)
          .font(.caption)
          .foregroundStyle(DHDTheme.textSecondary)
          .lineLimit(1)
      }
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 8)
    .background(
      RoundedRectangle(cornerRadius: 14)
        .fill(unread ? DHDTheme.accent.opacity(0.10) : Color.clear)
    )
  }
}

struct ChatAvatarView: View {
  let title: String
  let isAnnouncement: Bool
  let size: CGFloat

  var body: some View {
    ZStack {
      Circle()
        .fill(isAnnouncement ? Color.orange.opacity(0.18) : DHDTheme.accent.opacity(0.16))
      if isAnnouncement {
        Image(systemName: "megaphone.fill")
          .font(.system(size: size * 0.40, weight: .semibold))
          .foregroundStyle(.orange)
      } else {
        Text(initials)
          .font(.system(size: size * 0.34, weight: .bold))
          .foregroundStyle(DHDTheme.accent)
      }
    }
    .frame(width: size, height: size)
    .overlay(Circle().strokeBorder(DHDTheme.accent.opacity(0.18), lineWidth: 1))
  }

  private var initials: String {
    let parts = title
      .split(separator: " ")
      .prefix(2)
      .compactMap { $0.first }
      .map(String.init)
    let value = parts.joined()
    return value.isEmpty ? "DM" : value.uppercased()
  }
}
