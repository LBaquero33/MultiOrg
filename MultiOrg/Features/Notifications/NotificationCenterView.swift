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
          .frame(width: 38, height: 38)
          .background(.ultraThinMaterial, in: Circle())
        if viewModel.totalUnread > 0 {
          NotificationBadge(count: viewModel.totalUnread)
            .offset(x: 5, y: -5)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Notifications")
    .accessibilityValue(viewModel.totalUnread == 0 ? "No unread notifications" : "\(viewModel.totalUnread) unread")
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
  }

  private var activeOrganizationAnnouncementContext: NotificationAnnouncementContext? {
    guard appState.canAdminActiveOrg, let organizationId = appState.activeOrgId else { return nil }
    let name = appState.availableOrganizations.first(where: { $0.id == organizationId })?.name
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
      .font(.caption2.weight(.bold))
      .foregroundStyle(.white)
      .padding(.horizontal, count > 9 ? 5 : 4)
      .frame(minWidth: 18, minHeight: 18)
      .background(Color.red, in: Capsule())
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
    VStack(spacing: 0) {
      controls
      Divider()
      notificationContent
    }
    .navigationTitle("Notifications")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          Task { await refresh() }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
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

  private var controls: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        if selectedOrganizationId != nil {
          Picker("Scope", selection: $scopeToSelectedOrganization) {
            Text("All Organizations").tag(false)
            Text(selectedOrganizationName).tag(true)
          }
          .pickerStyle(.segmented)
        }

        if announcementContext?.canCreate == true {
          Button {
            viewModel.clearMessages()
            isComposing = true
          } label: {
            Label("Create Announcement", systemImage: "megaphone.fill")
          }
          .buttonStyle(.borderedProminent)
        }
      }

      HStack {
        Toggle("Unread only", isOn: $viewModel.unreadOnly)
          .toggleStyle(.switch)
        Spacer()
        Button("Mark All Read") {
          Task {
            await viewModel.markAllRead(
              organizationId: effectiveOrganizationId,
              service: appState.supabase
            )
          }
        }
        .disabled(viewModel.isMarkingAllRead || viewModel.totalUnread == 0)
      }

      if let message = viewModel.announcementMessage {
        Text(message)
          .font(.footnote)
          .foregroundStyle(.green)
      }
    }
    .padding()
  }

  @ViewBuilder
  private var notificationContent: some View {
    if viewModel.isLoading && viewModel.notifications.isEmpty {
      ProgressView("Loading notifications…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let error = viewModel.errorMessage, viewModel.notifications.isEmpty {
      ContentUnavailableView(
        "Notifications unavailable",
        systemImage: "exclamationmark.triangle",
        description: Text(error)
      )
      .overlay(alignment: .bottom) {
        Button("Try Again") { Task { await refresh() } }
          .buttonStyle(.borderedProminent)
          .padding()
      }
    } else if viewModel.notifications.isEmpty {
      ContentUnavailableView(
        viewModel.unreadOnly ? "No unread notifications" : "No notifications yet",
        systemImage: "bell.slash",
        description: Text("Important organization updates will appear here.")
      )
    } else {
      List {
        if let error = viewModel.errorMessage {
          Text(error)
            .font(.footnote)
            .foregroundStyle(.red)
        }
        ForEach(viewModel.notifications) { notification in
          Button {
            open(notification)
          } label: {
            NotificationRow(notification: notification)
          }
          .buttonStyle(.plain)
        }
        if viewModel.hasMore {
          HStack {
            Spacer()
            Button(viewModel.isLoadingMore ? "Loading…" : "Load More") {
              Task {
                await viewModel.loadMore(
                  organizationId: effectiveOrganizationId,
                  service: appState.supabase
                )
              }
            }
            .disabled(viewModel.isLoadingMore)
            Spacer()
          }
        }
      }
      .refreshable { await refresh() }
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
      _ = await viewModel.markRead(notification, service: appState.supabase)
      selectedNotification = viewModel.notifications.first(where: { $0.id == notification.id }) ?? notification
    }
  }
}

struct NotificationRow: View {
  let notification: AppNotification

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: notification.category.systemImage)
        .font(.title3)
        .foregroundStyle(notification.isUnread ? Color.accentColor : DHDTheme.textSecondary)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 5) {
        HStack(alignment: .firstTextBaseline) {
          Text(notification.title)
            .font(.headline)
            .foregroundStyle(DHDTheme.textPrimary)
          Spacer()
          if notification.isUnread {
            Circle()
              .fill(Color.accentColor)
              .frame(width: 8, height: 8)
              .accessibilityLabel("Unread")
          }
        }
        Text(notification.body)
          .font(.subheadline)
          .foregroundStyle(DHDTheme.textSecondary)
          .lineLimit(2)
        HStack {
          Text(notification.organizationName)
          Spacer()
          Text(relativeTimestamp)
        }
        .font(.caption)
        .foregroundStyle(DHDTheme.textSecondary)
      }
    }
    .padding(.vertical, 5)
    .contentShape(Rectangle())
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
    Form {
      if context.supportMode {
        Section {
          Text("Platform Support — sending on behalf of \(context.organizationName)")
            .font(.headline)
          Text("This does not make you an organization owner or member.")
            .font(.footnote)
            .foregroundStyle(DHDTheme.textSecondary)
        }
      }

      Section("Audience") {
        Picker("Recipients", selection: $draft.audience) {
          ForEach(AnnouncementAudience.allCases) { audience in
            Text(audience.title).tag(audience)
          }
        }
      }

      Section("Announcement") {
        TextField("Title", text: $draft.title)
        Text("\(draft.title.count)/\(AnnouncementDraft.maximumTitleLength)")
          .font(.caption)
          .foregroundStyle(DHDTheme.textSecondary)
        TextEditor(text: $draft.body)
          .frame(minHeight: 150)
        Text("\(draft.body.count)/\(AnnouncementDraft.maximumBodyLength)")
          .font(.caption)
          .foregroundStyle(DHDTheme.textSecondary)
      }

      if let validation = draft.validationError,
         !draft.title.isEmpty || !draft.body.isEmpty {
        Section {
          Text(validation)
            .font(.footnote)
            .foregroundStyle(.red)
        }
      }
      if let error = viewModel.errorMessage {
        Section {
          Text(error)
            .font(.footnote)
            .foregroundStyle(.red)
        }
      }
    }
    .navigationTitle("Create Announcement")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
          .disabled(viewModel.isSendingAnnouncement)
      }
      ToolbarItem(placement: .confirmationAction) {
        Button(viewModel.isSendingAnnouncement ? "Sending…" : "Send") {
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
        .disabled(!draft.isValid || viewModel.isSendingAnnouncement || !context.canCreate)
      }
    }
    .onAppear { viewModel.clearMessages() }
  }
}

struct NotificationDestinationView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appState: AppState
  let notification: AppNotification

  @ViewBuilder
  var body: some View {
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
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Label(notification.organizationName, systemImage: notification.category.systemImage)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Color.accentColor)
        Text(notification.title)
          .font(.title2.weight(.bold))
        Text(notification.body)
          .font(.body)
        Divider()
        Text(fallbackSummary)
          .font(.footnote)
          .foregroundStyle(DHDTheme.textSecondary)
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle("Notification")
    .notificationDismissToolbar(dismiss: dismiss)
  }

  private var fallbackSummary: String {
    switch NotificationRouter.destination(for: notification) {
    case .paymentRequest, .payment:
      return appState.activeOrgId == notification.organizationId
        ? "Payment details are available in Billing."
        : "Switch to \(notification.organizationName) to open this item in Billing."
    case .finance:
      return "Finance details require the matching active organization and owner or administrator access."
    case .announcement:
      return "Organization announcement"
    case .detail:
      return "No additional destination is available for this notification."
    }
  }
}

private extension View {
  func notificationDismissToolbar(dismiss: DismissAction) -> some View {
    toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Done") { dismiss() }
      }
    }
  }
}
