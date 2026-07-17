import SwiftUI

struct NotificationAnnouncementContext: Identifiable, Equatable, Sendable {
  let organizationId: UUID
  let organizationName: String
  let supportMode: Bool
  let canCreate: Bool

  var id: String {
    "\(organizationId.uuidString.lowercased()):\(supportMode)"
  }
}

/// The single role-agnostic notification entry point. Inbox authorization is
/// always enforced by the notification-center Edge Function using the JWT.
struct NotificationBellButton: View {
  @EnvironmentObject private var appState: AppState
  @StateObject private var viewModel = NotificationCenterViewModel()
  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented = true
    } label: {
      ZStack(alignment: .topTrailing) {
        Image(systemName: "bell.fill")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(HP.Color.text)
          .frame(width: 44, height: 44)
          .background(HP.Color.surfaceRaised, in: Circle())
          .overlay {
            Circle()
              .strokeBorder(HP.Color.border, lineWidth: 1)
              .allowsHitTesting(false)
          }
        if viewModel.totalUnread > 0 {
          NotificationBadge(count: viewModel.totalUnread)
            .offset(x: 5, y: -5)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Notifications")
    .accessibilityValue(
      viewModel.totalUnread == 0 ? "No unread notifications" : "\(viewModel.totalUnread) unread"
    )
    .sheet(isPresented: $isPresented) {
      NavigationStack {
        NotificationCenterView(
          viewModel: viewModel,
          announcementContext: activeOrganizationAnnouncementContext
        )
        .environmentObject(appState)
      }
      #if os(macOS)
        .frame(minWidth: 620, minHeight: 620)
      #endif
    }
    .task(id: appState.myProfile?.id) {
      viewModel.resetForUser(appState.myProfile?.id)
      await viewModel.refreshBadge(service: appState.supabase)
    }
    .onChange(of: appState.activeOrgId) { _, _ in
      viewModel.organizationChanged()
      Task { await viewModel.refreshBadge(service: appState.supabase) }
    }
    .onReceive(NotificationCenter.default.publisher(for: .dhdRemoteNotificationReceived)) { _ in
      Task {
        await viewModel.refreshBadge(service: appState.supabase)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .dhdNotificationStateChanged)) { _ in
      Task {
        await viewModel.refreshBadge(service: appState.supabase)
      }
    }
  }

  private var activeOrganizationAnnouncementContext: NotificationAnnouncementContext? {
    guard appState.canAdminActiveOrg, let organizationId = appState.activeOrgId else { return nil }
    let name =
      appState.availableOrganizations.first(where: { $0.id == organizationId })?.name
      ?? appState.activeOrgSettings?.display_name
      ?? "Organization"
    return NotificationAnnouncementContext(
      organizationId: organizationId,
      organizationName: name,
      supportMode: false,
      canCreate: true
    )
  }
}

struct NotificationBadge: View {
  let count: Int

  var body: some View {
    Text(count > 99 ? "99+" : String(count))
      .font(HP.Font.badge)
      .foregroundStyle(HP.Color.onDanger)
      .padding(.horizontal, count > 9 ? 5 : 4)
      .frame(minWidth: 18, minHeight: 18)
      .background(HP.Color.danger, in: Capsule())
      .accessibilityHidden(true)
  }
}

/// Owns an independent view model for explicit platform-support navigation.
struct NotificationCenterScreen: View {
  @EnvironmentObject private var appState: AppState
  @StateObject private var viewModel = NotificationCenterViewModel()
  let announcementContext: NotificationAnnouncementContext?

  var body: some View {
    NotificationCenterView(
      viewModel: viewModel,
      announcementContext: announcementContext
    )
    .environmentObject(appState)
    .task(id: appState.myProfile?.id) {
      viewModel.resetForUser(appState.myProfile?.id)
    }
  }
}

struct NotificationCenterView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appState: AppState
  @ObservedObject var viewModel: NotificationCenterViewModel
  let announcementContext: NotificationAnnouncementContext?

  @State private var scopeToSelectedOrganization: Bool
  @State private var selectedNotification: AppNotification?
  @State private var isComposing = false

  init(
    viewModel: NotificationCenterViewModel,
    announcementContext: NotificationAnnouncementContext?
  ) {
    self.viewModel = viewModel
    self.announcementContext = announcementContext
    _scopeToSelectedOrganization = State(initialValue: announcementContext != nil)
  }

  var body: some View {
    HPListScreenLayout {
      HPWorkspaceHeader(
        "Notifications",
        orgLabel: scopeToSelectedOrganization ? selectedOrganizationName : "Home Plate",
        context: notificationContext
      ) {
        if announcementContext?.canCreate == true {
          HPButton(
            title: "Create announcement",
            systemImage: "megaphone.fill",
            variant: .primary,
            size: .sm,
            action: {
              viewModel.clearMessages()
              isComposing = true
            }
          )
        }
      }
    } controls: {
      controls
    } results: { context in
      notificationContent(context)
    }
    .navigationTitle("Notifications")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Close") { dismiss() }
          .frame(minHeight: 44)
          .contentShape(Rectangle())
      }
      ToolbarItem(placement: .automatic) {
        Button {
          Task { await refresh() }
        } label: {
          Image(systemName: "arrow.clockwise")
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Refresh notifications")
        .disabled(viewModel.isLoading)
      }
    }
    .task(id: refreshIdentity) {
      viewModel.resetForUser(appState.myProfile?.id)
      await refresh()
    }
    .onChange(of: appState.activeOrgId) { _, _ in
      guard announcementContext == nil else { return }
      viewModel.organizationChanged()
      scopeToSelectedOrganization = false
      Task { await refresh() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .dhdRemoteNotificationReceived)) { _ in
      Task { await refresh() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .dhdNotificationStateChanged)) { _ in
      Task { await refresh() }
    }
    .sheet(item: $selectedNotification) { notification in
      NavigationStack {
        NotificationDestinationView(notification: notification)
      }
      #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
      #endif
    }
    .sheet(isPresented: $isComposing) {
      if let announcementContext {
        NavigationStack {
          AnnouncementComposerView(
            context: announcementContext,
            viewModel: viewModel
          )
          .environmentObject(appState)
        }
        #if os(macOS)
          .frame(minWidth: 520, minHeight: 520)
        #endif
      }
    }
    .refreshable { await refresh() }
    #if os(macOS)
      .onExitCommand { dismiss() }
    #endif
  }

  private var refreshIdentity: String {
    [
      appState.myProfile?.id.uuidString.lowercased() ?? "signed-out",
      effectiveOrganizationId?.uuidString.lowercased() ?? "all",
      String(viewModel.unreadOnly),
    ].joined(separator: ":")
  }

  private var selectedOrganizationId: UUID? {
    announcementContext?.organizationId ?? appState.activeOrgId
  }

  private var effectiveOrganizationId: UUID? {
    scopeToSelectedOrganization ? selectedOrganizationId : nil
  }

  private var selectedOrganizationName: String {
    announcementContext?.organizationName
      ?? appState.availableOrganizations.first(where: { $0.id == selectedOrganizationId })?.name
      ?? "Selected Organization"
  }

  private var notificationContext: String {
    if viewModel.notifications.isEmpty {
      return viewModel.unreadOnly ? "Unread notifications" : "Organization updates"
    }
    let suffix = viewModel.notifications.count == 1 ? "notification" : "notifications"
    return "\(viewModel.notifications.count) loaded \(suffix)"
  }

  private var unreadFilter: Binding<Set<String>> {
    Binding(
      get: { viewModel.unreadOnly ? ["Unread only"] : [] },
      set: { viewModel.unreadOnly = $0.contains("Unread only") }
    )
  }

  private var controls: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        if selectedOrganizationId != nil {
          VStack(alignment: .leading, spacing: 6) {
            Text("SCOPE")
              .font(HP.Font.eyebrow)
              .tracking(HP.Font.eyebrowTracking)
              .foregroundStyle(HP.Color.textMuted)
            HPSegmentedControl(
              options: [
                (value: false, label: "All Organizations"),
                (value: true, label: selectedOrganizationName),
              ],
              selection: $scopeToSelectedOrganization
            )
          }
        }

        VStack(alignment: .leading, spacing: 6) {
          Text("FILTER")
            .font(HP.Font.eyebrow)
            .tracking(HP.Font.eyebrowTracking)
            .foregroundStyle(HP.Color.textMuted)
          HPFilterBar(pills: ["Unread only"], active: unreadFilter)
        }

        ViewThatFits(in: .horizontal) {
          HStack(spacing: HP.Space.sm) {
            resultSummary
            Spacer(minLength: HP.Space.sm)
            markAllReadButton
          }
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            resultSummary
            markAllReadButton
          }
        }

        if let message = viewModel.announcementMessage {
          Label(message, systemImage: "checkmark.circle.fill")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.success)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private var resultSummary: some View {
    HStack(spacing: HP.Space.xs) {
      Text("\(viewModel.notifications.count) loaded")
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
      if viewModel.isLoading {
        HPStatusBadge(text: "Refreshing", kind: .info)
      } else if viewModel.errorMessage != nil, viewModel.notifications.isEmpty {
        HPStatusBadge(text: "Unavailable", kind: .danger)
      } else {
        HPStatusBadge(
          text: viewModel.totalUnread == 0 ? "All caught up" : "\(viewModel.totalUnread) unread",
          kind: viewModel.totalUnread == 0 ? .success : .gold
        )
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var markAllReadButton: some View {
    HPButton(
      title: "Mark all read",
      systemImage: "checkmark.circle",
      variant: .secondary,
      size: .sm,
      isLoading: viewModel.isMarkingAllRead,
      action: {
        Task {
          await viewModel.markAllRead(
            organizationId: effectiveOrganizationId,
            service: appState.supabase
          )
        }
      }
    )
    .disabled(viewModel.isMarkingAllRead || viewModel.totalUnread == 0)
  }

  @ViewBuilder
  private func notificationContent(_ context: HPScreenLayoutContext) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Inbox") {
          HPStatusBadge(text: "\(viewModel.notifications.count)", kind: .neutral)
        }

        if viewModel.isLoading && viewModel.notifications.isEmpty {
          HPLoadingState(text: "Loading notifications…")
        } else if let error = viewModel.errorMessage, viewModel.notifications.isEmpty {
          HPErrorState(title: "Notifications unavailable", message: error)
          HPButton(
            title: "Try again",
            systemImage: "arrow.clockwise",
            variant: .secondary,
            size: .md,
            fullWidth: context.isAccessibilitySize,
            action: { Task { await refresh() } }
          )
          .frame(maxWidth: .infinity, alignment: .center)
        } else if viewModel.notifications.isEmpty {
          HPEmptyState(
            title: viewModel.unreadOnly ? "No unread notifications" : "No notifications yet",
            message: "Important organization updates will appear here.",
            systemImage: "bell.slash"
          )
        } else {
          if let error = viewModel.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.danger)
              .fixedSize(horizontal: false, vertical: true)
          }

          ForEach(viewModel.notifications) { notification in
            Button {
              open(notification)
            } label: {
              NotificationRow(notification: notification)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityHint("Opens this notification")

            if notification.id != viewModel.notifications.last?.id {
              Divider()
                .overlay(HP.Color.border.opacity(0.5))
                .allowsHitTesting(false)
            }
          }

          if viewModel.hasMore {
            HPButton(
              title: "Load more",
              systemImage: "arrow.down.circle",
              variant: .secondary,
              size: .md,
              isLoading: viewModel.isLoadingMore,
              action: {
                Task {
                  await viewModel.loadMore(
                    organizationId: effectiveOrganizationId,
                    service: appState.supabase
                  )
                }
              }
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .disabled(viewModel.isLoadingMore)
          }
        }
      }
    }
  }

  private func refresh() async {
    await viewModel.refresh(
      organizationId: effectiveOrganizationId,
      service: appState.supabase
    )
  }

  private func open(_ notification: AppNotification) {
    Task {
      if case .chatConversation = NotificationRouter.destination(for: notification) {
        await appState.openNotification(notification, markNonChatRead: false)
        dismiss()
        return
      }
      _ = await viewModel.markRead(notification, service: appState.supabase)
      selectedNotification =
        viewModel.notifications.first(where: { $0.id == notification.id }) ?? notification
    }
  }
}

struct NotificationRow: View {
  let notification: AppNotification

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: notification.category.systemImage)
        .font(.title3)
        .foregroundStyle(notification.isUnread ? HP.Color.accent : HP.Color.textMuted)
        .frame(width: 28, height: 44, alignment: .top)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: HP.Space.xs) {
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline, spacing: HP.Space.sm) {
            notificationTitle
            Spacer(minLength: 0)
            if notification.isUnread {
              HPStatusBadge(text: "Unread", kind: .gold)
            }
          }
          VStack(alignment: .leading, spacing: HP.Space.xs) {
            notificationTitle
            if notification.isUnread {
              HPStatusBadge(text: "Unread", kind: .gold)
            }
          }
        }
        Text(notification.body)
          .font(HP.Font.callout)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
        ViewThatFits(in: .horizontal) {
          HStack(spacing: HP.Space.sm) {
            Text(notification.organizationName)
            Spacer(minLength: HP.Space.sm)
            Text(relativeTimestamp)
          }
          VStack(alignment: .leading, spacing: 2) {
            Text(notification.organizationName)
            Text(relativeTimestamp)
          }
        }
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
      }
    }
    .padding(.vertical, HP.Space.xs)
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  private var notificationTitle: some View {
    Text(notification.title)
      .font(HP.Font.headline)
      .foregroundStyle(HP.Color.text)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var relativeTimestamp: String {
    guard let date = notification.createdDate else { return "Recently" }
    return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
  }
}

struct AnnouncementComposerView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appState: AppState
  let context: NotificationAnnouncementContext
  @ObservedObject var viewModel: NotificationCenterViewModel
  @State private var draft = AnnouncementDraft()

  var body: some View {
    HPScreenScaffold(maxContentWidth: 720) { _ in
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPWorkspaceHeader(
          "Create Announcement",
          orgLabel: context.organizationName,
          context: context.supportMode
            ? "Platform Support · sending on behalf of this organization"
            : "Organization announcement"
        )

        if context.supportMode {
          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.xs) {
              Label(
                "Platform Support — sending on behalf of \(context.organizationName)",
                systemImage: "person.badge.shield.checkmark"
              )
              .font(HP.Font.headline)
              .foregroundStyle(HP.Color.accent)
              Text("This does not make you an organization owner or member.")
                .font(HP.Font.caption)
                .foregroundStyle(HP.Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Audience")
            Picker("Recipients", selection: $draft.audience) {
              ForEach(AnnouncementAudience.allCases) { audience in
                Text(audience.title).tag(audience)
              }
            }
            .pickerStyle(.menu)
            .tint(HP.Color.accent)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          }
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.md) {
            HPSectionHeader("Announcement")
            HPFormField(
              label: "Title",
              text: $draft.title,
              placeholder: "Announcement title",
              helper: "\(draft.title.count)/\(AnnouncementDraft.maximumTitleLength)"
            )
            HPFormField(
              label: "Message",
              text: $draft.body,
              kind: .multiline,
              placeholder: "Write your announcement",
              helper: "\(draft.body.count)/\(AnnouncementDraft.maximumBodyLength)"
            )

            if let validation = draft.validationError,
              !draft.title.isEmpty || !draft.body.isEmpty
            {
              Label(validation, systemImage: "exclamationmark.circle.fill")
                .font(HP.Font.caption)
                .foregroundStyle(HP.Color.danger)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }

        if let error = viewModel.errorMessage {
          HPCard(style: .flat) {
            Label(error, systemImage: "exclamationmark.triangle.fill")
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.danger)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
    .navigationTitle("Create Announcement")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
          .frame(minHeight: 44)
          .contentShape(Rectangle())
          .disabled(viewModel.isSendingAnnouncement)
      }
      ToolbarItem(placement: .confirmationAction) {
        HPButton(
          title: "Send",
          variant: .primary,
          size: .sm,
          isLoading: viewModel.isSendingAnnouncement,
          action: {
            Task {
              let sent = await viewModel.sendAnnouncement(
                organizationId: context.organizationId,
                draft: draft,
                supportMode: context.supportMode,
                service: appState.supabase
              )
              if sent { dismiss() }
            }
          }
        )
        .disabled(!draft.isValid || viewModel.isSendingAnnouncement || !context.canCreate)
      }
    }
    .onAppear { viewModel.clearMessages() }
    #if os(macOS)
      .onExitCommand {
        if !viewModel.isSendingAnnouncement { dismiss() }
      }
    #endif
  }
}

struct NotificationDestinationView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appState: AppState
  let notification: AppNotification

  var body: some View {
    destination
      #if os(macOS)
        .onExitCommand { dismiss() }
      #endif
  }

  @ViewBuilder
  private var destination: some View {
    switch NotificationRouter.destination(for: notification) {
    case .paymentRequest where appState.activeOrgId == notification.organizationId,
      .payment where appState.activeOrgId == notification.organizationId:
      AccountView()
        .navigationTitle("Billing")
        .notificationDismissToolbar(dismiss: dismiss)
    case .finance
    where appState.activeOrgId == notification.organizationId && appState.canAdminActiveOrg:
      FinanceDashboardView(
        organizationId: notification.organizationId,
        organizationName: notification.organizationName,
        platformSupportMode: false
      )
      .environmentObject(appState)
      .notificationDismissToolbar(dismiss: dismiss)
    default:
      detail
    }
  }

  private var detail: some View {
    HPScreenScaffold(maxContentWidth: 760) { _ in
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPWorkspaceHeader(
          "Notification",
          orgLabel: notification.organizationName,
          context: notification.isUnread ? "Unread organization update" : "Organization update"
        )
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.md) {
            ViewThatFits(in: .horizontal) {
              HStack(alignment: .center, spacing: HP.Space.sm) {
                notificationCategoryLabel
                Spacer(minLength: HP.Space.sm)
                HPStatusBadge(
                  text: notification.isUnread ? "Unread" : "Read",
                  kind: notification.isUnread ? .gold : .success
                )
              }
              VStack(alignment: .leading, spacing: HP.Space.sm) {
                notificationCategoryLabel
                HPStatusBadge(
                  text: notification.isUnread ? "Unread" : "Read",
                  kind: notification.isUnread ? .gold : .success
                )
              }
            }
            Text(notification.title)
              .font(HP.Font.title)
              .tracking(HP.Font.titleTracking)
              .foregroundStyle(HP.Color.text)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityAddTraits(.isHeader)
            Text(notification.body)
              .font(HP.Font.body)
              .foregroundStyle(HP.Color.text)
              .fixedSize(horizontal: false, vertical: true)
            Divider()
              .overlay(HP.Color.border)
              .allowsHitTesting(false)
            Text(fallbackSummary)
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.textMuted)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
    .navigationTitle("Notification")
    .notificationDismissToolbar(dismiss: dismiss)
  }

  private var notificationCategoryLabel: some View {
    Label(notification.organizationName, systemImage: notification.category.systemImage)
      .font(HP.Font.callout.weight(.semibold))
      .foregroundStyle(HP.Color.accent)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var fallbackSummary: String {
    switch NotificationRouter.destination(for: notification) {
    case .paymentRequest, .payment:
      return appState.activeOrgId == notification.organizationId
        ? "Payment details are available in Billing."
        : "Switch to \(notification.organizationName) to open this item in Billing."
    case .finance:
      return
        "Finance details require the matching active organization and owner or administrator access."
    case .chatConversation:
      return "Open Chat to view this conversation."
    case .announcement:
      return "Organization announcement"
    case .detail:
      return "No additional destination is available for this notification."
    }
  }
}

extension View {
  fileprivate func notificationDismissToolbar(dismiss: DismissAction) -> some View {
    toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Done") { dismiss() }
          .frame(minHeight: 44)
          .contentShape(Rectangle())
      }
    }
  }
}
