import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ChatThreadView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
  @State private var attachmentsByMessage: [UUID: [SDChatAttachment]] = [:]
  @State private var signedAttachmentURLs: [UUID: URL] = [:]
  @State private var pendingAttachments: [PendingChatAttachment] = []
  @State private var photoPickerItem: PhotosPickerItem?
  @State private var isShowingFileImporter = false

  private var myId: UUID? { appState.myProfile?.id }
  private var canSend: Bool {
    if channel.isAnnouncement { return appState.myProfile?.isCoach == true }
    return true
  }

  var body: some View {
    VStack(spacing: HP.Space.sm) {
      threadHeader

      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: HP.Space.sm) {
            if isLoading {
              HPCard(style: .flat) {
                HPLoadingState(text: "Loading messages…")
              }
            } else if orderedMessages.isEmpty {
              emptyState
            }

            ForEach(Array(orderedMessages.enumerated()), id: \.element.id) { index, message in
              let previous = index > 0 ? orderedMessages[index - 1] : nil
              MessageRow(
                text: message.body,
                senderName: senderName(for: message.sender_id),
                senderProfile: message.sender_id.flatMap { profileById[$0] },
                isMe: message.sender_id == myId,
                createdAt: message.created_at,
                attachments: attachmentsByMessage[message.id] ?? [],
                attachmentURLs: signedAttachmentURLs,
                showSender: shouldShowSender(for: message, previous: previous),
                showTimestamp: shouldShowTimestamp(for: message, previous: previous)
              )
              .id(message.id)
            }
          }
          .padding(.vertical, HP.Space.xs)
          .frame(maxWidth: .infinity)
        }
        .background(HP.Color.bg)
        .onChange(of: messages.count) { _, _ in
          guard let last = orderedMessages.last else { return }
          withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(last.id, anchor: .bottom)
          }
        }
      }

      Divider().overlay(HP.Color.border)

      composer
    }
    .padding(HP.Space.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(HP.Color.bg)
    .navigationTitle(channelTitle)
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .fileImporter(
      isPresented: $isShowingFileImporter,
      allowedContentTypes: [.image, .pdf, .plainText, .commaSeparatedText, .data],
      allowsMultipleSelection: true
    ) { result in
      handleImportedFiles(result)
    }
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
    HPCard(style: .flat) {
      let layout = dynamicTypeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
        : AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.sm))
      layout {
        HStack(alignment: .top, spacing: HP.Space.sm) {
          if channel.isAnnouncement || profileById.isEmpty {
            ChatAvatarView(
              title: channelTitle == "Chat" ? threadSubtitle : channelTitle,
              isAnnouncement: channel.isAnnouncement,
              size: 46
            )
          } else {
            HStack(spacing: -10) {
              ForEach(
                profileById.values
                  .filter { $0.id != myId }
                  .sorted { $0.displayName < $1.displayName }
                  .prefix(3)
              ) { profile in
                HPProfileAvatarButton(profile: profile, size: .md)
              }
            }
          }

          VStack(alignment: .leading, spacing: 3) {
            Text(channelTitle == "Chat" ? threadSubtitle : channelTitle)
              .font(HP.Font.headline)
              .foregroundStyle(HP.Color.text)
              .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
              .fixedSize(horizontal: false, vertical: true)
            Text(threadSubtitle)
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.textMuted)
              .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
              .fixedSize(horizontal: false, vertical: true)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }

        if !dynamicTypeSize.isAccessibilitySize {
          Spacer(minLength: HP.Space.sm)
        }

        HPStatusBadge(
          text: channel.isDM ? "DM" : channel.isGroup ? "Group" : "Announcement",
          kind: channel.isAnnouncement ? .warning : .info
        )
      }
    }
  }

  private var emptyState: some View {
    HPCard(style: .flat) {
      HPEmptyState(
        title: "No messages yet",
        message: canSend ? "Start the conversation below." : "Announcements will appear here.",
        systemImage: channel.isAnnouncement ? "megaphone" : "bubble.left.and.bubble.right"
      )
    }
  }

  private var composer: some View {
    HPCard(style: .flat) {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HStack(spacing: HP.Space.xs) {
          PhotosPicker(selection: $photoPickerItem, matching: .images) {
            Label("Photo", systemImage: "photo.badge.plus")
          }
          .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            Task { await addPhoto(item) }
          }
          Button { isShowingFileImporter = true } label: {
            Label("File", systemImage: "paperclip")
          }
        }
        .buttonStyle(.bordered)
        .disabled(!canSend || isSending)

        if !pendingAttachments.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HP.Space.xs) {
              ForEach(pendingAttachments) { attachment in
                HStack(spacing: 5) {
                  Image(systemName: attachment.isImage ? "photo" : "doc")
                  Text(attachment.fileName).lineLimit(1)
                  Button {
                    pendingAttachments.removeAll(where: { $0.id == attachment.id })
                    sendOperation.clear()
                  } label: {
                    Image(systemName: "xmark.circle.fill")
                  }
                  .buttonStyle(.plain)
                  .accessibilityLabel("Remove \(attachment.fileName)")
                }
                .font(HP.Font.caption)
                .padding(.horizontal, HP.Space.xs)
                .padding(.vertical, 6)
                .background(HP.Color.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: HP.Radius.sm))
              }
            }
          }
        }

        let layout = dynamicTypeSize.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
          : AnyLayout(HStackLayout(alignment: .bottom, spacing: HP.Space.sm))
        layout {
          HPFormField(
            label: "Message",
            text: $composerText,
            kind: .multiline,
            placeholder: canSend ? "Write a message" : "Coaches only",
            isEnabled: canSend && !isSending
          )

          HPButton(
            title: "Send",
            systemImage: "paperplane.fill",
            variant: .primary,
            size: .md,
            isLoading: isSending,
            fullWidth: dynamicTypeSize.isAccessibilitySize
          ) {
            Task { await send() }
          }
          .disabled(
            !canSend
              || isSending
              || (composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && pendingAttachments.isEmpty)
          )
        }

        if let sendErrorText {
          let errorLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.sm))
          errorLayout {
            sendFailureLabel(sendErrorText)
            if !dynamicTypeSize.isAccessibilitySize {
              Spacer(minLength: HP.Space.sm)
            }
            retryButton(fullWidth: dynamicTypeSize.isAccessibilitySize)
          }
        } else if sendOperation.status == .sent {
          Label("Sent", systemImage: "checkmark.circle.fill")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.success)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private func sendFailureLabel(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.circle.fill")
      .font(HP.Font.caption)
      .foregroundStyle(HP.Color.danger)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func retryButton(fullWidth: Bool) -> some View {
    HPButton(
      title: "Retry",
      systemImage: "arrow.clockwise",
      variant: .secondary,
      size: .sm,
      fullWidth: fullWidth
    ) {
      Task { await send() }
    }
    .disabled(
      isSending || (composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && pendingAttachments.isEmpty)
    )
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
      guard accepts(organizationId: organizationId, token: token) else { return }
      messages = msgs

      let loadedAttachments = try await supabase.listChatAttachments(messageIds: msgs.map(\.id))
      guard accepts(organizationId: organizationId, token: token) else { return }
      attachmentsByMessage = Dictionary(grouping: loadedAttachments, by: \.message_id)
      var loadedURLs: [UUID: URL] = [:]
      for attachment in loadedAttachments {
        if let url = try? await supabase.signedChatAttachmentURL(path: attachment.storage_path) {
          loadedURLs[attachment.id] = url
        }
      }
      guard accepts(organizationId: organizationId, token: token) else { return }
      signedAttachmentURLs = loadedURLs

      // Load participant profiles so we can label messages.
      let memberships = try await supabase.listChatMemberships(
        channelIds: [channel.id],
        organizationId: organizationId
      )
      guard accepts(organizationId: organizationId, token: token) else { return }
      let ids = Set(memberships.map(\.user_id))
      let profiles = try await supabase.listProfiles(ids: Array(ids))
      guard accepts(organizationId: organizationId, token: token) else { return }
      profileById = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

      if let latest = orderedMessages.last {
        await markRead(through: latest.id)
      }
      guard accepts(organizationId: organizationId, token: token) else { return }
      isLoading = false
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
    SDAsyncRequestGuard.accepts(
      responseContext: Optional(organizationId),
      responseToken: token,
      activeContext: appState.activeOrgId,
      currentToken: loadToken,
      taskIsCancelled: Task.isCancelled
    )
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
    let outgoingAttachments = pendingAttachments
    let messageBody = text.isEmpty ? "Shared an attachment" : text
    let operationMaterial = messageBody + "\n" + outgoingAttachments.map(\.fileName).joined(separator: "|")
    guard let clientMessageId = sendOperation.begin(
      channelId: channel.id,
      body: operationMaterial
    ) else { return }
    sendErrorText = nil
    isSending = true
    defer { isSending = false }
    do {
      let response = try await supabase.sendChatMessage(
        channelId: channel.id,
        body: messageBody,
        clientMessageId: clientMessageId
      )
      if !messages.contains(where: { $0.id == response.message.id }) {
        messages.append(response.message)
      }
      var existing = (try? await supabase.listChatAttachments(messageIds: [response.message.id])) ?? []
      for attachment in outgoingAttachments {
        if existing.contains(where: {
          $0.file_name == attachment.fileName && $0.byte_size == attachment.data.count
        }) {
          continue
        }
        guard let organizationId = channel.org_id else { continue }
        let storagePath = try await supabase.uploadChatAttachment(
          attachment.data,
          organizationId: organizationId,
          channelId: channel.id,
          fileName: attachment.fileName,
          contentType: attachment.mimeType
        )
        let saved = try await supabase.createChatAttachment(
          messageId: response.message.id,
          storagePath: storagePath,
          fileName: attachment.fileName,
          mimeType: attachment.mimeType,
          byteSize: attachment.data.count,
          isImage: attachment.isImage
        )
        existing.append(saved)
        if let url = try? await supabase.signedChatAttachmentURL(path: storagePath) {
          signedAttachmentURLs[saved.id] = url
        }
      }
      attachmentsByMessage[response.message.id] = existing
      sendOperation.finish(success: true)
      composerText = ""
      pendingAttachments = []
      photoPickerItem = nil
      await markRead(through: response.message.id)
    } catch {
      if SDApplicationErrorClassifier.isCancellation(
        error,
        taskIsCancelled: Task.isCancelled
      ) {
        return
      }
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

  private func addPhoto(_ item: PhotosPickerItem) async {
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else {
        sendErrorText = "That photo could not be loaded."
        return
      }
      try appendPending(
        data: data,
        fileName: "Photo-\(pendingAttachments.count + 1).jpg",
        mimeType: "image/jpeg",
        isImage: true
      )
    } catch {
      sendErrorText = "That photo could not be attached."
    }
  }

  private func handleImportedFiles(_ result: Result<[URL], Error>) {
    do {
      for url in try result.get() {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let type = UTType(filenameExtension: url.pathExtension)
        try appendPending(
          data: data,
          fileName: url.lastPathComponent,
          mimeType: type?.preferredMIMEType ?? "application/octet-stream",
          isImage: type?.conforms(to: .image) == true
        )
      }
    } catch {
      sendErrorText = error.localizedDescription
    }
  }

  private func appendPending(data: Data, fileName: String, mimeType: String, isImage: Bool) throws {
    guard data.count <= 52_428_800 else {
      throw NSError(domain: "chat", code: 10, userInfo: [NSLocalizedDescriptionKey: "Attachments must be 50 MB or smaller."])
    }
    let allowed = isImage
      || [
        "application/pdf", "text/plain", "text/csv", "application/msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.ms-excel",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      ].contains(mimeType)
    guard allowed else {
      throw NSError(domain: "chat", code: 11, userInfo: [NSLocalizedDescriptionKey: "That file type is not supported."])
    }
    pendingAttachments.append(
      PendingChatAttachment(data: data, fileName: fileName, mimeType: mimeType, isImage: isImage)
    )
    sendOperation.clear()
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
  let senderProfile: Profile?
  let isMe: Bool
  let createdAt: Date
  let attachments: [SDChatAttachment]
  let attachmentURLs: [UUID: URL]
  let showSender: Bool
  let showTimestamp: Bool

  var body: some View {
    VStack(spacing: 5) {
      if showTimestamp {
        Text(createdAt.formatted(date: .abbreviated, time: .shortened))
          .font(HP.Font.caption.weight(.medium))
          .foregroundStyle(HP.Color.textMuted)
          .padding(.vertical, HP.Space.xs)
      }

      HStack(alignment: .bottom, spacing: HP.Space.xs) {
        if isMe { Spacer(minLength: 44) }

        if !isMe, let senderProfile {
          HPProfileAvatarButton(profile: senderProfile, size: .sm)
        }

        VStack(alignment: isMe ? .trailing : .leading, spacing: HP.Space.xs) {
          if showSender {
            Text(senderName)
              .font(HP.Font.caption.weight(.semibold))
              .foregroundStyle(HP.Color.textMuted)
              .fixedSize(horizontal: false, vertical: true)
          }

          Text(text)
            .font(HP.Font.body)
            .foregroundStyle(isMe ? HP.Color.accentText : HP.Color.text)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, HP.Space.sm)
            .padding(.vertical, HP.Space.xs)
            .background(
              UnevenRoundedRectangle(
                topLeadingRadius: HP.Radius.md,
                bottomLeadingRadius: isMe ? HP.Radius.md : HP.Radius.sm,
                bottomTrailingRadius: isMe ? HP.Radius.sm : HP.Radius.md,
                topTrailingRadius: HP.Radius.md
              )
              .fill(isMe ? HP.Color.accent : HP.Color.surfaceRaised)
            )

          ForEach(attachments) { attachment in
            if let url = attachmentURLs[attachment.id] {
              if attachment.isImage {
                Link(destination: url) {
                  AsyncImage(url: url) { phase in
                    if let image = phase.image {
                      image.resizable().scaledToFill()
                    } else {
                      ZStack {
                        HP.Color.surfaceRaised
                        ProgressView()
                      }
                    }
                  }
                  .frame(width: 220, height: 160)
                  .clipShape(RoundedRectangle(cornerRadius: HP.Radius.md))
                }
              } else {
                Link(destination: url) {
                  Label(attachment.file_name, systemImage: "doc.fill")
                    .font(HP.Font.callout.weight(.semibold))
                    .lineLimit(2)
                    .padding(HP.Space.sm)
                    .background(HP.Color.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: HP.Radius.sm))
                }
              }
            }
          }
            .overlay(
              UnevenRoundedRectangle(
                topLeadingRadius: HP.Radius.md,
                bottomLeadingRadius: isMe ? HP.Radius.md : HP.Radius.sm,
                bottomTrailingRadius: isMe ? HP.Radius.sm : HP.Radius.md,
                topTrailingRadius: HP.Radius.md
              )
              .strokeBorder(isMe ? .clear : HP.Color.border, lineWidth: 1)
              .allowsHitTesting(false)
            )
        }
        .frame(maxWidth: 560, alignment: isMe ? .trailing : .leading)

        if !isMe { Spacer(minLength: 44) }
      }
    }
    .padding(.vertical, showTimestamp ? 6 : 1)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityDescription)
  }

  private var accessibilityDescription: String {
    let message = "\(isMe ? "You" : senderName): \(text)"
    guard showTimestamp else { return message }
    return "\(createdAt.formatted(date: .abbreviated, time: .shortened)). \(message)"
  }
}

private struct PendingChatAttachment: Identifiable {
  let id = UUID()
  let data: Data
  let fileName: String
  let mimeType: String
  let isImage: Bool
}
