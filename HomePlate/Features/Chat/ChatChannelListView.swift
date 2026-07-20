import SwiftUI

struct ChatChannelListView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
  @State private var loadToken: UUID?
  @State private var loadedOrganizationId: UUID?
  @State private var readCursorByChannelId: [UUID: ChatReadCursor] = [:]

  @State private var showCreate = false
  @State private var selectedChannelId: UUID?
  @State private var detailRevision = UUID()
  @State private var navigationPath = NavigationPath()

  private var myId: UUID? { appState.myProfile?.id }

  var body: some View {
    Group {
#if os(macOS)
      if usesSplitPresentation {
        communicationLayout
      } else {
        navigationContainer
      }
#else
      navigationContainer
#endif
    }
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorText ?? "")
    }
    .task(id: chatContextIdentity) {
      resetForOrganizationChange()
      await reload()
      if let requested = appState.requestedChatChannelId {
        await openRequestedChannel(requested)
      }
    }
    .onChange(of: appState.chatLastInsert) { _, ins in
      guard let ins,
            ins.organizationId == appState.activeOrgId,
            ins.organizationId == loadedOrganizationId,
            channels.contains(where: { $0.id == ins.channelId }) else { return }
      // Update last message cache for quick UI refresh.
      lastByChannelId[ins.channelId] = SDChatLastMessageRow(
        channel_id: ins.channelId,
        body_preview: String(ins.body.prefix(140)),
        message_created_at: ins.createdAt,
        message_id: ins.messageId
      )
    }
    .onChange(of: appState.chatReadUpdate) { _, update in
      guard let update,
            update.organizationId == appState.activeOrgId,
            update.organizationId == loadedOrganizationId else { return }
      let next = ChatReadCursor(
        at: update.lastReadAt,
        messageId: update.lastReadMessageId
      )
      readCursorByChannelId[update.conversationId] = ChatReadCursor.later(
        readCursorByChannelId[update.conversationId],
        next
      )
    }
    .onChange(of: appState.requestedChatChannelId) { _, channelId in
      guard let channelId else { return }
      Task { await openRequestedChannel(channelId) }
    }
    .onChange(of: filter) { _, _ in
      syncSelectedChannel()
    }
    .onChange(of: query) { _, _ in
      syncSelectedChannel()
    }
    .onChange(of: channels.map(\.id)) { _, _ in
      syncSelectedChannel()
    }
    .onChange(of: usesSplitPresentation) { wasSplit, isSplit in
      reconcilePresentationChange(wasSplit: wasSplit, isSplit: isSplit)
    }
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

  private var usesSplitPresentation: Bool {
#if os(macOS)
    !dynamicTypeSize.isAccessibilitySize
#else
    horizontalSizeClass != .compact && !dynamicTypeSize.isAccessibilitySize
#endif
  }

  private var communicationWidthMode: HPScreenWidthMode {
#if os(macOS)
    .wide
#else
    horizontalSizeClass == .compact ? .compact : .regular
#endif
  }

  private var navigationContainer: some View {
    NavigationStack(path: $navigationPath) {
      communicationLayout
        .navigationTitle("Chat")
        .navigationDestination(for: UUID.self) { channelId in
          if let channel = channels.first(where: { $0.id == channelId }) {
            ChatThreadView(channel: channel)
              .id(channel.id)
              .environmentObject(appState)
          } else {
            HPCard {
              HPLoadingState(text: "Opening chat…")
            }
            .frame(maxWidth: 520)
            .padding(HP.Space.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HP.Color.bg)
            .task { await reload() }
          }
        }
    }
  }

  private var communicationLayout: some View {
    HPCommunicationScreenLayout(
      widthMode: communicationWidthMode,
      compactPane: .conversations
    ) { context in
      sidebar(context)
    } thread: { _ in
      detail
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
      ChatConversationSearch.matches(
        title: titleForChannel(c),
        preview: subtitleForChannel(c),
        query: q
      )
    }
  }

  private var chatContextIdentity: String {
    [
      appState.myProfile?.id.uuidString.lowercased() ?? "signed-out",
      appState.activeOrgId?.uuidString.lowercased() ?? "no-organization",
    ].joined(separator: ":")
  }

  @MainActor
  private func handleCreatedChannel(_ channelId: UUID) async {
    query = ""
    await reload()
    if let channel = channels.first(where: { $0.id == channelId }) {
      filter = filterForChannel(channel)
    }
    select(channelId)
    if !usesSplitPresentation {
      if !navigationPath.isEmpty {
        navigationPath.removeLast(navigationPath.count)
      }
      navigationPath.append(channelId)
    }
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
  private func sidebar(_ context: HPScreenLayoutContext) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPWorkspaceHeader(
          "Messages",
          context: "\(filteredChannels.count) conversation\(filteredChannels.count == 1 ? "" : "s")"
        ) {
          let layout = context.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.xs))
          layout {
            headerActions(
              fullWidth: context.isAccessibilitySize,
              newChatIsPrimary: !context.isExpanded
            )
          }
        }

        HPCard(style: .flat) {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            Text("CONVERSATION TYPE")
              .font(HP.Font.eyebrow)
              .tracking(HP.Font.eyebrowTracking)
              .foregroundStyle(HP.Color.textMuted)
            HPSegmentedControl(
              options: Filter.allCases.map { (value: $0, label: $0.rawValue) },
              selection: $filter
            )
            HPSearchBar(text: $query, placeholder: "Search messages")
          }
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Conversations") {
              HPStatusBadge(text: "\(filteredChannels.count)", kind: .neutral)
            }

            if isLoading {
              HPLoadingState(text: "Loading conversations…")
            } else if filteredChannels.isEmpty {
              HPEmptyState(
                title: "No chats yet",
                message: query.isEmpty
                  ? "Start a direct message or group conversation."
                  : "No conversations match your search.",
                systemImage: "bubble.left.and.bubble.right"
              )
            } else {
              LazyVStack(alignment: .leading, spacing: HP.Space.xs) {
                ForEach(filteredChannels) { channel in
                  conversationLink(channel, context: context)
                }
              }
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .background(HP.Color.bg)
  }

  @ViewBuilder
  private func headerActions(fullWidth: Bool, newChatIsPrimary: Bool) -> some View {
    HPButton(
      title: "Refresh",
      systemImage: "arrow.clockwise",
      variant: .secondary,
      size: .sm,
      fullWidth: fullWidth
    ) {
      Task { await reload() }
    }

    if filter != .announcements {
      HPButton(
        title: "New chat",
        systemImage: "square.and.pencil",
        variant: newChatIsPrimary ? .primary : .secondary,
        size: .sm,
        fullWidth: fullWidth
      ) {
        showCreate = true
      }
    }
  }

  @ViewBuilder
  private var detail: some View {
    if let selectedChannelId, let channel = channels.first(where: { $0.id == selectedChannelId }) {
      ChatThreadView(channel: channel)
        .id(detailRevision)
        .environmentObject(appState)
    } else {
      HPCard {
        HPEmptyState(
          title: "Select a chat",
          message: "Choose a direct message, group, or announcement to view messages.",
          systemImage: "bubble.left.and.bubble.right"
        )
      }
      .frame(maxWidth: 560)
      .padding(HP.Space.md)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(HP.Color.bg)
    }
  }

  @ViewBuilder
  private func conversationLink(
    _ channel: SDChatChannel,
    context: HPScreenLayoutContext
  ) -> some View {
    let row = ChatChannelRowView(
      title: titleForChannel(channel),
      subtitle: subtitleForChannel(channel),
      timestamp: timestampForChannel(channel),
      unread: isUnread(channel),
      isAnnouncement: channel.isAnnouncement,
      isSelected: context.isExpanded && selectedChannelId == channel.id
    )

    if context.isExpanded {
      Button { select(channel.id) } label: { row }
        .buttonStyle(.plain)
        .accessibilityHint("Opens this conversation")
    } else {
      Button {
        select(channel.id)
        navigationPath.append(channel.id)
      } label: {
        row
      }
        .buttonStyle(.plain)
        .accessibilityHint("Opens this conversation")
    }
  }

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

  private func timestampForChannel(_ channel: SDChatChannel) -> String? {
    guard let date = lastByChannelId[channel.id]?.message_created_at ?? channel.created_at else {
      return nil
    }
    if Calendar.current.isDateInToday(date) {
      return date.formatted(date: .omitted, time: .shortened)
    }
    return date.formatted(date: .abbreviated, time: .omitted)
  }

  private func isUnread(_ c: SDChatChannel) -> Bool {
    let membershipCursor = myMembershipByChannelId[c.id].flatMap { membership in
      membership.last_read_at.map {
        ChatReadCursor(at: $0, messageId: membership.last_read_message_id)
      }
    }
    let mine = ChatReadCursor.later(
      membershipCursor,
      readCursorByChannelId[c.id]
    )
    return ChatUnreadState.isUnread(
      lastMessageAt: lastByChannelId[c.id]?.message_created_at,
      lastMessageId: lastByChannelId[c.id]?.message_id,
      lastReadAt: mine?.at,
      lastReadMessageId: mine?.messageId
    )
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    guard let organizationId = appState.activeOrgId else {
      resetForOrganizationChange()
      return
    }
    let token = UUID()
    loadToken = token
    isLoading = true
    do {
      let ch = try await supabase.listChatChannels(organizationId: organizationId)
      guard accepts(organizationId: organizationId, token: token) else { return }
      channels = ch
      loadedOrganizationId = organizationId

      let ids = ch.map(\.id)
      let last = try await supabase.listChatLastMessages(channelIds: ids)
      guard accepts(organizationId: organizationId, token: token) else { return }
      lastByChannelId = Dictionary(uniqueKeysWithValues: last.map { ($0.channel_id, $0) })

      let myMemberships = try await supabase.listMyChatMemberships(organizationId: organizationId)
      guard accepts(organizationId: organizationId, token: token) else { return }
      myMembershipByChannelId = Dictionary(uniqueKeysWithValues: myMemberships.map { ($0.channel_id, $0) })
      readCursorByChannelId = Dictionary(uniqueKeysWithValues: myMemberships.compactMap { membership in
        membership.last_read_at.map {
          (
            membership.channel_id,
            ChatReadCursor(at: $0, messageId: membership.last_read_message_id)
          )
        }
      })

      let allMemberships = try await supabase.listChatMemberships(
        channelIds: ids,
        organizationId: organizationId
      )
      guard accepts(organizationId: organizationId, token: token) else { return }
      membershipsByChannelId = Dictionary(grouping: allMemberships, by: \.channel_id)

      // Load participant profiles so DMs can display the other user name.
      let userIds = Set(allMemberships.map(\.user_id))
      let profiles = try await supabase.listProfiles(ids: Array(userIds))
      guard accepts(organizationId: organizationId, token: token) else { return }
      profileById = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
      isLoading = false

      syncSelectedChannel()
    } catch {
      guard accepts(organizationId: organizationId, token: token) else { return }
      errorText = SDApplicationErrorClassifier.alertMessage(
        for: error,
        taskIsCancelled: Task.isCancelled
      )
      isLoading = false
    }
  }

  private func accepts(organizationId: UUID, token: UUID) -> Bool {
    ChatContextGuard.accepts(
      responseOrganizationId: organizationId,
      responseToken: token,
      activeOrganizationId: appState.activeOrgId,
      currentToken: loadToken
    ) && !Task.isCancelled
  }

  private func resetForOrganizationChange() {
    loadToken = nil
    loadedOrganizationId = nil
    channels = []
    membershipsByChannelId = [:]
    myMembershipByChannelId = [:]
    lastByChannelId = [:]
    profileById = [:]
    readCursorByChannelId = [:]
    query = ""
    errorText = nil
    isLoading = false
    selectedChannelId = nil
    detailRevision = UUID()
    navigationPath = NavigationPath()
  }

  private func select(_ channelId: UUID) {
    guard selectedChannelId != channelId else { return }
    selectedChannelId = channelId
    detailRevision = UUID()
  }

  private func reconcilePresentationChange(wasSplit: Bool, isSplit: Bool) {
    guard wasSplit != isSplit else { return }
    if isSplit {
      navigationPath = NavigationPath()
    } else if let selectedChannelId {
      navigationPath = NavigationPath()
      navigationPath.append(selectedChannelId)
    }
  }

  private func syncSelectedChannel() {
    let validIds = Set(filteredChannels.map(\.id))
    if let selectedChannelId, validIds.contains(selectedChannelId) {
      return
    }
#if os(macOS)
    if let first = filteredChannels.first {
      select(first.id)
    } else {
      selectedChannelId = nil
      detailRevision = UUID()
    }
#else
    selectedChannelId = nil
    detailRevision = UUID()
#endif
  }

  private func filterForChannel(_ channel: SDChatChannel) -> Filter {
    if channel.isGroup { return .groups }
    if channel.isAnnouncement { return .announcements }
    return .dms
  }

  private func openRequestedChannel(_ channelId: UUID) async {
    if !channels.contains(where: { $0.id == channelId }) {
      await reload()
    }
    guard let channel = channels.first(where: {
      $0.id == channelId && $0.org_id == appState.activeOrgId
    }) else {
      appState.requestedChatChannelId = nil
      appState.globalToastText = "That conversation is no longer available for this organization."
      return
    }
    filter = filterForChannel(channel)
    select(channelId)
    if !usesSplitPresentation {
      navigationPath = NavigationPath()
      navigationPath.append(channelId)
    }
    appState.requestedChatChannelId = nil
  }
}

private struct ChatChannelRowView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let title: String
  let subtitle: String
  let timestamp: String?
  let unread: Bool
  let isAnnouncement: Bool
  let isSelected: Bool

  var body: some View {
    HStack(alignment: .top, spacing: HP.Space.sm) {
      ChatAvatarView(title: title, isAnnouncement: isAnnouncement, size: 42)

      VStack(alignment: .leading, spacing: HP.Space.xs) {
        let layout = dynamicTypeSize.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.xs))
          : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: HP.Space.xs))
        layout {
          conversationTitle
          if !dynamicTypeSize.isAccessibilitySize {
            Spacer(minLength: HP.Space.xs)
          }
          conversationMetadata
        }

        Text(subtitle.isEmpty ? "No messages yet" : subtitle)
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(HP.Space.sm)
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
        .fill(isSelected ? HP.Color.surfaceRaised : unread ? HP.Color.accent.opacity(0.10) : .clear)
    )
    .overlay(
      RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
        .strokeBorder(isSelected ? HP.Color.borderStrong : .clear, lineWidth: 1)
        .allowsHitTesting(false)
    )
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityValue(isSelected ? "Selected" : unread ? "Unread" : "Read")
  }

  private var conversationTitle: some View {
    Text(title)
      .font(unread ? HP.Font.headline : HP.Font.callout.weight(.medium))
      .foregroundStyle(HP.Color.text)
      .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var conversationMetadata: some View {
    HStack(spacing: HP.Space.xs) {
      if let timestamp {
        Text(timestamp)
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
      if unread {
        HPStatusBadge(text: "New", kind: .gold)
      }
    }
  }
}

struct ChatAvatarView: View {
  let title: String
  let isAnnouncement: Bool
  let size: CGFloat

  var body: some View {
    HPAvatar(
      name: title.isEmpty ? "DM" : title,
      systemImage: isAnnouncement ? "megaphone.fill" : nil,
      size: size < 40 ? .sm : size > 54 ? .lg : .md,
      tint: isAnnouncement ? HP.Color.warning : HP.Color.primary
    )
  }
}
