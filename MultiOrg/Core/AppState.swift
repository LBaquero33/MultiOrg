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

  /// DEV ONLY: show entitlement test buttons in Account → Subscription/Access.
  ///
  /// This does not involve Stripe or any monetary transaction; it calls the
  /// `entitlement_test` Edge Function (coach-only).
  ///
  /// Set in `Configs/Secrets.xcconfig`:
  /// `DHD_ENABLE_ENTITLEMENT_TEST = 1`
  static var enableEntitlementTestUI: Bool {
    #if !DEBUG
    return false
    #else
    let rawAny = Bundle.main.object(forInfoDictionaryKey: "DHD_ENABLE_ENTITLEMENT_TEST")
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
  @Published var requestedChatChannelId: UUID?

  private(set) var supabase: SupabaseService?
  private var coachListenersStarted = false
  private var chatListenerStarted = false
  private var activeChatChannelId: UUID?
  private var notifiedChatMessageIds = Set<UUID>()

  init() {
    NotificationCenter.default.addObserver(
      forName: .dhdOpenChatChannel,
      object: nil,
      queue: .main
    ) { [weak self] note in
      guard let channelId = note.object as? UUID else { return }
      Task { @MainActor in self?.requestedChatChannelId = channelId }
    }
  }

  var activeOrgMembership: SDOrgMembership? {
    guard let activeOrgId else { return nil }
    return myOrgMemberships.first { $0.org_id == activeOrgId }
  }

  var canAdminActiveOrg: Bool {
    activeOrgMembership?.isStaff == true || myProfile?.isCoach == true
  }

  var canStaffActiveOrg: Bool {
    activeOrgMembership?.isStaff == true || myProfile?.isCoach == true
  }

  private func clearOrgContext() {
    activeOrgId = nil
    myOrgMemberships = []
    availableOrganizations = []
    activeOrgSettings = nil
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
      isAuthenticated = true
      await loadMyProfile()
      await startCoachListenersIfNeeded()
      await startChatListenerIfNeeded()
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
      await startCoachListenersIfNeeded()
      await startChatListenerIfNeeded()
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
        await startCoachListenersIfNeeded()
        await startChatListenerIfNeeded()
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

  func refreshOrgContext() async {
    guard let supabase else { return }
    do {
      let memberships = try await supabase.listMyOrgMemberships()
      myOrgMemberships = memberships
      let membershipIds = Set(memberships.map(\.org_id))
      let orgs = try await supabase.listOrgs()
      availableOrganizations = orgs
        .filter { membershipIds.contains($0.id) }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

      if let currentOrgId = activeOrgId, membershipIds.contains(currentOrgId) {
        // Keep the current organization when the user still has access.
      } else {
        activeOrgId = availableOrganizations.first?.id ?? memberships.first?.org_id
      }
      if let activeOrgId {
        activeOrgSettings = try await supabase.fetchOrgSettings(orgId: activeOrgId)
      } else {
        activeOrgSettings = nil
      }
    } catch {
      myOrgMemberships = []
      availableOrganizations = []
      activeOrgSettings = nil
    }
  }

  func switchActiveOrganization(to orgId: UUID) async {
    guard myOrgMemberships.contains(where: { $0.org_id == orgId }) else {
      globalToastText = "You do not have access to that organization."
      return
    }
    guard activeOrgId != orgId else { return }

    activeOrgId = orgId
    do {
      activeOrgSettings = try await supabase?.fetchOrgSettings(orgId: orgId)
      let name = availableOrganizations.first(where: { $0.id == orgId })?.displayName ?? "Organization"
      globalToastText = "Switched to \(name)."
    } catch {
      activeOrgSettings = nil
      globalToastText = "Organization settings could not be loaded: \(error.localizedDescription)"
    }
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
    guard let supabase else { return }
    do {
      let session = try await supabase.client.auth.session
      let uid = session.user.id
      myOnboarding = try await supabase.fetchOnboarding(playerId: uid)
      needsOnboarding = (myOnboarding?.completed_at == nil)
    } catch {
      myOnboarding = nil
      needsOnboarding = false
    }
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
      isAuthenticated = true
      await loadMyProfile()
      await startCoachListenersIfNeeded()
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

  func signIn(orgSlug: String, username: String, password: String) async {
    authError = nil
    profileLoadError = nil
    guard let supabase else {
      authError = "Supabase not configured."
      return
    }
    do {
      let resp = try await supabase.orgLogin(orgSlug: orgSlug, username: username, password: password)
      try await supabase.client.auth.setSession(accessToken: resp.access_token, refreshToken: resp.refresh_token)
      activeOrgId = resp.active_org_id

      isAuthenticated = true
      await loadMyProfile()
      await startCoachListenersIfNeeded()
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
      clearOrgContext()
      coachListenersStarted = false
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
      authError = error.localizedDescription
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
    if chatListenerStarted { return }
    chatListenerStarted = true

    await requestNotificationPermissionIfNeeded()

    do {
      try await supabase.startChatMessageListener { [weak self] ins in
        Task { @MainActor in
          self?.chatLastInsert = ins
          self?.handleChatMessageInsertForNotification(ins)
        }
      }
    } catch {
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

  private func handleChatMessageInsertForNotification(_ ins: SupabaseService.ChatMessageInsert) {
    guard isAuthenticated, ins.senderId != myProfile?.id, activeChatChannelId != ins.channelId else { return }
    guard notifiedChatMessageIds.insert(ins.messageId).inserted else { return }
    if notifiedChatMessageIds.count > 250 { notifiedChatMessageIds.removeAll(keepingCapacity: true) }

    Task { @MainActor in
      await requestNotificationPermissionIfNeeded()
      await scheduleChatNotification(for: ins)
    }
  }

  private func scheduleChatNotification(for ins: SupabaseService.ChatMessageInsert) async {
    guard let supabase else { return }
    do {
      let channels = try await supabase.listChatChannels()
      guard let channel = channels.first(where: { $0.id == ins.channelId }) else { return }
      var senderName = "New message"
      if let senderId = ins.senderId {
        senderName = try await supabase.listProfiles(ids: [senderId]).first?.displayName ?? senderName
      }
      let title: String
      if channel.isGroup { title = "\(senderName) in \(channel.title ?? "Group chat")" }
      else if channel.isAnnouncement { title = channel.title ?? "Announcement" }
      else { title = senderName }
      let body = ins.body.trimmingCharacters(in: .whitespacesAndNewlines)
      globalToastText = "\(title): \(body.isEmpty ? "Sent you a message." : String(body.prefix(180)))"

      let settings = await UNUserNotificationCenter.current().notificationSettings()
      guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body.isEmpty ? "Sent you a message." : String(body.prefix(180))
      content.sound = .default
      content.categoryIdentifier = "chat_message"
      content.threadIdentifier = "chat_\(ins.channelId.uuidString)"
      content.userInfo = ["channel_id": ins.channelId.uuidString]
      try await UNUserNotificationCenter.current().add(UNNotificationRequest(
        identifier: "sd_chat_message_\(ins.messageId.uuidString)", content: content, trigger: nil
      ))
    } catch {
      // Realtime chat remains functional even if a local alert cannot be scheduled.
    }
  }
}
