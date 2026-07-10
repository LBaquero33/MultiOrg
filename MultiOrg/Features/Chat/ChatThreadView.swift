import SwiftUI

struct ChatThreadView: View {
  @EnvironmentObject private var appState: AppState
  let channel: SDChatChannel

  @State private var messages: [SDChatMessage] = []
  @State private var profileById: [UUID: Profile] = [:]
  @State private var isLoading = false
  @State private var errorText: String?

  @State private var composerText = ""
  @State private var isSending = false

  private var myId: UUID? { appState.myProfile?.id }
  private var canSend: Bool {
    if channel.isAnnouncement { return appState.myProfile?.isCoach == true }
    return true
  }

  var body: some View {
    VStack(spacing: 0) {
      threadHeader

      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 10) {
            if isLoading {
              HStack(spacing: 10) {
                ProgressView()
                Text("Loading messages...")
                  .foregroundStyle(DHDTheme.textSecondary)
              }
              .padding(.vertical, 18)
            } else if orderedMessages.isEmpty {
              emptyState
            }

            ForEach(Array(orderedMessages.enumerated()), id: \.element.id) { index, message in
              let previous = index > 0 ? orderedMessages[index - 1] : nil
              MessageRow(
                text: message.body,
                senderName: senderName(for: message.sender_id),
                isMe: message.sender_id == myId,
                createdAt: message.created_at,
                showSender: shouldShowSender(for: message, previous: previous),
                showTimestamp: shouldShowTimestamp(for: message, previous: previous)
              )
              .id(message.id)
            }
          }
          .padding(.horizontal, 18)
          .padding(.vertical, 16)
          .frame(maxWidth: .infinity)
        }
        .background(DHDTheme.pageBackground)
        .onChange(of: messages.count) { _, _ in
          guard let last = orderedMessages.last else { return }
          withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(last.id, anchor: .bottom)
          }
        }
      }

      Divider().opacity(0.35)

      composer
    }
    .background(DHDTheme.pageBackground)
    .navigationTitle(channelTitle)
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .onAppear {
      appState.setActiveChatChannel(channel.id)
    }
    .onDisappear {
      appState.clearActiveChatChannelIfCurrent(channel.id)
    }
    .task {
      appState.setActiveChatChannel(channel.id)
      await reload()
    }
    .onChange(of: appState.chatLastInsert) { _, ins in
      guard let ins, ins.channelId == channel.id else { return }
      // If we already have the message, ignore.
      if messages.contains(where: { $0.id == ins.messageId }) { return }
      // Append and mark read if we're viewing this thread.
      messages.append(SDChatMessage(
        id: ins.messageId,
        org_id: channel.org_id,
        channel_id: ins.channelId,
        sender_id: ins.senderId,
        body: ins.body,
        created_at: ins.createdAt,
        edited_at: nil,
        deleted_at: nil
      ))
      Task {
        try? await appState.supabase?.upsertMyChatReadState(channelId: channel.id, lastReadAt: Date())
      }
    }
  }

  private var channelTitle: String {
    channel.title ?? (channel.isAnnouncement ? "Announcements" : "Chat")
  }

  private var orderedMessages: [SDChatMessage] {
    messages.sorted(by: { $0.created_at < $1.created_at })
  }

  private var threadSubtitle: String {
    if channel.isAnnouncement { return "Announcements" }
    if channel.isGroup { return "Group chat" }
    let others = profileById
      .filter { $0.key != myId }
      .map { $0.value.displayName }
      .sorted()
    if !others.isEmpty { return others.joined(separator: ", ") }
    return "Direct message"
  }

  private var threadHeader: some View {
    HStack(spacing: 12) {
      ChatAvatarView(title: channelTitle == "Chat" ? threadSubtitle : channelTitle, isAnnouncement: channel.isAnnouncement, size: 46)

      VStack(alignment: .leading, spacing: 3) {
        Text(channelTitle == "Chat" ? threadSubtitle : channelTitle)
          .font(.headline)
          .foregroundStyle(DHDTheme.textPrimary)
          .lineLimit(1)
        Text(threadSubtitle)
          .font(.caption)
          .foregroundStyle(DHDTheme.textSecondary)
          .lineLimit(1)
      }

      Spacer()

      Text(channel.isDM ? "DM" : channel.isGroup ? "Group" : "Announcement")
        .font(.caption2.weight(.bold))
        .foregroundStyle(DHDTheme.accent)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(DHDTheme.accent.opacity(0.13)))
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
    .background(DHDTheme.cardBackground)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Color.white.opacity(0.08))
        .frame(height: 1)
    }
  }

  private var emptyState: some View {
    VStack(spacing: 10) {
      Image(systemName: channel.isAnnouncement ? "megaphone" : "bubble.left.and.bubble.right")
        .font(.system(size: 34, weight: .semibold))
        .foregroundStyle(DHDTheme.accent.opacity(0.75))
      Text("No messages yet")
        .font(.headline)
      Text(canSend ? "Start the conversation below." : "Announcements will appear here.")
        .font(.subheadline)
        .foregroundStyle(DHDTheme.textSecondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 70)
  }

  private var composer: some View {
    HStack(alignment: .bottom, spacing: 10) {
      TextField(canSend ? "Message" : "Coaches only", text: $composerText, axis: .vertical)
        .lineLimit(1...5)
        .textFieldStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
          RoundedRectangle(cornerRadius: 18)
            .fill(DHDTheme.surfaceElevated)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 18)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .disabled(!canSend || isSending)

      Button {
        Task { await send() }
      } label: {
        if isSending {
          ProgressView().controlSize(.small)
        } else {
          Image(systemName: "paperplane.fill")
        }
      }
      .buttonStyle(.borderedProminent)
      .clipShape(Circle())
      .disabled(!canSend || isSending || composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    .padding(.horizontal, 16)
    .padding(.top, 12)
    .padding(.bottom, 14)
    .background(DHDTheme.cardBackground)
  }

  private func senderName(for senderId: UUID?) -> String {
    guard let senderId else { return "Unknown" }
    if senderId == myId { return "You" }
    return profileById[senderId]?.displayName ?? "User"
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let msgs = try await supabase.listChatMessages(channelId: channel.id, before: nil, limit: 200)
      messages = msgs

      // Load participant profiles so we can label messages.
      let memberships = try await supabase.listChatMemberships(channelIds: [channel.id])
      let ids = Set(memberships.map(\.user_id))
      let profiles = try await supabase.listProfiles(ids: Array(ids))
      profileById = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

      // Mark read (creates membership row for announcements if missing).
      try await supabase.upsertMyChatReadState(channelId: channel.id, lastReadAt: Date())
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func shouldShowSender(for message: SDChatMessage, previous: SDChatMessage?) -> Bool {
    guard message.sender_id != myId else { return false }
    guard let previous else { return true }
    return previous.sender_id != message.sender_id || message.created_at.timeIntervalSince(previous.created_at) > 300
  }

  private func shouldShowTimestamp(for message: SDChatMessage, previous: SDChatMessage?) -> Bool {
    guard let previous else { return true }
    return message.created_at.timeIntervalSince(previous.created_at) > 900
  }

  private func send() async {
    guard let supabase = appState.supabase else { return }
    let text = composerText
    composerText = ""
    isSending = true
    defer { isSending = false }
    do {
      let msg = try await supabase.sendChatMessage(channelId: channel.id, body: text)
      messages.append(msg)
      try await supabase.upsertMyChatReadState(channelId: channel.id, lastReadAt: Date())
    } catch {
      composerText = text
      errorText = error.localizedDescription
    }
  }
}

private struct MessageRow: View {
  let text: String
  let senderName: String
  let isMe: Bool
  let createdAt: Date
  let showSender: Bool
  let showTimestamp: Bool

  var body: some View {
    VStack(spacing: 5) {
      if showTimestamp {
        Text(createdAt.formatted(date: .abbreviated, time: .shortened))
          .font(.caption2.weight(.medium))
          .foregroundStyle(DHDTheme.textSecondary)
          .padding(.vertical, 4)
      }

      HStack(alignment: .bottom, spacing: 8) {
        if isMe { Spacer(minLength: 44) }

        VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
          if showSender {
            Text(senderName)
              .font(.caption.weight(.semibold))
              .foregroundStyle(DHDTheme.textSecondary)
          }

          Text(text)
            .font(.body)
            .foregroundStyle(isMe ? .white : DHDTheme.textPrimary)
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
              UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: isMe ? 18 : 6,
                bottomTrailingRadius: isMe ? 6 : 18,
                topTrailingRadius: 18
              )
              .fill(isMe ? DHDTheme.accent : DHDTheme.surfaceElevated)
            )
        }
        .frame(maxWidth: 560, alignment: isMe ? .trailing : .leading)

        if !isMe { Spacer(minLength: 44) }
      }
    }
    .padding(.vertical, showTimestamp ? 6 : 1)
  }
}
