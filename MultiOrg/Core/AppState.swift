import Foundation
import SwiftUI
import Supabase
import UserNotifications

enum AppFlags {
  /// Temporary paywall bypass. When enabled, the app will not block players behind `sd_access_entitlements`.
  ///
  /// Set in `Configs/Secrets.xcconfig`:
  /// `DHD_BYPASS_ACCESS = 1`
  static var bypassAccessCheck: Bool {
    #if !DEBUG
    return false
    #else
    let rawAny = Bundle.main.object(forInfoDictionaryKey: "DHD_BYPASS_ACCESS")
    if let b = rawAny as? Bool { return b }
    let raw = (rawAny as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    if raw.isEmpty { return false }
    return ["1", "true", "yes", "y", "on"].contains(raw)
    #endif
  }

}

@MainActor
final class AppState: ObservableObject {
  @Published private(set) var configError: String?
  @Published private(set) var isAuthenticated: Bool = false
  @Published var authError: String?
  @Published var profileLoadError: String?
  @Published private(set) var myProfile: Profile?
  @Published private(set) var myOnboarding: SDPlayerOnboarding?
  @Published private(set) var myEntitlement: SDAccessEntitlement?
  @Published var needsAccess: Bool = false
  @Published var needsOnboarding: Bool = false
  @Published var activeOrgId: UUID?
  @Published private(set) var myOrgMemberships: [SDOrgMembership] = []
  @Published private(set) var availableOrganizations: [SDOrg] = []
  @Published private(set) var activeOrgSettings: SDOrgSettings?
  @Published var showOnboardingEditor: Bool = false
  @Published var globalToastText: String?
  @Published var chatLastInsert: SupabaseService.ChatMessageInsert?
  @Published var chatReadUpdate: ChatReadUpdate?
  @Published var requestedChatChannelId: UUID?
  @Published var requestedNotification: AppNotification?
  @Published private(set) var isPlatformAdmin = false

  let pushNotifications = PushNotificationManager()
  private let pendingPushNotificationKey = "homePlate.pendingNotificationId"

  private(set) var supabase: SupabaseService?
  private var coachListenersStarted = false
  private var chatListenerStarted = false
  private var chatListenerOrganizationId: UUID?
  private var activeChatChannelId: UUID?

  init() {
    NotificationCenter.default.addObserver(
      forName: .dhdOpenChatChannel,
      object: nil,
      queue: .main
    ) { [weak self] note in
      guard let channelId = note.object as? UUID else { return }
      Task { @MainActor in self?.requestedChatChannelId = channelId }
    }
    NotificationCenter.default.addObserver(
      forName: .dhdRemoteDeviceToken, object: nil, queue: .main
    ) { [weak self] note in
      guard let data = note.object as? Data else { return }
      Task { @MainActor in await self?.pushNotifications.receiveDeviceToken(data) }
    }
    NotificationCenter.default.addObserver(
      forName: .dhdRemoteRegistrationFailed, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.pushNotifications.receiveRegistrationFailure() }
    }
    NotificationCenter.default.addObserver(
      forName: .dhdOpenRemoteNotification, object: nil, queue: .main
    ) { [weak self] note in
      guard let id = note.object as? UUID else { return }
      Task { @MainActor in await self?.openRemoteNotification(id) }
    }
  }

  var activeOrgMembership: SDOrgMembership? {
    OrganizationAuthorization.activeMembership(
      userId: myProfile?.id,
      orgId: activeOrgId,
      memberships: myOrgMemberships
    )
  }

  var canAdminActiveOrg: Bool {
    activeOrgMembership?.canAdministerOrganization == true
  }

  var canStaffActiveOrg: Bool {
    activeOrgMembership?.isStaff == true
  }

  var activeOrgAuthorizationKey: String {
    guard let membership = activeOrgMembership else {
      return "\(activeOrgId?.uuidString.lowercased() ?? "none"):none"
    }
    return [
      membership.org_id.uuidString.lowercased(),
      membership.user_id.uuidString.lowercased(),
      membership.normalizedRole,
      membership.normalizedStatus,
    ].joined(separator: ":")
  }

  /// Coaches can browse the organization roster, but an organization may
  /// restrict mutations to players assigned to the coach's own team.
  func canManagePlayerOnActiveTeam(_ playerId: UUID) async -> Bool {
    guard activeOrgSettings?.teamPolicy("restrictCoachActionsToTeam", default: true) != false else { return true }
    // Organization owners/admins retain full management access. Platform
    // administration is deliberately separate from organization authority.
    guard activeOrgMembership?.canAdministerOrganization != true else { return true }
    guard let supabase, let orgId = activeOrgId, let myId = myProfile?.id else { return false }
    do {
      let response = try await supabase.adminListTeams(orgId: orgId)
      let myTeam = response.members.first(where: { $0.member_id == myId })?.team_id
      let playerTeam = response.members.first(where: { $0.member_id == playerId })?.team_id
      return myTeam != nil && myTeam == playerTeam
    } catch {
      return false
    }
  }

  private func clearOrgContext() {
    clearChatContext()
    activeOrgId = nil
    myOrgMemberships = []
    availableOrganizations = []
    activeOrgSettings = nil
    isPlatformAdmin = false
  }

  private func clearChatContext() {
    activeChatChannelId = nil
    chatLastInsert = nil
    chatReadUpdate = nil
    requestedChatChannelId = nil
    requestedNotification = nil
  }

  func bootstrap() async {
    switch SupabaseConfig.fromInfoPlist() {
    case .failure(let err):
      configError = err.localizedDescription
      isAuthenticated = false
      return
    case .success(let config):
      configError = nil
      supabase = SupabaseService(config: config)
    }

    guard let supabase else { return }
    do {
      try await supabase.restoreSessionIfAny()
      await loadMyProfile()
      guard myProfile != nil else {
        throw LoginBootstrapError.profileUnavailable
      }
      isAuthenticated = true
      startLiveUpdates()
      if myProfile?.isPlayer == true {
        if AppFlags.bypassAccessCheck {
          myEntitlement = nil
          needsAccess = false
        } else {
          await refreshEntitlement()
        }
        await refreshOnboarding()
      } else {
        myOnboarding = nil
        needsOnboarding = false
        myEntitlement = nil
        needsAccess = false
      }
    } catch {
      isAuthenticated = false
      myProfile = nil
      myOnboarding = nil
      needsOnboarding = false
      myEntitlement = nil
      needsAccess = false
      clearOrgContext()
      coachListenersStarted = false
    }
  }

  func loadMyProfile() async {
    guard let supabase else { return }
    profileLoadError = nil
    do {
      myProfile = try await supabase.fetchMyProfile()
      await refreshOrgContext()
      await reconcileOrganizationDirectoryNames()
      if myProfile?.isPlayer == true {
        if AppFlags.bypassAccessCheck {
          myEntitlement = nil
          needsAccess = false
        } else {
          await refreshEntitlement()
        }
      } else {
        myEntitlement = nil
        needsAccess = false
      }
    } catch {
      // If the profile row doesn't exist yet, insert it (safe: does not touch role) and retry.
      do {
        try await supabase.ensureMyProfileExists(fullName: nil)
        myProfile = try await supabase.fetchMyProfile()
        await refreshOrgContext()
        await reconcileOrganizationDirectoryNames()
        if myProfile?.isPlayer == true {
          if AppFlags.bypassAccessCheck {
            myEntitlement = nil
            needsAccess = false
          } else {
            await refreshEntitlement()
          }
        } else {
          myEntitlement = nil
          needsAccess = false
        }
      } catch {
        myProfile = nil
        profileLoadError = error.localizedDescription
        myEntitlement = nil
        needsAccess = false
        clearOrgContext()
        coachListenersStarted = false
      }
    }
  }

  private func reconcileOrganizationDirectoryNames() async {
    guard myProfile?.isCoach == true,
          let supabase,
          let orgId = activeOrgId else { return }
    // The authorized directory endpoint repairs legacy profiles whose names
    // were missing, allowing every roster surface to use a human name.
    _ = try? await supabase.adminListTeams(orgId: orgId)
  }

  func refreshOrgContext() async {
    guard let supabase else { return }
    let previousOrganizationId = activeOrgId
    let memberships: [SDOrgMembership]
    do {
      memberships = try await supabase.listMyOrgMemberships()
        .filter(\.isActive)
    } catch {
      // A failed authoritative membership read must fail closed and remove all
      // organization authority. Platform authorization is intentionally kept
      // independent and is refreshed through its server-authorized endpoint.
      if chatListenerStarted {
        await supabase.stopChatMessageListener()
      }
      activeOrgId = nil
      myOrgMemberships = []
      availableOrganizations = []
      activeOrgSettings = nil
      chatListenerStarted = false
      chatListenerOrganizationId = nil
      clearChatContext()
      return
    }

    // Commit the source of truth before loading optional directory/settings
    // presentation data. A branding or organization-list failure must not
    // erase a valid active owner/admin/coach membership.
    myOrgMemberships = memberships
    let membershipIds = Set(memberships.map(\.org_id))
    if let currentOrgId = activeOrgId, membershipIds.contains(currentOrgId) {
      // Keep the current organization when the user still has access.
    } else {
      activeOrgId = memberships.first?.org_id
    }

    do {
      let orgs = try await supabase.listOrgs()
      availableOrganizations = orgs
        .filter { membershipIds.contains($0.id) }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    } catch {
      // Keep any previously loaded matching names. Authorization remains based
      // solely on the membership rows committed above.
      availableOrganizations = availableOrganizations
        .filter { membershipIds.contains($0.id) }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    if let activeOrgId {
      do {
        activeOrgSettings = try await supabase.fetchOrgSettings(orgId: activeOrgId)
      } catch {
        activeOrgSettings = nil
      }
    } else {
      activeOrgSettings = nil
    }

    if previousOrganizationId != activeOrgId, chatListenerStarted {
      await supabase.stopChatMessageListener()
      chatListenerStarted = false
      chatListenerOrganizationId = nil
      clearChatContext()
      if activeOrgId != nil {
        await startChatListenerIfNeeded()
      }
    } else if activeOrgId == nil, chatListenerStarted {
      await supabase.stopChatMessageListener()
      chatListenerStarted = false
      chatListenerOrganizationId = nil
      clearChatContext()
    }
  }

  func switchActiveOrganization(to orgId: UUID) async {
    // Refresh first so a role/status change in another session cannot leave
    // authorization cached from the previously selected organization.
    await refreshOrgContext()
    guard OrganizationAuthorization.activeMembership(
      userId: myProfile?.id,
      orgId: orgId,
      memberships: myOrgMemberships
    ) != nil else {
      globalToastText = "You do not have access to that organization."
      return
    }
    guard activeOrgId != orgId else {
      // The refresh above still matters: it replaces stale role/status state
      // even when the requested organization is already selected.
      return
    }

    await supabase?.stopChatMessageListener()
    chatListenerStarted = false
    chatListenerOrganizationId = nil
    clearChatContext()
    activeOrgId = orgId
    do {
      activeOrgSettings = try await supabase?.fetchOrgSettings(orgId: orgId)
      let name = availableOrganizations.first(where: { $0.id == orgId })?.displayName ?? "Organization"
      globalToastText = "Switched to \(name)."
    } catch {
      activeOrgSettings = nil
      globalToastText = "Organization settings could not be loaded: \(error.localizedDescription)"
    }
    await startChatListenerIfNeeded()
  }

  func refreshEntitlement() async {
    if AppFlags.bypassAccessCheck {
      myEntitlement = nil
      needsAccess = false
      return
    }
    guard let supabase else { return }
    do {
      let session = try await supabase.client.auth.session
      let uid = session.user.id
      myEntitlement = try await supabase.fetchAccessEntitlement(userId: uid)
      needsAccess = (myEntitlement?.is_active != true)
    } catch {
      myEntitlement = nil
      needsAccess = true
    }
  }

  func refreshOnboarding() async {
    // MultiOrg no longer blocks accounts behind a questionnaire. Keep this
    // compatibility entry point so older call sites remain harmless.
    myOnboarding = nil
    needsOnboarding = false
    showOnboardingEditor = false
  }

  func signIn(email: String, password: String) async {
    authError = nil
    profileLoadError = nil
    guard let supabase else {
      authError = "Supabase not configured."
      return
    }
    do {
      try await supabase.signIn(email: email, password: password)
      await loadMyProfile()
      guard myProfile != nil else {
        throw LoginBootstrapError.profileUnavailable
      }
      isAuthenticated = true
      startLiveUpdates()
      if myProfile?.isPlayer == true {
        if AppFlags.bypassAccessCheck {
          myEntitlement = nil
          needsAccess = false
        } else {
          await refreshEntitlement()
        }
        await refreshOnboarding()
      } else {
        myOnboarding = nil
        needsOnboarding = false
        myEntitlement = nil
        needsAccess = false
      }
    } catch {
      // If the user typed a configured legacy username, try the migration bridge.
      // This migrates the legacy Shiny `public.users` row into Supabase Auth on first successful login.
      let lower = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if lower.hasSuffix("@\(DHDAppConfig.legacyEmailDomain.lowercased())"), let username = lower.split(separator: "@").first.map(String.init), !username.isEmpty {
        await legacySignIn(username: username, password: password)
        return
      }
      authError = error.localizedDescription
      isAuthenticated = false
      myProfile = nil
      myOnboarding = nil
      needsOnboarding = false
      clearOrgContext()
      coachListenersStarted = false
    }
  }

  func signIn(orgSlug: String, identifier: String, password: String) async {
    authError = nil
    profileLoadError = nil
    guard let supabase else {
      authError = "Supabase not configured."
      return
    }
    do {
      let normalizedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if normalizedIdentifier.contains("@") {
        // Email identifies the user globally. Authenticate first, then resolve
        // the organizations that account actually belongs to. This prevents a
        // valid coach login from failing just because the public picker was
        // initially pointing at a different organization.
        try await supabase.signIn(email: normalizedIdentifier, password: password)
      } else {
        // Usernames are organization-scoped and must use the selected org.
        let resp = try await supabase.orgLogin(
          orgSlug: orgSlug,
          identifier: normalizedIdentifier,
          password: password
        )
        try await supabase.installSession(accessToken: resp.access_token, refreshToken: resp.refresh_token)
        activeOrgId = resp.active_org_id
      }
      await loadMyProfile()
      guard myProfile != nil else {
        throw LoginBootstrapError.profileUnavailable
      }

      // Honor the selected organization when the authenticated account is a
      // member; otherwise retain the first real active membership selected by
      // refreshOrgContext().
      if let selected = availableOrganizations.first(where: {
        $0.slug.caseInsensitiveCompare(orgSlug) == .orderedSame
      }), myOrgMemberships.contains(where: { $0.org_id == selected.id }) {
        activeOrgId = selected.id
        activeOrgSettings = try await supabase.fetchOrgSettings(orgId: selected.id)
      }
      isAuthenticated = true
      startLiveUpdates()
      if myProfile?.isPlayer == true {
        if AppFlags.bypassAccessCheck {
          myEntitlement = nil
          needsAccess = false
        } else {
          await refreshEntitlement()
        }
        await refreshOnboarding()
      } else {
        myOnboarding = nil
        needsOnboarding = false
        myEntitlement = nil
        needsAccess = false
      }
    } catch {
      await clearFailedLogin(with: userFacingLoginMessage(for: error))
    }
  }

  private enum LoginBootstrapError: LocalizedError {
    case profileUnavailable

    var errorDescription: String? {
      switch self {
      case .profileUnavailable: return "Profile could not be loaded."
      }
    }
  }

  private func clearFailedLogin(with message: String) async {
    if let supabase {
      try? await supabase.signOut()
    }
    isAuthenticated = false
    myProfile = nil
    myOnboarding = nil
    needsOnboarding = false
    myEntitlement = nil
    needsAccess = false
    clearOrgContext()
    coachListenersStarted = false
    chatListenerStarted = false
    chatListenerOrganizationId = nil
    clearChatContext()
    UserDefaults.standard.removeObject(forKey: pendingPushNotificationKey)
    profileLoadError = nil
    authError = message
  }

  private func userFacingLoginMessage(for error: Error) -> String {
    let message = error.localizedDescription.lowercased()
    if message.contains("invalid_login")
      || message.contains("invalid credentials")
      || message.contains("invalid email or password")
      || message.contains("401")
      || message.contains("auth session missing")
      || message.contains("profile could not be loaded") {
      return "Login credentials are incorrect."
    }
    return "We couldn't sign you in right now. Check your connection and try again."
  }

  /// Notifications and realtime keep the app current, but never belong on the
  /// blocking path between a valid login and the first usable screen.
  private func startLiveUpdates() {
    Task { [weak self] in
      guard let self else { return }
      await self.refreshPlatformAdminStatus()
      await self.startCoachListenersIfNeeded()
      await self.startChatListenerIfNeeded()
    }
  }

  @discardableResult
  func refreshPlatformAdminStatus() async -> Bool {
    guard let supabase, isAuthenticated else {
      isPlatformAdmin = false
      return false
    }
    do {
      try await supabase.verifyPlatformAdminAccess()
      isPlatformAdmin = true
      return true
    } catch {
      isPlatformAdmin = false
      return false
    }
  }

  func resetPassword(email: String) async {
    authError = nil
    guard let supabase else {
      authError = "Supabase not configured."
      return
    }
    do {
      try await supabase.client.auth.resetPasswordForEmail(email)
      authError = "Password reset email sent (check spam)."
    } catch {
      authError = error.localizedDescription
    }
  }

  func signUp(
    orgSlug: String,
    username: String,
    email: String,
    password: String,
    fullName: String?,
    accountType: String,
    parentCode: String?,
    relationship: String?,
    coachCode: String?
  ) async {
    authError = nil
    profileLoadError = nil
    guard let supabase else {
      authError = "Supabase not configured."
      return
    }
    do {
      struct CreateAccountResponse: Decodable {
        let access_token: String
        let refresh_token: String
      }

      // Create the account server-side (Edge Function) so username-style accounts don't get stuck on email confirmation.
      let resp: CreateAccountResponse = try await supabase.client.functions.invoke(
        "create_account",
        options: FunctionInvokeOptions(
          body: [
            "org_slug": orgSlug,
            "username": username,
            "email": email,
            "password": password,
            "full_name": fullName ?? "",
            "account_type": accountType,
            "parent_code": parentCode ?? "",
            "relationship": relationship ?? "",
            "coach_code": coachCode ?? "",
          ]
        )
      )
      try await supabase.client.auth.setSession(accessToken: resp.access_token, refreshToken: resp.refresh_token)
      isAuthenticated = true
      await loadMyProfile()
      if myProfile?.isPlayer == true {
        await refreshOnboarding()
      } else {
        myOnboarding = nil
        needsOnboarding = false
      }
    } catch {
      let message = error.localizedDescription
      authError = message.localizedCaseInsensitiveContains("404")
        ? "The selected organization could not be found. Refresh the organization list and try again."
        : message
      isAuthenticated = false
      myProfile = nil
      myOnboarding = nil
      needsOnboarding = false
      clearOrgContext()
    }
  }

  struct LegacyLoginResponse: Decodable {
    let access_token: String
    let refresh_token: String
  }

  func legacySignIn(username: String, password: String) async {
    authError = nil
    profileLoadError = nil
    guard let supabase else {
      authError = "Supabase not configured."
      return
    }
    do {
      let resp: LegacyLoginResponse = try await supabase.client.functions.invoke(
        "legacy_login",
        options: FunctionInvokeOptions(
          body: ["username": username, "password": password]
        )
      )
      try await supabase.client.auth.setSession(accessToken: resp.access_token, refreshToken: resp.refresh_token)
      isAuthenticated = true
      await loadMyProfile()
      if myProfile?.isPlayer == true {
        if AppFlags.bypassAccessCheck {
          myEntitlement = nil
          needsAccess = false
        } else {
          await refreshEntitlement()
        }
        await refreshOnboarding()
      } else {
        myOnboarding = nil
        needsOnboarding = false
        myEntitlement = nil
        needsAccess = false
      }
    } catch let err as FunctionsError {
      switch err {
      case .relayError:
        authError = err.localizedDescription
      case .httpError(let code, let data):
        struct FnErr: Decodable {
          let error: String?
          let message: String?
          let reason: String?
        }
        let decoded = try? JSONDecoder().decode(FnErr.self, from: data)
        let parts = [
          decoded?.error,
          decoded?.message,
          decoded?.reason
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if parts.isEmpty {
          authError = "Legacy sign-in failed (\(code))."
        } else {
          authError = "Legacy sign-in failed (\(code)): " + parts.joined(separator: " — ")
        }
      }
      isAuthenticated = false
      myProfile = nil
      myOnboarding = nil
      needsOnboarding = false
      myEntitlement = nil
      needsAccess = false
      clearOrgContext()
    } catch {
      authError = error.localizedDescription
      isAuthenticated = false
      myProfile = nil
      myOnboarding = nil
      needsOnboarding = false
      myEntitlement = nil
      needsAccess = false
      clearOrgContext()
    }
  }

  func signInWithApple(idToken: String, nonce: String, fullName: String?) async {
    authError = nil
    profileLoadError = nil
    guard let supabase else {
      authError = "Supabase not configured."
      return
    }
    do {
      let creds = OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
      _ = try await supabase.client.auth.signInWithIdToken(credentials: creds)
      // Create/update profile (player default).
      try? await supabase.ensureMyProfileExists(fullName: fullName)
      await loadMyProfile()
      guard myProfile != nil else {
        throw LoginBootstrapError.profileUnavailable
      }
      isAuthenticated = true
      startLiveUpdates()
      if myProfile?.isPlayer == true {
        if AppFlags.bypassAccessCheck {
          myEntitlement = nil
          needsAccess = false
        } else {
          await refreshEntitlement()
        }
        await refreshOnboarding()
      } else {
        myOnboarding = nil
        needsOnboarding = false
        myEntitlement = nil
        needsAccess = false
      }
    } catch {
      authError = error.localizedDescription
      isAuthenticated = false
      myProfile = nil
      myOnboarding = nil
      needsOnboarding = false
      myEntitlement = nil
      needsAccess = false
    }
  }

  func signOut() async {
    authError = nil
    profileLoadError = nil
    guard let supabase else { return }
    do {
      await supabase.stopFacilityBookingRequestListener()
      await supabase.stopChatMessageListener()
      await pushNotifications.detachBeforeSignOut()
      try await supabase.signOut()
    } catch {
      authError = error.localizedDescription
    }
    isAuthenticated = false
    myProfile = nil
    myOnboarding = nil
    needsOnboarding = false
    myEntitlement = nil
    needsAccess = false
    showOnboardingEditor = false
    globalToastText = nil
    clearOrgContext()
    coachListenersStarted = false
    chatListenerStarted = false
    chatListenerOrganizationId = nil
    UserDefaults.standard.removeObject(forKey: pendingPushNotificationKey)
  }

  func configurePushNotifications() async {
    if isAuthenticated {
      await pushNotifications.configure(actorId: myProfile?.id, service: supabase)
    } else {
      await pushNotifications.configure(actorId: nil, service: nil)
    }
    guard isAuthenticated,
          let raw = UserDefaults.standard.string(forKey: pendingPushNotificationKey),
          let id = UUID(uuidString: raw) else { return }
    await openRemoteNotification(id)
  }

  private func openRemoteNotification(_ notificationId: UUID) async {
    guard isAuthenticated, let supabase else {
      UserDefaults.standard.set(
        notificationId.uuidString.lowercased(), forKey: pendingPushNotificationKey
      )
      return
    }
    do {
      // The push payload contributes only an opaque identifier. The backend
      // performs recipient ownership checks before any route is accepted.
      let owned = try await supabase.getNotification(notificationId: notificationId)
      UserDefaults.standard.removeObject(forKey: pendingPushNotificationKey)
      await openNotification(owned, markNonChatRead: true)
    } catch {
      UserDefaults.standard.removeObject(forKey: pendingPushNotificationKey)
      globalToastText = "That notification is no longer available for this account."
    }
  }

  func openNotification(
    _ notification: AppNotification,
    markNonChatRead: Bool
  ) async {
    if case .chatConversation(let conversationId, let messageId) =
      NotificationRouter.destination(for: notification) {
      await openChatNotification(
        notification: notification,
        conversationId: conversationId,
        messageId: messageId
      )
      return
    }

    if notification.category == .messageReceived {
      globalToastText = "That conversation link is invalid or no longer available."
      return
    }

    if markNonChatRead {
      do {
        requestedNotification = try await supabase?.markNotificationRead(
          notificationId: notification.id
        ) ?? notification
      } catch {
        globalToastText = "That notification is no longer available for this account."
      }
    } else {
      requestedNotification = notification
    }
  }

  private func openChatNotification(
    notification: AppNotification,
    conversationId: UUID,
    messageId: UUID
  ) async {
    guard let supabase else { return }
    if activeOrgId != notification.organizationId {
      await switchActiveOrganization(to: notification.organizationId)
    }
    guard activeOrgId == notification.organizationId else {
      globalToastText = "You no longer have access to that conversation's organization."
      return
    }
    do {
      _ = try await supabase.chatChannel(
        channelId: conversationId,
        organizationId: notification.organizationId
      )
      if activeChatChannelId == conversationId {
        let result = try await supabase.markChatConversationRead(
          channelId: conversationId,
          throughMessageId: messageId
        )
        recordChatRead(result)
      } else if requestedChatChannelId != conversationId {
        requestedChatChannelId = conversationId
      }
    } catch {
      requestedChatChannelId = nil
      globalToastText = "That conversation is no longer available for this account."
    }
  }

  func shouldPresentRemoteNotification(_ notificationId: UUID) async -> Bool {
    guard isAuthenticated, let supabase else { return true }
    do {
      let notification = try await supabase.getNotification(notificationId: notificationId)
      guard case .chatConversation(let conversationId, let messageId) =
        NotificationRouter.destination(for: notification) else { return true }
      guard !ChatForegroundPresentationPolicy.shouldPresent(
        notificationOrganizationId: notification.organizationId,
        notificationConversationId: conversationId,
        activeOrganizationId: activeOrgId,
        activeConversationId: activeChatChannelId
      ) else { return true }
      let result = try await supabase.markChatConversationRead(
        channelId: conversationId,
        throughMessageId: messageId
      )
      recordChatRead(result)
      return false
    } catch {
      // Failure to resolve an opaque reference must not suppress unrelated
      // foreground notifications globally.
      return true
    }
  }

  func promoteMeToCoach() async {
    authError = nil
    guard let supabase else {
      authError = "Supabase not configured."
      return
    }
    struct Resp: Decodable { let ok: Bool? }
    do {
      let _: Resp = try await supabase.client.functions.invoke("promote_me")
      await loadMyProfile()
    } catch {
      authError = error.localizedDescription
    }
  }

  // MARK: - Coach notifications (facility booking requests)

  private func startCoachListenersIfNeeded() async {
    guard let supabase else { return }
    guard myProfile?.isCoach == true else {
      if coachListenersStarted {
        await supabase.stopFacilityBookingRequestListener()
      }
      coachListenersStarted = false
      return
    }
    if coachListenersStarted { return }
    coachListenersStarted = true

    await requestNotificationPermissionIfNeeded()

    do {
      try await supabase.startFacilityBookingRequestListener { [weak self] req in
        Task { @MainActor in
          self?.handleNewFacilityBookingRequest(req)
        }
      }
    } catch {
      globalToastText = "Facility request notifications unavailable: \(error.localizedDescription)"
    }
  }

  // MARK: - Chat live updates (all roles)

  private func startChatListenerIfNeeded() async {
    guard let supabase else { return }
    guard isAuthenticated else { return }
    guard let organizationId = activeOrgId else { return }
    if chatListenerStarted, chatListenerOrganizationId == organizationId { return }
    if chatListenerStarted {
      await supabase.stopChatMessageListener()
      chatListenerStarted = false
      chatListenerOrganizationId = nil
    }
    chatListenerStarted = true
    chatListenerOrganizationId = organizationId

    await requestNotificationPermissionIfNeeded()

    do {
      try await supabase.startChatMessageListener(organizationId: organizationId) { [weak self] ins in
        Task { @MainActor in
          guard self?.activeOrgId == ins.organizationId,
                self?.chatListenerOrganizationId == ins.organizationId else { return }
          self?.chatLastInsert = ins
        }
      }
    } catch {
      chatListenerStarted = false
      chatListenerOrganizationId = nil
      // Best-effort. Chat still works with manual refresh.
      globalToastText = "Chat live updates unavailable: \(error.localizedDescription)"
    }
  }

  private func requestNotificationPermissionIfNeeded() async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    if settings.authorizationStatus == .notDetermined {
      _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
  }

  /// Exposed for Account UI: prompts for notification permission if needed.
  func requestCoachNotificationPermission() async {
    await requestNotificationPermissionIfNeeded()
  }

  func setActiveChatChannel(_ channelId: UUID?) {
    activeChatChannelId = channelId
  }

  func clearActiveChatChannelIfCurrent(_ channelId: UUID) {
    if activeChatChannelId == channelId {
      activeChatChannelId = nil
    }
  }

  func recordChatRead(_ result: SDChatReadResult) {
    guard result.organizationId == activeOrgId else { return }
    chatReadUpdate = ChatReadUpdate(
      organizationId: result.organizationId,
      conversationId: result.conversationId,
      throughMessageId: result.throughMessageId,
      lastReadAt: result.lastReadAt,
      lastReadMessageId: result.lastReadMessageId
    )
    if result.notificationsMarkedRead > 0 {
      NotificationCenter.default.post(name: .dhdNotificationStateChanged, object: nil)
    }
  }

  private func handleNewFacilityBookingRequest(_ req: SupabaseService.FacilityBookingRequest) {
    globalToastText = "New booking request received."

    let timeFmt = DateFormatter()
    timeFmt.dateStyle = .none
    timeFmt.timeStyle = .short
    let body = "\(req.activityType) • \(timeFmt.string(from: req.startAt))–\(timeFmt.string(from: req.endAt))"

    let content = UNMutableNotificationContent()
    content.title = "New cage booking request"
    content.body = body
    content.sound = .default

    // Fire immediately (in-app, while running). If notifications are disabled, toast still shows.
    let request = UNNotificationRequest(
      identifier: "sd_facility_booking_request_\(req.bookingId.uuidString)",
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request)
  }

}
