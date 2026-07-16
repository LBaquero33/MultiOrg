import SwiftUI

struct ChatThreadView: View {
  @EnvironmentObject private var appState: AppState
  let channel: SDChatChannel

  @State private var messages: [SDChatMessage] = []
  @State private var profileById: [UUID: Profile] = [:]
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var loadToken: UUID?

  @State private var composerText = ""
  @State private var isSending = false
  @State private var sendErrorText: String?
  @State private var sendOperation = ChatSendOperationState()

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
    .task(id: chatContextIdentity) {
      appState.setActiveChatChannel(channel.id)
      await reload()
    }
    .onChange(of: appState.chatLastInsert) { _, ins in
      guard let ins,
            ins.organizationId == channel.org_id,
            ins.organizationId == appState.activeOrgId,
            ins.channelId == channel.id else { return }
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
        await markRead(through: ins.messageId)
      }
    }
    .onChange(of: appState.chatReadUpdate) { _, update in
      guard let update,
            update.organizationId == channel.org_id,
            update.conversationId == channel.id,
            !messages.contains(where: { $0.id == update.throughMessageId }) else { return }
      Task { await reload() }
    }
  }

  private var chatContextIdentity: String {
    "\(channel.id.uuidString.lowercased()):\(appState.activeOrgId?.uuidString.lowercased() ?? "none")"
  }

  private var channelTitle: String {
    channel.title ?? (channel.isAnnouncement ? "Announcements" : "Chat")
  }

  private var orderedMessages: [SDChatMessage] {
    messages.sorted { lhs, rhs in
      if lhs.created_at != rhs.created_at {
        return lhs.created_at < rhs.created_at
      }
      return lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
    }
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
    VStack(alignment: .leading, spacing: 8) {
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

      if let sendErrorText {
        HStack(spacing: 10) {
          Label(sendErrorText, systemImage: "exclamationmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
          Spacer()
          Button("Retry") { Task { await send() } }
            .buttonStyle(.bordered)
            .disabled(isSending || composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      } else if sendOperation.status == .sent {
        Label("Sent", systemImage: "checkmark.circle.fill")
          .font(.footnote)
          .foregroundStyle(.green)
      }
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
    guard let organizationId = channel.org_id,
          organizationId == appState.activeOrgId else {
      loadToken = nil
      isLoading = false
      messages = []
      profileById = [:]
      errorText = "Switch back to this conversation's organization to view it."
      return
    }
    let token = UUID()
    loadToken = token
    isLoading = true
    do {
      let msgs = try await supabase.listChatMessages(
        channelId: channel.id,
        organizationId: organizationId,
        before: nil,
        limit: 200
      )
      guard loadToken == token, appState.activeOrgId == organizationId else { return }
      messages = msgs

      // Load participant profiles so we can label messages.
      let memberships = try await supabase.listChatMemberships(
        channelIds: [channel.id],
        organizationId: organizationId
      )
      guard loadToken == token, appState.activeOrgId == organizationId else { return }
      let ids = Set(memberships.map(\.user_id))
      let profiles = try await supabase.listProfiles(ids: Array(ids))
      guard loadToken == token, appState.activeOrgId == organizationId else { return }
      profileById = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

      if let latest = orderedMessages.last {
        await markRead(through: latest.id)
      }
      guard loadToken == token, appState.activeOrgId == organizationId else { return }
      isLoading = false
    } catch {
      guard loadToken == token, appState.activeOrgId == organizationId else { return }
      errorText = error.localizedDescription
      isLoading = false
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
    guard channel.org_id == appState.activeOrgId else {
      sendErrorText = "This conversation belongs to a different organization."
      return
    }
    let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let clientMessageId = sendOperation.begin(
      channelId: channel.id,
      body: text
    ) else { return }
    composerText = ""
    sendErrorText = nil
    isSending = true
    defer { isSending = false }
    do {
      let response = try await supabase.sendChatMessage(
        channelId: channel.id,
        body: text,
        clientMessageId: clientMessageId
      )
      if !messages.contains(where: { $0.id == response.message.id }) {
        messages.append(response.message)
      }
      sendOperation.finish(success: true)
      await markRead(through: response.message.id)
    } catch {
      sendOperation.finish(success: false)
      composerText = text
      let failure = error.localizedDescription.lowercased()
      if failure.contains("chat_idempotency_conflict") {
        sendErrorText = "This retry no longer matches the original message. Review the draft and send again."
      } else if failure.contains("membership") || failure.contains("participant") || failure.contains("42501") {
        sendErrorText = "You no longer have permission to send in this conversation."
      } else {
        sendErrorText = "Message could not be sent. Your draft is preserved; try again."
      }
    }
  }

  private func markRead(through messageId: UUID) async {
    guard let supabase = appState.supabase,
          channel.org_id == appState.activeOrgId else { return }
    do {
      let result = try await supabase.markChatConversationRead(
        channelId: channel.id,
        throughMessageId: messageId
      )
      appState.recordChatRead(result)
    } catch {
      // Message content remains available. A later reload or realtime event can
      // safely retry the exact authoritative read boundary.
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
