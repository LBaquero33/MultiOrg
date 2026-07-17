import SwiftUI

@MainActor
final class PlayerDevelopmentCopilotWorkspaceModel: ObservableObject {
  enum Phase: Equatable { case idle, loading, loaded, failed(String) }

  @Published private(set) var phase: Phase = .idle
  @Published private(set) var conversations: [SDCopilotConversation] = []
  @Published private(set) var drafts: [SDParentUpdateDraft] = []
  @Published private(set) var suggestedQuestions: [String] = []
  @Published private(set) var usage: SDCopilotUsage?
  @Published private(set) var hasMore = false
  @Published private(set) var isCreating = false
  @Published private(set) var isLoadingMore = false
  @Published private(set) var presentedConversation: SDCopilotConversationPresentation?
  @Published var errorMessage: String?

  private var context: SDCopilotContextToken?
  private var loadTask: Task<Void, Never>?
  private var creationKey: UUID?

  func reset() {
    loadTask?.cancel()
    loadTask = nil
    context = nil
    phase = .idle
    conversations = []
    drafts = []
    suggestedQuestions = []
    usage = nil
    hasMore = false
    isCreating = false
    isLoadingMore = false
    presentedConversation = nil
    errorMessage = nil
    creationKey = nil
  }

  @discardableResult
  func presentConversation(
    _ conversation: SDCopilotConversation,
    organizationId: UUID,
    userId: UUID,
    playerId: UUID,
    audience: SDCopilotAudience,
    initialQuestion: String? = nil
  ) -> Bool {
    let token = SDCopilotContextToken(
      organizationId: organizationId,
      userId: userId,
      playerId: playerId,
      audience: audience
    )
    guard context == token,
          conversation.organizationId == organizationId,
          conversation.playerId == playerId,
          conversation.audience == audience,
          audience == .coach || conversation.createdBy == userId else {
      errorMessage = SDCopilotClientScopeError.invalidResponseScope.localizedDescription
      return false
    }
    presentedConversation = SDCopilotConversationPresentation(
      conversation: conversation,
      initialQuestion: initialQuestion
    )
    return true
  }

  func dismissPresentedConversation() {
    presentedConversation = nil
  }

  func loadMoreConversations(
    client: any PlayerDevelopmentCopilotClient,
    organizationId: UUID,
    userId: UUID,
    playerId: UUID,
    audience: SDCopilotAudience
  ) async {
    guard hasMore, !isLoadingMore else { return }
    let token = SDCopilotContextToken(organizationId: organizationId, userId: userId, playerId: playerId, audience: audience)
    guard context == token else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let response = try await client.listCopilotConversations(
        organizationId: organizationId,
        playerId: playerId,
        audience: audience,
        offset: conversations.count,
        limit: 25
      )
      guard context == token else { return }
      guard response.conversations.allSatisfy({ conversation in
        conversation.organizationId == organizationId &&
          conversation.playerId == playerId &&
          conversation.audience == audience &&
          (audience == .coach || conversation.createdBy == userId)
      }) else {
        throw SDCopilotClientScopeError.invalidResponseScope
      }
      let existing = Set(conversations.map(\.id))
      conversations.append(contentsOf: response.conversations.filter { !existing.contains($0.id) })
      hasMore = response.pagination.hasMore
    } catch is CancellationError {
      return
    } catch {
      guard context == token else { return }
      errorMessage = error.localizedDescription
    }
  }

  func load(
    client: any PlayerDevelopmentCopilotClient,
    organizationId: UUID,
    userId: UUID,
    playerId: UUID,
    audience: SDCopilotAudience
  ) async {
    loadTask?.cancel()
    let token = SDCopilotContextToken(organizationId: organizationId, userId: userId, playerId: playerId, audience: audience)
    if context != nil, context != token {
      presentedConversation = nil
      creationKey = nil
    }
    context = token
    phase = .loading
    errorMessage = nil
    let task = Task { @MainActor in
      do {
        let conversationResponse = try await client.listCopilotConversations(
          organizationId: organizationId, playerId: playerId, audience: audience, offset: 0, limit: 25
        )
        try Task.checkCancellation()
        guard conversationResponse.conversations.allSatisfy({ conversation in
          conversation.organizationId == organizationId &&
            conversation.playerId == playerId &&
            conversation.audience == audience &&
            (audience == .coach || conversation.createdBy == userId)
        }) else {
          throw SDCopilotClientScopeError.invalidResponseScope
        }
        let draftResponse = audience == .coach
          ? try await client.listParentUpdateDrafts(organizationId: organizationId, playerId: playerId)
          : []
        try Task.checkCancellation()
        let questionResponse = try await client.copilotSuggestedQuestions(
          organizationId: organizationId, playerId: playerId, audience: audience
        )
        try Task.checkCancellation()
        let usageResponse = try await client.copilotUsage(organizationId: organizationId, audience: audience)
        guard context == token else { return }
        conversations = conversationResponse.conversations
        hasMore = conversationResponse.pagination.hasMore
        drafts = draftResponse
        suggestedQuestions = questionResponse.suggestedQuestions
        usage = usageResponse
        phase = .loaded
      } catch is CancellationError {
        return
      } catch {
        guard context == token else { return }
        errorMessage = error.localizedDescription
        phase = .failed(error.localizedDescription)
      }
    }
    loadTask = task
    await task.value
  }

  func createConversation(
    client: any PlayerDevelopmentCopilotClient,
    organizationId: UUID,
    userId: UUID,
    playerId: UUID,
    audience: SDCopilotAudience,
    title: String,
    reportingWindowDays: Int,
    initialQuestion: String? = nil
  ) async -> Bool {
    guard !isCreating else { return false }
    let token = SDCopilotContextToken(organizationId: organizationId, userId: userId, playerId: playerId, audience: audience)
    guard context == token else { return false }
    isCreating = true
    errorMessage = nil
    if creationKey == nil { creationKey = UUID() }
    let requestKey = creationKey!
    defer { isCreating = false }
    do {
      let conversation = try await client.createCopilotConversation(
        organizationId: organizationId,
        playerId: playerId,
        audience: audience,
        title: title,
        reportingWindowDays: reportingWindowDays,
        idempotencyKey: requestKey
      )
      guard context == token else { return false }
      guard presentConversation(
        conversation,
        organizationId: organizationId,
        userId: userId,
        playerId: playerId,
        audience: audience,
        initialQuestion: initialQuestion
      ) else { return false }
      conversations.removeAll(where: { $0.id == conversation.id })
      conversations.insert(conversation, at: 0)
      creationKey = nil
      return true
    } catch {
      guard context == token else { return false }
      errorMessage = error.localizedDescription
      return false
    }
  }
}

@MainActor
final class PlayerDevelopmentCopilotConversationModel: ObservableObject {
  @Published private(set) var conversation: SDCopilotConversation?
  @Published private(set) var messages: [SDCopilotMessage] = []
  @Published private(set) var suggestedQuestions: [String] = []
  @Published private(set) var isLoading = false
  @Published private(set) var isSending = false
  @Published private(set) var isLoadingMore = false
  @Published private(set) var hasMore = false
  @Published private(set) var pendingQuestion: SDCopilotPendingQuestion?
  @Published var composer = ""
  @Published var errorMessage: String?
  @Published private(set) var errorDiagnosticCode: String?
  @Published var successMessage: String?

  private var context: SDCopilotContextToken?
  private var requestTask: Task<Void, Never>?
  private var sendKey: UUID?
  private var sendQuestion: String?
  private var retryAllowed = false

  var retryAvailable: Bool {
    retryAllowed && sendKey != nil && sendQuestion != nil && !isSending
  }

  private func presentFailure(_ error: Error) {
    let presentation = SDCopilotFailurePresentation(error: error)
    errorMessage = presentation.message
    errorDiagnosticCode = presentation.code
    retryAllowed = presentation.isRetryable
  }

  private func restorePersistedFailure() {
    guard let failed = messages.last(where: { $0.role == .assistant }),
          [.failed, .rejected].contains(failed.generationStatus) else { return }
    let presentation = SDCopilotFailurePresentation(
      code: failed.safeErrorCode
    )
    errorMessage = presentation.message
    errorDiagnosticCode = presentation.code
    retryAllowed = presentation.isRetryable
    guard presentation.isRetryable else {
      sendKey = nil
      sendQuestion = nil
      return
    }
    let user = messages.last(where: { message in
      message.role == .user && message.createdAt <= failed.createdAt
    })
    sendKey = failed.idempotencyKey ?? user?.idempotencyKey
    sendQuestion = user?.userQuestion
    if sendKey == nil || sendQuestion == nil { retryAllowed = false }
  }

  func prefill(_ question: String?) {
    guard composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let question = question?.trimmingCharacters(in: .whitespacesAndNewlines),
          !question.isEmpty,
          question.count <= 2_000 else { return }
    composer = question
  }

  private func messageIsScoped(
    _ message: SDCopilotMessage,
    organizationId: UUID,
    playerId: UUID,
    audience: SDCopilotAudience,
    conversationId: UUID
  ) -> Bool {
    message.organizationId == organizationId &&
      message.playerId == playerId &&
      message.audience == audience &&
      message.conversationId == conversationId &&
      (message.citations ?? []).allSatisfy { citation in
        let isLegacyInlineCitation = citation.persistedId == nil &&
          citation.organizationId == nil && citation.playerId == nil &&
          citation.audience == nil && citation.messageId == nil
        let isPersistedScopedCitation = citation.persistedId != nil &&
          citation.organizationId == organizationId &&
          citation.playerId == playerId && citation.audience == audience &&
          citation.messageId == message.id
        return isLegacyInlineCitation || isPersistedScopedCitation
      }
  }

  private func detailIsScoped(
    _ detail: SDCopilotConversationDetailResponse,
    organizationId: UUID,
    userId: UUID,
    playerId: UUID,
    audience: SDCopilotAudience,
    conversationId: UUID
  ) -> Bool {
    detail.conversation.id == conversationId &&
      detail.conversation.organizationId == organizationId &&
      detail.conversation.playerId == playerId &&
      detail.conversation.audience == audience &&
      (audience == .coach || detail.conversation.createdBy == userId) &&
      detail.messages.allSatisfy {
        messageIsScoped(
          $0,
          organizationId: organizationId,
          playerId: playerId,
          audience: audience,
          conversationId: conversationId
        )
      }
  }

  func reset() {
    requestTask?.cancel()
    requestTask = nil
    context = nil
    conversation = nil
    messages = []
    suggestedQuestions = []
    isLoading = false
    isSending = false
    isLoadingMore = false
    hasMore = false
    pendingQuestion = nil
    composer = ""
    errorMessage = nil
    errorDiagnosticCode = nil
    successMessage = nil
    sendKey = nil
    sendQuestion = nil
    retryAllowed = false
  }

  func loadMoreMessages(
    client: any PlayerDevelopmentCopilotClient,
    organizationId: UUID,
    userId: UUID,
    playerId: UUID,
    audience: SDCopilotAudience,
    conversationId: UUID
  ) async {
    guard hasMore, !isLoadingMore else { return }
    let token = SDCopilotContextToken(organizationId: organizationId, userId: userId, playerId: playerId, audience: audience)
    guard context == token else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let detail = try await client.copilotConversation(
        organizationId: organizationId,
        conversationId: conversationId,
        audience: audience,
        offset: messages.count,
        limit: 40
      )
      guard context == token else { return }
      guard detailIsScoped(
        detail,
        organizationId: organizationId,
        userId: userId,
        playerId: playerId,
        audience: audience,
        conversationId: conversationId
      ) else {
        throw SDCopilotClientScopeError.invalidResponseScope
      }
      let existing = Set(messages.map(\.id))
      messages.append(contentsOf: detail.messages.filter { !existing.contains($0.id) })
      messages.sort(by: { $0.createdAt < $1.createdAt })
      hasMore = detail.pagination.hasMore
      restorePersistedFailure()
    } catch is CancellationError {
      return
    } catch {
      guard context == token else { return }
      presentFailure(error)
    }
  }

  func load(
    client: any PlayerDevelopmentCopilotClient,
    organizationId: UUID,
    userId: UUID,
    playerId: UUID,
    audience: SDCopilotAudience,
    conversationId: UUID
  ) async {
    requestTask?.cancel()
    let token = SDCopilotContextToken(organizationId: organizationId, userId: userId, playerId: playerId, audience: audience)
    context = token
    isLoading = true
    errorMessage = nil
    errorDiagnosticCode = nil
    sendKey = nil
    sendQuestion = nil
    retryAllowed = false
    let task = Task { @MainActor in
      defer { if context == token { isLoading = false } }
      do {
        let detail = try await client.copilotConversation(
          organizationId: organizationId, conversationId: conversationId, audience: audience, offset: 0, limit: 40
        )
        try Task.checkCancellation()
        guard detailIsScoped(
          detail,
          organizationId: organizationId,
          userId: userId,
          playerId: playerId,
          audience: audience,
          conversationId: conversationId
        ) else {
          throw SDCopilotClientScopeError.invalidResponseScope
        }
        let questions = try await client.copilotSuggestedQuestions(
          organizationId: organizationId, playerId: playerId, audience: audience
        )
        guard context == token else { return }
        conversation = detail.conversation
        messages = detail.messages
        pendingQuestion = detail.messages.compactMap(\.pendingQuestion).last(where: { pending in
          pending.status == .pending && (ISO8601DateFormatter().date(from: pending.expiresAt) ?? .distantPast) > Date()
        })
        hasMore = detail.pagination.hasMore
        suggestedQuestions = questions.suggestedQuestions
        restorePersistedFailure()
      } catch is CancellationError {
        return
      } catch {
        guard context == token else { return }
        presentFailure(error)
      }
    }
    requestTask = task
    await task.value
  }

  @discardableResult
  func send(
    client: any PlayerDevelopmentCopilotClient,
    organizationId: UUID,
    userId: UUID,
    playerId: UUID,
    audience: SDCopilotAudience,
    conversationId: UUID,
    window: SDDevelopmentWindow,
    retry: Bool = false,
    responseText: String? = nil,
    responseMode: SDCopilotPendingResponseMode? = nil
  ) async -> Bool {
    guard !isSending else { return false }
    let token = SDCopilotContextToken(organizationId: organizationId, userId: userId, playerId: playerId, audience: audience)
    guard context == token else { return false }
    let activePending = pendingQuestion?.status == .pending ? pendingQuestion : nil
    let question = retry
      ? (sendQuestion ?? "")
      : (responseText ?? composer).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !question.isEmpty, question.count <= 2_000 else {
      errorMessage = question.isEmpty ? "Enter a player-development question." : "Questions are limited to 2,000 characters."
      return false
    }
    if !retry || sendQuestion != question || sendKey == nil {
      sendQuestion = question
      sendKey = UUID()
    }
    isSending = true
    errorMessage = nil
    errorDiagnosticCode = nil
    retryAllowed = false
    successMessage = nil
    defer { isSending = false }
    do {
      let response = try await client.askCopilot(
        organizationId: organizationId,
        playerId: playerId,
        conversationId: conversationId,
        audience: audience,
        question: question,
        window: window,
        idempotencyKey: sendKey!,
        retry: retry,
        pendingQuestionId: activePending?.id,
        pendingResponseMode: activePending == nil ? nil : (responseMode ?? .answer)
      )
      guard context == token else { return false }
      guard [response.userMessage, response.assistantMessage].allSatisfy({
        messageIsScoped(
          $0,
          organizationId: organizationId,
          playerId: playerId,
          audience: audience,
          conversationId: conversationId
        )
      }) else {
        throw SDCopilotClientScopeError.invalidResponseScope
      }
      for message in [response.userMessage, response.assistantMessage] {
        messages.removeAll(where: { $0.id == message.id })
        messages.append(message)
      }
      messages.sort(by: { $0.createdAt < $1.createdAt })
      suggestedQuestions = response.suggestedQuestions
      pendingQuestion = response.pendingQuestion
      composer = ""
      sendQuestion = nil
      sendKey = nil
      retryAllowed = false
      successMessage = response.reused ? "The existing answer was restored." : nil
      return true
    } catch {
      guard context == token else { return false }
      presentFailure(error)
      return false
    }
  }

  func submitFeedback(
    client: any PlayerDevelopmentCopilotClient,
    organizationId: UUID,
    audience: SDCopilotAudience,
    conversationId: UUID,
    messageId: UUID,
    type: SDCopilotFeedbackType
  ) async {
    do {
      try await client.submitCopilotFeedback(
        organizationId: organizationId,
        conversationId: conversationId,
        messageId: messageId,
        audience: audience,
        type: type,
        note: nil
      )
      successMessage = "Feedback saved."
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func archiveConversation(
    client: any PlayerDevelopmentCopilotClient,
    organizationId: UUID,
    userId: UUID,
    playerId: UUID,
    audience: SDCopilotAudience,
    conversationId: UUID
  ) async -> Bool {
    let token = SDCopilotContextToken(organizationId: organizationId, userId: userId, playerId: playerId, audience: audience)
    guard context == token else { return false }
    do {
      let archived = try await client.archiveCopilotConversation(
        organizationId: organizationId,
        conversationId: conversationId,
        audience: audience
      )
      guard context == token else { return false }
      guard archived.organizationId == organizationId,
            archived.playerId == playerId,
            archived.audience == audience,
            audience == .coach || archived.createdBy == userId else {
        throw SDCopilotClientScopeError.invalidResponseScope
      }
      conversation = archived
      return true
    } catch {
      guard context == token else { return false }
      errorMessage = error.localizedDescription
      return false
    }
  }
}

struct PlayerDevelopmentCopilotWorkspaceView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @StateObject private var model = PlayerDevelopmentCopilotWorkspaceModel()
  @State private var reportingDays = 90
  let player: Profile
  let audience: SDCopilotAudience
  let presentationStyle: SDCopilotWorkspacePresentationStyle

  init(
    player: Profile,
    audience: SDCopilotAudience = .coach,
    presentationStyle: SDCopilotWorkspacePresentationStyle = .pushed
  ) {
    self.player = player
    self.audience = audience
    self.presentationStyle = presentationStyle
  }

  private var contextKey: String {
    "\(appState.activeOrgAuthorizationKey):\(appState.myProfile?.id.uuidString ?? "none"):\(player.id.uuidString):\(audience.rawValue)"
  }
  private var presentation: SDCopilotPresentationPolicy {
    SDCopilotPresentationPolicy(audience: audience)
  }
  private var presentedConversation: Binding<SDCopilotConversationPresentation?> {
    Binding(
      get: { model.presentedConversation },
      set: { value in
        if value == nil { model.dismissPresentedConversation() }
      }
    )
  }
  private var canRetryInitialLoad: Bool {
    if case .failed = model.phase { return true }
    return false
  }

  var body: some View {
    Group {
      if !SDDevelopmentPresentationAuthorization.isCopilotVisible(
        membership: appState.activeOrgMembership,
        audience: audience,
        userId: appState.myProfile?.id,
        playerId: player.id
      ) {
        HPStateScreenLayout { _ in
          HPCard {
            HPEmptyState(
              title: "Copilot access unavailable",
              message: audience == .player
                ? "Player Copilot is available only for your signed-in player profile."
                : "Coach Copilot requires an active coach, administrator, or owner membership in the selected organization.",
              systemImage: "lock.fill"
            )
          }
        }
      } else if let service = appState.supabase,
                let organizationId = appState.activeOrgId,
                let userId = appState.myProfile?.id {
        content(service: service, organizationId: organizationId, userId: userId)
      } else {
        HPStateScreenLayout { _ in
          HPCard {
            HPLoadingState(text: "Loading organization…")
          }
        }
      }
    }
    .navigationTitle(audience == .player ? "Player Copilot" : "Coach Copilot")
    .toolbar {
      if presentationStyle == .modal {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { dismiss() }
            #if os(macOS)
            .keyboardShortcut(.cancelAction)
            #endif
        }
      }
    }
    .background(HP.Color.bg)
    .task(id: contextKey) {
      guard let service = appState.supabase,
            let organizationId = appState.activeOrgId,
            let userId = appState.myProfile?.id else { return }
      model.reset()
      await model.load(client: service, organizationId: organizationId, userId: userId, playerId: player.id, audience: audience)
    }
    .copilotConversationPresentation(
      item: presentedConversation,
      player: player,
      audience: audience,
      appState: appState
    )
  }

  private func content(
    service: SupabaseService,
    organizationId: UUID,
    userId: UUID
  ) -> some View {
    HPListScreenLayout {
      HPWorkspaceHeader(
        audience == .player ? "Player Copilot" : "Coach Copilot",
        orgLabel: player.displayName,
        context: "Ask evidence-grounded questions. Facts and interpretations remain separate, and every supported claim keeps its citation."
      ) {
        HPButton(
          title: model.isCreating ? "Creating…" : "New Conversation",
          systemImage: "plus.bubble.fill",
          variant: .primary,
          size: .sm,
          isLoading: model.isCreating
        ) {
          Task {
            _ = await model.createConversation(
              client: service,
              organizationId: organizationId,
              userId: userId,
              playerId: player.id,
              audience: audience,
              title: "\(player.displayName) development",
              reportingWindowDays: reportingDays
            )
          }
        }
        .disabled(model.isCreating)
      }
    } controls: {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Default window")
          HPSegmentedControl(
            options: [
              (value: 30, label: "30 days"),
              (value: 90, label: "90 days"),
              (value: 180, label: "180 days"),
              (value: 365, label: "1 year"),
            ],
            selection: $reportingDays
          )
        }
      }
    } results: { context in
      VStack(alignment: .leading, spacing: HP.Space.md) {
        if let error = model.errorMessage {
          HPCard {
            HPErrorState(
              title: "Copilot unavailable",
              message: error,
              onRetry: canRetryInitialLoad
                ? {
                  Task {
                    await model.load(
                      client: service,
                      organizationId: organizationId,
                      userId: userId,
                      playerId: player.id,
                      audience: audience
                    )
                  }
                }
                : nil
            )
          }
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Suggested questions") {
              if !model.suggestedQuestions.isEmpty {
                HPStatusBadge(text: "\(model.suggestedQuestions.count)", kind: .neutral)
              }
            }
            if model.suggestedQuestions.isEmpty {
              Text("Suggestions will appear when supported evidence is available.")
                .font(HP.Font.callout)
                .foregroundStyle(HP.Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            } else {
              ForEach(model.suggestedQuestions, id: \.self) { question in
                Button {
                  Task {
                    _ = await model.createConversation(
                      client: service,
                      organizationId: organizationId,
                      userId: userId,
                      playerId: player.id,
                      audience: audience,
                      title: "\(player.displayName) development",
                      reportingWindowDays: reportingDays,
                      initialQuestion: question
                    )
                  }
                } label: {
                  HStack(alignment: .center, spacing: HP.Space.sm) {
                    Image(systemName: "plus.bubble")
                      .foregroundStyle(HP.Color.primary)
                    Text(question)
                      .font(HP.Font.callout)
                      .foregroundStyle(HP.Color.text)
                      .fixedSize(horizontal: false, vertical: true)
                      .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(HP.Color.textMuted)
                  }
                  .frame(minHeight: 44)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isCreating)
              }
            }
          }
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Conversations") {
              HPStatusBadge(text: "\(model.conversations.count)", kind: .neutral)
            }
            if model.phase == .loading {
              HPLoadingState(text: "Loading conversations…")
            }
            if model.conversations.isEmpty, model.phase != .loading {
              Text("No Copilot conversations yet.")
                .font(HP.Font.callout)
                .foregroundStyle(HP.Color.textMuted)
            }
            ForEach(model.conversations) { conversation in
              Button {
                _ = model.presentConversation(
                  conversation,
                  organizationId: organizationId,
                  userId: userId,
                  playerId: player.id,
                  audience: audience
                )
              } label: {
                HStack(alignment: .center, spacing: HP.Space.sm) {
                  VStack(alignment: .leading, spacing: 5) {
                    Text(conversation.title)
                      .font(HP.Font.headline)
                      .foregroundStyle(HP.Color.text)
                      .fixedSize(horizontal: false, vertical: true)
                    copilotQualityBadge(conversation.qualityStatus ?? .unavailable)
                    if let question = conversation.mostRecentQuestion {
                      Text(question)
                        .font(HP.Font.callout)
                        .foregroundStyle(HP.Color.text)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    }
                    if let preview = conversation.mostRecentAnswerPreview {
                      Text(preview)
                        .font(HP.Font.caption)
                        .foregroundStyle(HP.Color.textMuted)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    }
                    Text(
                      "\(conversation.generationMode == .deterministic ? "Deterministic mode" : conversation.provider.capitalized) • \(conversation.updatedAt)\(conversation.status == .archived ? " • Archived • read only" : "")"
                    )
                    .font(HP.Font.caption)
                    .foregroundStyle(HP.Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                  Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HP.Color.textMuted)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
            if model.hasMore {
              HPButton(
                title: model.isLoadingMore ? "Loading…" : "Load more conversations",
                variant: .secondary,
                size: .md,
                isLoading: model.isLoadingMore,
                fullWidth: context.isAccessibilitySize
              ) {
                Task {
                  await model.loadMoreConversations(
                    client: service,
                    organizationId: organizationId,
                    userId: userId,
                    playerId: player.id,
                    audience: audience
                  )
                }
              }
              .disabled(model.isLoadingMore)
            }
          }
        }

        if presentation.showsParentDraftControls {
          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              HPSectionHeader("Parent update drafts") {
                HPStatusBadge(text: "\(model.drafts.count)", kind: .neutral)
              }
              Label("Not shared with parent.", systemImage: "lock.fill")
                .font(HP.Font.caption.weight(.semibold))
                .foregroundStyle(HP.Color.warning)
              if model.drafts.isEmpty {
                Text("No parent update drafts.")
                  .font(HP.Font.callout)
                  .foregroundStyle(HP.Color.textMuted)
              }
              ForEach(model.drafts) { draft in
                NavigationLink {
                  ParentUpdateDraftDetailView(player: player, draftId: draft.id)
                } label: {
                  HStack(alignment: .center, spacing: HP.Space.sm) {
                    VStack(alignment: .leading, spacing: 4) {
                      Text("Parent update")
                        .font(HP.Font.headline)
                        .foregroundStyle(HP.Color.text)
                      Text(draft.updatedAt)
                        .font(HP.Font.caption)
                        .foregroundStyle(HP.Color.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HPStatusBadge(
                      text: draft.status.rawValue.capitalized,
                      kind: draft.status == .approved ? .success : .warning
                    )
                    Image(systemName: "chevron.right")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(HP.Color.textMuted)
                  }
                  .frame(minHeight: 44)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
              }
            }
          }
        }

        if let usage = model.usage {
          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              HPSectionHeader("Development usage")
              Text("\(usage.organizationQuestionsToday) of \(usage.limits.questionsPerOrganizationDay) organization questions today")
              Text("\(usage.actorQuestionsThisHour) of \(usage.limits.questionsPerActorHour) questions this hour")
              if presentation.showsParentDraftUsage {
                Text("\(usage.organizationParentDraftsToday) of \(usage.limits.parentDraftsPerOrganizationDay) parent drafts today")
              }
            }
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
          }
        }
      }
    }
  }
}

private struct CopilotConversationPresentationModifier: ViewModifier {
  @Binding var item: SDCopilotConversationPresentation?
  let player: Profile
  let audience: SDCopilotAudience
  let appState: AppState

  func body(content: Content) -> some View {
    #if os(macOS)
    content.sheet(item: $item) { route in
      NavigationStack {
        PlayerDevelopmentCopilotConversationView(
          player: player,
          conversation: route.conversation,
          audience: audience,
          initialQuestion: route.initialQuestion,
          presentationStyle: .modal
        )
        .environmentObject(appState)
      }
      .frame(minWidth: 720, minHeight: 680)
    }
    #else
    content.fullScreenCover(item: $item) { route in
      NavigationStack {
        PlayerDevelopmentCopilotConversationView(
          player: player,
          conversation: route.conversation,
          audience: audience,
          initialQuestion: route.initialQuestion,
          presentationStyle: .modal
        )
        .environmentObject(appState)
      }
    }
    #endif
  }
}

private extension View {
  func copilotConversationPresentation(
    item: Binding<SDCopilotConversationPresentation?>,
    player: Profile,
    audience: SDCopilotAudience,
    appState: AppState
  ) -> some View {
    modifier(
      CopilotConversationPresentationModifier(
        item: item,
        player: player,
        audience: audience,
        appState: appState
      )
    )
  }
}

struct PlayerDevelopmentCopilotConversationView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @StateObject private var model = PlayerDevelopmentCopilotConversationModel()
  @State private var selectedCitation: SDCopilotCitation?
  @State private var selectedParentDraft: SDParentUpdateDraft?
  @State private var reportingDays = 90
  let player: Profile
  let conversation: SDCopilotConversation
  let audience: SDCopilotAudience
  let initialQuestion: String?
  let presentationStyle: SDCopilotWorkspacePresentationStyle

  private var conversationId: UUID { conversation.id }

  private var contextKey: String {
    "\(appState.activeOrgAuthorizationKey):\(appState.myProfile?.id.uuidString ?? "none"):\(player.id.uuidString):\(conversationId):\(audience.rawValue)"
  }
  private var presentation: SDCopilotPresentationPolicy {
    SDCopilotPresentationPolicy(audience: audience)
  }
  private var window: SDDevelopmentWindow { .trailingDays(reportingDays) }
  private var isArchived: Bool { (model.conversation ?? conversation).status == .archived }

  var body: some View {
    Group {
      if let service = appState.supabase,
         let organizationId = appState.activeOrgId,
         let userId = appState.myProfile?.id {
        HPCommunicationScreenLayout(compactPane: .thread) { context in
          conversationContextPane(context)
        } thread: { context in
          conversationContent(
            service: service,
            organizationId: organizationId,
            userId: userId,
            showsContextCard: !context.isExpanded
          )
        }
      } else {
        HPStateScreenLayout { _ in
          HPCard {
            HPLoadingState(text: "Loading organization…")
          }
        }
      }
    }
    .navigationTitle(model.conversation?.title ?? conversation.title)
    #if !os(macOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
      if presentationStyle == .modal {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { dismiss() }
            #if os(macOS)
            .keyboardShortcut(.cancelAction)
            #endif
        }
      }
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Picker("Reporting window", selection: $reportingDays) {
            Text("30 days").tag(30)
            Text("90 days").tag(90)
            Text("180 days").tag(180)
            Text("1 year").tag(365)
          }
          if presentation.showsParentDraftControls {
            Button("Generate Parent Update") {
            guard let service = appState.supabase,
                  let organizationId = appState.activeOrgId else { return }
            Task {
              do {
                selectedParentDraft = try await service.createParentUpdateDraft(
                  organizationId: organizationId,
                  playerId: player.id,
                  conversationId: conversationId,
                  sourceMessageId: model.messages.last(where: { $0.role == .assistant })?.id,
                  window: window,
                  idempotencyKey: UUID()
                )
              } catch { model.errorMessage = error.localizedDescription }
            }
            }
          }
          if model.conversation?.status == .active,
             let service = appState.supabase,
             let organizationId = appState.activeOrgId,
             let userId = appState.myProfile?.id {
            Button("Archive conversation", role: .destructive) {
              Task {
                if await model.archiveConversation(
                  client: service,
                  organizationId: organizationId,
                  userId: userId,
                  playerId: player.id,
                  audience: audience,
                  conversationId: conversationId
                ) { dismiss() }
              }
            }
          }
        } label: {
          Image(systemName: "ellipsis.circle")
            .accessibilityLabel("More conversation actions")
        }
      }
    }
    .background(HP.Color.bg)
    .task(id: contextKey) {
      guard let service = appState.supabase,
            let organizationId = appState.activeOrgId,
            let userId = appState.myProfile?.id else { return }
      model.reset()
      await model.load(client: service, organizationId: organizationId, userId: userId, playerId: player.id, audience: audience, conversationId: conversationId)
      model.prefill(initialQuestion)
    }
    .sheet(item: $selectedCitation) { EvidenceCitationDetailView(citation: $0) }
    .sheet(item: $selectedParentDraft) { draft in
      NavigationStack {
        ParentUpdateDraftDetailView(player: player, draftId: draft.id)
          .environmentObject(appState)
      }
    }
  }

  private func conversationContextPane(_: HPScreenLayoutContext) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPWorkspaceHeader(
          audience == .player ? "Player Copilot" : "Coach Copilot",
          orgLabel: player.displayName,
          context: audience == .player ? "Private player conversation" : "Private staff conversation"
        )
        conversationContextCard()
        evidenceGroundingCard
      }
    }
  }

  private func conversationContextCard() -> some View {
    let mode = model.conversation?.generationMode ?? conversation.generationMode
    return HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HStack(alignment: .center, spacing: HP.Space.sm) {
          HPAvatar(
            name: player.displayName,
            systemImage: audience == .player ? "person.crop.circle" : "person.2.fill",
            size: .md
          )
          VStack(alignment: .leading, spacing: 2) {
            Text(player.displayName)
              .font(HP.Font.headline)
              .foregroundStyle(HP.Color.text)
            Text(audience == .player ? "Player Copilot • Private to you" : "Coach Copilot • Staff workspace")
              .font(HP.Font.caption.weight(.semibold))
              .foregroundStyle(HP.Color.primary)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: HP.Space.xs)
          HPStatusBadge(
            text: mode == .deterministic ? "Deterministic" : mode.rawValue.capitalized,
            kind: mode == .unavailable ? .danger : .info
          )
        }
        Divider().overlay(HP.Color.border)
        Label("\(reportingDays)-day evidence window", systemImage: "calendar")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
      }
    }
  }

  private var evidenceGroundingCard: some View {
    HPCard(style: .flat) {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        Label("Evidence-grounded", systemImage: "checkmark.shield.fill")
          .font(HP.Font.headline)
          .foregroundStyle(HP.Color.text)
        Text("Facts and interpretations remain separate, and supported claims retain their citations.")
          .font(HP.Font.callout)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func conversationContent(
    service: SupabaseService,
    organizationId: UUID,
    userId: UUID,
    showsContextCard: Bool
  ) -> some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          if showsContextCard {
            conversationContextCard()
            evidenceGroundingCard
          }
          if model.isLoading {
            HPLoadingState(text: "Loading messages…")
          }
          if let error = model.errorMessage {
            HPCard {
              VStack(alignment: .leading, spacing: HP.Space.sm) {
                if model.retryAvailable {
                  HPErrorState(
                    title: "Answer unavailable",
                    message: error,
                    retryTitle: "Retry failed answer",
                    onRetry: {
                      Task {
                        _ = await model.send(
                          client: service,
                          organizationId: organizationId,
                          userId: userId,
                          playerId: player.id,
                          audience: audience,
                          conversationId: conversationId,
                          window: window,
                          retry: true
                        )
                      }
                    }
                  )
                  .disabled(model.isSending)
                } else if model.conversation == nil {
                  HPErrorState(
                    title: "Conversation unavailable",
                    message: error,
                    retryTitle: "Retry conversation",
                    onRetry: {
                      Task {
                        await model.load(
                          client: service,
                          organizationId: organizationId,
                          userId: userId,
                          playerId: player.id,
                          audience: audience,
                          conversationId: conversationId
                        )
                        model.prefill(initialQuestion)
                      }
                    }
                  )
                  .disabled(model.isLoading)
                } else {
                  HPErrorState(
                    title: "Conversation unavailable",
                    message: error
                  )
                }
                #if DEBUG
                if let code = model.errorDiagnosticCode {
                  DisclosureGroup("Technical details") {
                    Text("Code: \(code)")
                      .font(.caption.monospaced())
                      .textSelection(.enabled)
                  }
                }
                #endif
              }
            }
          }
          if let success = model.successMessage {
            Label(success, systemImage: "checkmark.circle.fill")
              .foregroundStyle(HP.Color.success)
          }
          if model.messages.isEmpty, !model.isLoading {
            HPCard(style: .flat) {
              HPEmptyState(
                title: "Ask a player-development question",
                message: "Use the composer below to ask about supported player evidence.",
                systemImage: "bubble.left.and.text.bubble.right"
              )
            }
          }
          ForEach(model.messages) { message in
            if message.role == .user {
              HStack {
                Spacer(minLength: 32)
                Text(message.userQuestion ?? "")
                  .font(HP.Font.callout)
                  .foregroundStyle(HP.Color.text)
                  .padding(HP.Space.sm)
                  .background(
                    HP.Color.primary.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: HP.Radius.lg, style: .continuous)
                  )
              }
            } else if let pending = message.pendingQuestion,
                      message.assistantTurnType?.isQuestion == true {
              CopilotQuestionCard(
                message: message,
                pending: pending,
                isActive: model.pendingQuestion?.id == pending.id,
                isSending: model.isSending
              ) { text, mode in
                Task {
                  _ = await model.send(
                    client: service,
                    organizationId: organizationId,
                    userId: userId,
                    playerId: player.id,
                    audience: audience,
                    conversationId: conversationId,
                    window: window,
                    responseText: text,
                    responseMode: mode
                  )
                }
              }
            } else {
              CopilotAnswerCard(message: message, onCitation: { selectedCitation = $0 }) { feedback in
                Task { await model.submitFeedback(client: service, organizationId: organizationId, audience: audience, conversationId: conversationId, messageId: message.id, type: feedback) }
              }
            }
          }
          if model.hasMore {
            HPButton(
              title: model.isLoadingMore ? "Loading…" : "Load more messages",
              variant: .secondary,
              size: .md,
              isLoading: model.isLoadingMore,
              fullWidth: dynamicTypeSize.isAccessibilitySize
            ) {
              Task {
                await model.loadMoreMessages(
                  client: service,
                  organizationId: organizationId,
                  userId: userId,
                  playerId: player.id,
                  audience: audience,
                  conversationId: conversationId
                )
              }
            }
            .disabled(model.isLoadingMore)
          }
          if !model.suggestedQuestions.isEmpty {
            HPCard {
              VStack(alignment: .leading, spacing: HP.Space.sm) {
                Text("Suggested follow-ups")
                  .font(HP.Font.headline)
                  .foregroundStyle(HP.Color.text)
                ForEach(model.suggestedQuestions, id: \.self) { question in
                  Button(question) { model.composer = question }
                    .buttonStyle(.plain)
                    .foregroundStyle(HP.Color.primary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                    .disabled(isArchived)
                }
              }
            }
          }
          Color.clear.frame(height: 1).id("copilot-conversation-bottom")
        }
        .padding()
        .padding(.bottom, 110)
      }
      .onChange(of: model.messages.count) { _, _ in
        withAnimation { proxy.scrollTo("copilot-conversation-bottom", anchor: .bottom) }
      }
      .onChange(of: model.isLoading) { _, loading in
        if !loading { proxy.scrollTo("copilot-conversation-bottom", anchor: .bottom) }
      }
    }
    .safeAreaInset(edge: .bottom) {
      if isArchived {
        HPCard(style: .flat) {
          Label("Archived conversation • Read only", systemImage: "archivebox.fill")
            .font(HP.Font.callout.weight(.semibold))
            .foregroundStyle(HP.Color.textMuted)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, HP.Space.sm)
        .padding(.vertical, HP.Space.xs)
        .background(.regularMaterial)
      } else {
        HPCard(style: .flat) {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            let layout = dynamicTypeSize.isAccessibilitySize
              ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
              : AnyLayout(HStackLayout(alignment: .bottom, spacing: HP.Space.sm))

            layout {
              HPFormField(
                label: "Message",
                text: $model.composer,
                kind: .multiline,
                placeholder: model.pendingQuestion == nil
                  ? "Ask about supported player evidence…"
                  : "Answer Copilot’s question…"
              )

              HPButton(
                title: "Send",
                systemImage: "arrow.up.circle.fill",
                variant: .primary,
                size: .md,
                isLoading: model.isSending,
                fullWidth: dynamicTypeSize.isAccessibilitySize
              ) {
                Task {
                  _ = await model.send(
                    client: service,
                    organizationId: organizationId,
                    userId: userId,
                    playerId: player.id,
                    audience: audience,
                    conversationId: conversationId,
                    window: window
                  )
                }
              }
              .accessibilityLabel("Send message")
              .disabled(
                model.isSending
                  || model.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  || model.composer.count > 2_000
              )
            }

            HStack {
              Text("\(model.composer.count)/2,000")
              Spacer()
              Text(
                model.pendingQuestion?.isOptional == true
                  ? "Optional response • Copilot never changes official records."
                  : "Copilot never changes official player records."
              )
            }
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, HP.Space.sm)
        .padding(.vertical, HP.Space.xs)
        .background(.regularMaterial)
      }
    }
  }
}

private struct CopilotQuestionCard: View {
  let message: SDCopilotMessage
  let pending: SDCopilotPendingQuestion
  let isActive: Bool
  let isSending: Bool
  let onResponse: (String, SDCopilotPendingResponseMode) -> Void

  private var isExpired: Bool {
    guard pending.status == .pending else { return pending.status == .expired }
    return (ISO8601DateFormatter().date(from: pending.expiresAt) ?? .distantPast) <= Date()
  }

  private var title: String {
    switch pending.questionType {
    case .clarificationQuestion: "One clarification"
    case .evidenceGapQuestion: "Evidence context needed"
    case .reflectionQuestion: "Optional reflection"
    case .confirmationQuestion: "Confirmation required"
    default: "Copilot question"
    }
  }

  var body: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: HP.Space.sm) {
            questionIdentity
            Spacer(minLength: HP.Space.sm)
            questionStatus
          }
          VStack(alignment: .leading, spacing: HP.Space.xs) {
            questionIdentity
            questionStatus
          }
        }
        Text(message.structuredAnswer?.answer ?? pending.questionText ?? "Copilot needs a response.")
          .font(HP.Font.body.weight(.medium))
          .foregroundStyle(HP.Color.text)
          .fixedSize(horizontal: false, vertical: true)
        Text(pending.whyAsked)
          .font(HP.Font.callout)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
        if pending.mayLaterBeSaved {
          Text("Your response stays in this private conversation unless you separately confirm a supported save action.")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        if isSending && isActive {
          HPLoadingState(text: "Sending response…")
        } else if isExpired {
          Label(
            "This question expired. Ask Copilot again for a current question.",
            systemImage: "clock.badge.exclamationmark"
          )
          .font(HP.Font.callout)
          .foregroundStyle(HP.Color.warning)
          .fixedSize(horizontal: false, vertical: true)
        } else if pending.status != .pending || !isActive {
          Label(
            pending.status == .superseded ? "Superseded by a newer question" : "Response recorded",
            systemImage: "checkmark.circle.fill"
          )
          .font(HP.Font.callout)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
        } else {
          if !pending.choices.isEmpty {
            FlowLayout(spacing: HP.Space.xs) {
              ForEach(pending.choices.prefix(6), id: \.self) { choice in
                HPButton(title: choice, variant: .secondary, size: .sm) {
                  onResponse(choice, .answer)
                }
              }
            }
          }
          if pending.expectedResponseType == "free_text" {
            Text("Type your response in the composer below.")
              .font(HP.Font.callout)
              .foregroundStyle(HP.Color.textMuted)
          }
          ViewThatFits(in: .horizontal) {
            HStack(spacing: HP.Space.xs) {
              responseButtons(fullWidth: false)
            }
            VStack(alignment: .leading, spacing: HP.Space.xs) {
              responseButtons(fullWidth: true)
            }
          }
        }
      }
    }
  }

  private var questionIdentity: some View {
    Label(title, systemImage: pending.isOptional ? "questionmark.bubble" : "checkmark.shield")
      .font(HP.Font.headline)
      .foregroundStyle(HP.Color.text)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var questionStatus: some View {
    HPStatusBadge(
      text: pending.isOptional ? "Optional" : "Required",
      kind: pending.isOptional ? .info : .warning
    )
  }

  @ViewBuilder
  private func responseButtons(fullWidth: Bool) -> some View {
    if pending.isOptional {
      HPButton(title: "Skip", variant: .secondary, size: .md, fullWidth: fullWidth) {
        onResponse("Skip", .skip)
      }
    }
    HPButton(
      title: "Use available evidence",
      variant: .secondary,
      size: .md,
      fullWidth: fullWidth
    ) {
      onResponse("Use available evidence", .useAvailableEvidence)
    }
  }
}

private struct FlowLayout<Content: View>: View {
  let spacing: CGFloat
  let content: Content

  init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
    self.spacing = spacing
    self.content = content()
  }

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: spacing) { content }
      VStack(alignment: .leading, spacing: spacing) { content }
    }
  }
}

private struct CopilotAnswerCard: View {
  let message: SDCopilotMessage
  let onCitation: (SDCopilotCitation) -> Void
  let onFeedback: (SDCopilotFeedbackType) -> Void

  var body: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: HP.Space.sm) {
            copilotIdentity
            Spacer(minLength: HP.Space.sm)
            copilotQualityBadge(message.qualityStatus)
          }
          VStack(alignment: .leading, spacing: HP.Space.xs) {
            copilotIdentity
            copilotQualityBadge(message.qualityStatus)
          }
        }
        if let answer = message.structuredAnswer {
          Text(answer.answer)
            .font(HP.Font.body)
            .foregroundStyle(HP.Color.text)
            .fixedSize(horizontal: false, vertical: true)
          claimSection("Facts", rows: answer.facts.map { ($0.text, $0.evidenceIds) })
          claimSection("Calculations", rows: answer.calculations.map { ($0.text, $0.evidenceIds) })
          claimSection("Interpretation", rows: answer.interpretations.map { ($0.text, $0.evidenceIds) })
          claimSection("Recommendations", rows: answer.recommendations.map { ($0.text, $0.evidenceIds) })
          if !answer.missingData.isEmpty { warningSection("Missing information", rows: answer.missingData) }
          if !answer.warnings.isEmpty { warningSection("Warnings", rows: answer.warnings) }
          if !answer.proposedActions.isEmpty {
            Divider().overlay(HP.Color.border)
            Text("Proposed coach actions")
              .font(HP.Font.headline)
              .foregroundStyle(HP.Color.text)
            ForEach(answer.proposedActions) { action in
              VStack(alignment: .leading, spacing: 3) {
                Text(action.actionType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                  .font(HP.Font.callout.weight(.semibold))
                  .foregroundStyle(HP.Color.text)
                Text(action.explanation)
                  .font(HP.Font.callout)
                  .foregroundStyle(HP.Color.text)
                  .fixedSize(horizontal: false, vertical: true)
                Text("Requires coach approval")
                  .font(HP.Font.caption)
                  .foregroundStyle(HP.Color.warning)
              }
            }
          }
        } else {
          let failure = SDCopilotFailurePresentation(code: message.safeErrorCode)
          Text(failure.message)
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
          #if DEBUG
          if let code = failure.code {
            DisclosureGroup("Technical details") {
              Text("Code: \(code)")
                .font(.caption.monospaced())
                .textSelection(.enabled)
            }
          }
          #endif
        }
        if let citations = message.citations, !citations.isEmpty {
          Divider().overlay(HP.Color.border)
          Text("Evidence citations")
            .font(HP.Font.headline)
            .foregroundStyle(HP.Color.text)
          ForEach(citations) { citation in
            Button { onCitation(citation) } label: {
              HStack(spacing: HP.Space.sm) {
                Image(systemName: "doc.text.magnifyingglass")
                  .accessibilityHidden(true)
                Text(citation.displayLabel)
                  .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: HP.Space.sm)
                Image(systemName: "chevron.right")
                  .accessibilityHidden(true)
              }
              .frame(minHeight: 44)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.accent)
            .accessibilityLabel("Evidence citation, \(citation.displayLabel)")
          }
        }
        Menu("Rate this answer") {
          ForEach(SDCopilotFeedbackType.allCases, id: \.self) { type in
            Button(type.title) { onFeedback(type) }
          }
        }
        .font(HP.Font.callout)
        .frame(minHeight: 44)
      }
    }
  }

  private var copilotIdentity: some View {
    Label("Home Plate Copilot", systemImage: "sparkles")
      .font(HP.Font.headline)
      .foregroundStyle(HP.Color.text)
      .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder
  private func claimSection(_ title: String, rows: [(String, [String])]) -> some View {
    if !rows.isEmpty {
      Divider().overlay(HP.Color.border)
      Text(title)
        .font(HP.Font.headline)
        .foregroundStyle(HP.Color.text)
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        VStack(alignment: .leading, spacing: 3) {
          Text(row.0)
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.text)
            .fixedSize(horizontal: false, vertical: true)
          Text("\(row.1.count) citation\(row.1.count == 1 ? "" : "s")")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
        }
      }
    }
  }

  private func warningSection(_ title: String, rows: [String]) -> some View {
    VStack(alignment: .leading, spacing: HP.Space.xs) {
      Divider().overlay(HP.Color.border)
      Text(title)
        .font(HP.Font.headline)
        .foregroundStyle(HP.Color.text)
      ForEach(rows, id: \.self) {
        Label($0, systemImage: "info.circle")
          .font(HP.Font.callout)
          .foregroundStyle(HP.Color.warning)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

private struct EvidenceCitationDetailView: View {
  @Environment(\.dismiss) private var dismiss
  let citation: SDCopilotCitation

  private var displayValue: String {
    if let value = citation.normalizedValue { return String(value) }
    return citation.observedValue ?? "Unavailable"
  }

  var body: some View {
    NavigationStack {
      HPDetailScreenLayout {
        HPWorkspaceHeader(
          "Evidence citation",
          context: citation.displayLabel
        )
      } metrics: {
        EmptyView()
      } details: {
        VStack(alignment: .leading, spacing: HP.Space.md) {
          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              HPSectionHeader("Evidence")
              LabeledContent("Metric", value: citation.canonicalMetricKey ?? citation.displayLabel)
              LabeledContent("Value", value: displayValue)
              LabeledContent("Unit", value: citation.unit ?? "Not applicable")
              LabeledContent("Date", value: citation.observedAt ?? "Unavailable")
            }
          }

          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              HPSectionHeader("Provenance")
              LabeledContent("Source", value: citation.sourceEntityType)
              LabeledContent("Provider", value: citation.sourceProvider ?? "Home Plate")
              LabeledContent("Verification", value: citation.verificationStatus ?? "Not supplied")
              if let rule = citation.deterministicRuleId {
                LabeledContent("Calculation rule", value: rule)
              }
            }
          }

          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              HPSectionHeader("Why this supports the answer")
              Text(citation.explanation)
                .font(HP.Font.callout)
                .foregroundStyle(HP.Color.text)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      } related: { _ in
        EmptyView()
      } primaryAction: {
        EmptyView()
      }
      .navigationTitle("Evidence citation")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { dismiss() }
            #if os(macOS)
            .keyboardShortcut(.cancelAction)
            #endif
        }
      }
    }
  }
}

struct ParentUpdateDraftDetailView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var detail: SDParentDraftDetailResponse?
  @State private var edited: SDParentUpdateContent?
  @State private var isWorking = false
  @State private var errorMessage: String?
  let player: Profile
  let draftId: UUID

  var body: some View {
    draftBody
    .navigationTitle("Parent update draft")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Close") { dismiss() }
          #if os(macOS)
          .keyboardShortcut(.cancelAction)
          #endif
      }
    }
    .task(id: "\(appState.activeOrgAuthorizationKey):\(draftId)") { await load() }
  }

  @ViewBuilder
  private var draftBody: some View {
    if let detail, edited != nil {
      draftForm(detail)
    } else if let errorMessage {
      HPScreenScaffold(maxContentWidth: 720) { _ in
        HPCard {
          HPErrorState(title: "Draft unavailable", message: errorMessage)
        }
      }
    } else {
      HPScreenScaffold(maxContentWidth: 720) { _ in
        HPCard {
          HPLoadingState(text: "Loading draft…")
        }
      }
    }
  }

  private func draftForm(_ detail: SDParentDraftDetailResponse) -> some View {
    HPFormScreenLayout { _ in
      HPWorkspaceHeader(
        "Parent update draft",
        context: player.displayName
      )
    } sections: { _ in
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Draft status") {
              HPStatusBadge(
                text: detail.draft.status.rawValue.capitalized,
                kind: draftStatusKind(detail.draft.status)
              )
            }
            Label(
              "Not shared with parent.",
              systemImage: "person.crop.circle.badge.exclamationmark"
            )
            .font(HP.Font.headline)
            .foregroundStyle(HP.Color.warning)
            .fixedSize(horizontal: false, vertical: true)
            LabeledContent("Status", value: detail.draft.status.rawValue.capitalized)
            LabeledContent("Player", value: player.displayName)
          }
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.md) {
            HPSectionHeader("Coach-edited version")
            contentEditors(editedContentBinding)
          }
        }

        HPCard {
          DisclosureGroup("Compare generated original") {
            parentContent(detail.draft.generatedOriginal)
              .padding(.top, HP.Space.sm)
          }
          .font(HP.Font.headline)
          .foregroundStyle(HP.Color.text)
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Review history") {
              HPStatusBadge(text: "\(detail.reviewEvents.count)", kind: .neutral)
            }
            ForEach(detail.reviewEvents) { event in
              VStack(alignment: .leading, spacing: 2) {
                Text(event.eventType.capitalized)
                  .font(HP.Font.headline)
                  .foregroundStyle(HP.Color.text)
                Text(event.createdAt)
                  .font(HP.Font.caption)
                  .foregroundStyle(HP.Color.textMuted)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }

        if let errorMessage {
          HPCard {
            HPErrorState(title: "Draft action failed", message: errorMessage)
          }
        }
      }
    } primaryAction: { context in
      HPButton(
        title: "Save edits",
        systemImage: "square.and.arrow.down",
        variant: .primary,
        size: .lg,
        fullWidth: context.isAccessibilitySize
      ) {
        Task { await save(markReviewed: false) }
      }
      .disabled(isWorking || !canEdit(detail.draft.status))
    } secondaryAction: { context in
      ViewThatFits(in: .horizontal) {
        HStack(spacing: HP.Space.xs) {
          secondaryLifecycleButtons(detail.draft.status, fullWidth: false)
        }
        VStack(alignment: .leading, spacing: HP.Space.xs) {
          secondaryLifecycleButtons(detail.draft.status, fullWidth: true)
        }
      }
      .frame(maxWidth: context.isAccessibilitySize ? .infinity : nil, alignment: .leading)
    }
  }

  private var editedContentBinding: Binding<SDParentUpdateContent> {
    Binding(
      get: { edited ?? detail!.draft.editedContent },
      set: { edited = $0 }
    )
  }

  private func draftStatusKind(_ status: SDParentDraftStatus) -> HPStatusKind {
    switch status {
    case .generated: .warning
    case .reviewed: .info
    case .approved: .success
    case .rejected: .danger
    case .archived, .unknown: .neutral
    }
  }

  @ViewBuilder
  private func secondaryLifecycleButtons(
    _ status: SDParentDraftStatus,
    fullWidth: Bool
  ) -> some View {
    HPButton(
      title: "Mark reviewed",
      variant: .secondary,
      size: .md,
      fullWidth: fullWidth
    ) {
      Task { await save(markReviewed: true) }
    }
    .disabled(isWorking || status != .generated)

    HPButton(
      title: "Approve",
      variant: .secondary,
      size: .md,
      fullWidth: fullWidth
    ) {
      Task { await transition("approve_parent_draft") }
    }
    .disabled(isWorking || status != .reviewed)

    HPButton(
      title: "Reject",
      variant: .destructive,
      size: .md,
      fullWidth: fullWidth
    ) {
      Task { await transition("reject_parent_draft") }
    }
    .disabled(isWorking || ![.generated, .reviewed].contains(status))

    HPButton(
      title: "Archive",
      variant: .tertiary,
      size: .md,
      fullWidth: fullWidth
    ) {
      Task { await transition("archive_parent_draft") }
    }
    .disabled(isWorking || status == .archived)
  }

  private func canEdit(_ status: SDParentDraftStatus) -> Bool {
    [.generated, .reviewed].contains(status)
  }

  @ViewBuilder
  private func contentEditors(_ content: Binding<SDParentUpdateContent>) -> some View {
    HPFormField(label: "Recent work", text: content.recentWork, kind: .multiline)
    HPFormField(
      label: "Positive developments",
      text: content.positiveDevelopments,
      kind: .multiline
    )
    HPFormField(label: "Current focus", text: content.currentFocus, kind: .multiline)
    HPFormField(label: "Consistency", text: content.consistency, kind: .multiline)
    HPFormField(label: "Recent testing", text: content.recentTesting, kind: .multiline)
    HPFormField(
      label: "Evidence limitations",
      text: content.evidenceLimitations,
      kind: .multiline
    )
    HPFormField(
      label: "Upcoming next steps",
      text: content.upcomingNextSteps,
      kind: .multiline
    )
  }

  private func parentContent(_ content: SDParentUpdateContent) -> some View {
    VStack(alignment: .leading, spacing: HP.Space.sm) {
      parentSection("Recent work", content.recentWork)
      parentSection("Positive developments", content.positiveDevelopments)
      parentSection("Current focus", content.currentFocus)
      parentSection("Consistency", content.consistency)
      parentSection("Recent testing", content.recentTesting)
      parentSection("Evidence limitations", content.evidenceLimitations)
      parentSection("Upcoming next steps", content.upcomingNextSteps)
    }
  }

  private func parentSection(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(HP.Font.caption.weight(.semibold))
        .foregroundStyle(HP.Color.textMuted)
      Text(value)
        .font(HP.Font.callout)
        .foregroundStyle(HP.Color.text)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func load() async {
    guard let service = appState.supabase, let organizationId = appState.activeOrgId else { return }
    do {
      let loaded = try await service.parentUpdateDraft(organizationId: organizationId, draftId: draftId)
      guard appState.activeOrgId == organizationId, loaded.draft.playerId == player.id else { return }
      detail = loaded
      edited = loaded.draft.editedContent
    } catch { errorMessage = error.localizedDescription }
  }

  private func save(markReviewed: Bool) async {
    guard !isWorking, let service = appState.supabase, let organizationId = appState.activeOrgId, let edited else { return }
    isWorking = true; defer { isWorking = false }
    do {
      _ = try await service.updateParentUpdateDraft(organizationId: organizationId, draftId: draftId, content: markReviewed ? nil : edited, markReviewed: markReviewed, note: nil)
      await load()
    } catch { errorMessage = error.localizedDescription }
  }

  private func transition(_ action: String) async {
    guard !isWorking, let service = appState.supabase, let organizationId = appState.activeOrgId else { return }
    isWorking = true; defer { isWorking = false }
    do {
      _ = try await service.transitionParentUpdateDraft(organizationId: organizationId, draftId: draftId, action: action, note: nil)
      await load()
    } catch { errorMessage = error.localizedDescription }
  }
}

private func copilotQualityBadge(_ quality: SDCopilotQualityStatus) -> some View {
  let kind: HPStatusKind = switch quality {
  case .sufficient: .success
  case .limited, .stale, .conflicting: .warning
  case .rejected, .unknown: .danger
  case .unavailable: .neutral
  }
  return HPStatusBadge(text: quality.rawValue.capitalized, kind: kind)
}
