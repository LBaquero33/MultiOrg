import SwiftUI
import PhotosUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

import UserNotifications
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private struct PushNotificationSettingsCard: View {
  @ObservedObject var manager: PushNotificationManager

  var body: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Notifications")
        HPStatTile(label: "System permission", value: permissionLabel, systemImage: "bell")
        VStack(alignment: .leading, spacing: 4) {
          Label("This device", systemImage: "iphone")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
          Text(registrationLabel)
            .font(HP.Font.callout.weight(.semibold))
            .foregroundStyle(HP.Color.text)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        if manager.canRequestPermission {
          HPButton(
            title: "Enable Notifications",
            systemImage: "bell",
            variant: .secondary,
            size: .md,
            fullWidth: true,
            action: { Task { await manager.requestPermission() } }
          )
        }
        if manager.authorizationStatus == .denied {
          HPButton(
            title: "Open System Settings",
            systemImage: "gear",
            variant: .secondary,
            size: .md,
            fullWidth: true,
            action: { manager.openSystemSettings() }
          )
        }
      }
    }
  }

  private var permissionLabel: String {
    switch manager.authorizationStatus {
    case .authorized: "Enabled"
    case .denied: "Denied"
    case .notDetermined: "Not set"
    case .provisional: "Provisional"
    case .ephemeral: "Ephemeral"
    @unknown default: "Unknown"
    }
  }

  private var registrationLabel: String {
    switch manager.registrationState {
    case .idle: "Not registered"
    case .waitingForToken: "Waiting for Apple"
    case .registering: "Registering…"
    case .registered: "Registered"
    case .failed(let message): message
    }
  }
}

private struct AccountProfileAvatar: View {
  let url: URL?
  let name: String
  let fallbackInitials: String
  let size: HPAvatarSize

  var body: some View {
    Group {
      if let url {
        AsyncImage(url: url) { phase in
          switch phase {
          case .empty:
            placeholder
          case .success(let image):
            image
              .resizable()
              .scaledToFill()
          case .failure:
            placeholder
          @unknown default:
            placeholder
          }
        }
      } else {
        placeholder
      }
    }
    .frame(width: size.dim, height: size.dim)
    .clipShape(Circle())
    .overlay(
      Circle()
        .strokeBorder(HP.Color.borderStrong, lineWidth: 1)
        .allowsHitTesting(false)
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(name == "Signed in" ? "Account profile photo" : "\(name) profile photo")
  }

  private var placeholder: some View {
    HPAvatar(
      name: name == "Signed in" ? fallbackInitials : name,
      size: size
    )
  }
}

/// Unified Account / Profile screen (role-aware).
/// - Profile: avatar + full bio fields
/// - Parents/Family: request/approve parent linking
/// - Subscription/Access: entitlement status (read-only)
/// - Security: password reset + sign out
struct AccountView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase

  @State private var details: SupabaseService.SDProfileDetails?
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var toastText: String?
  @State private var isApplyingProfile = false
  @State private var isSavingProfile = false
  @State private var profileSaveTask: Task<Void, Never>?

  @State private var myParentCode: String?
  @State private var paymentRequestState = SDPaymentRequestListState()
  @State private var isPaymentRequestLoading = false
  @State private var paymentRequestErrorText: String?
  @State private var paymentCheckoutState = SDPaymentCheckoutState.idle
  @State private var checkoutConfirmationRequest: SDPaymentRequest?

  // Editable fields
  @State private var fullName: String = ""
  @State private var phone: String = ""
  @State private var gradYear: String = ""
  @State private var primaryPosition: String = ""
  @State private var bats: String = "unknown"
  @State private var throwsHand: String = "unknown"
  @State private var school: String = ""
  @State private var team: String = ""
  @State private var heightIn: String = ""
  @State private var weightLb: String = ""
  @State private var notes: String = ""
  @State private var professionalTitle: String = ""
  @State private var professionalBio: String = ""
  @State private var specialties: String = ""
  @State private var website: String = ""
  @State private var yearsExperience: String = ""

  // Avatar
  @State private var avatarURL: URL?
  @State private var pendingAvatarJPEG: Data?

#if canImport(UIKit)
  @State private var photoItem: PhotosPickerItem?
#else
  @State private var showFilePicker = false
  @State private var macPickedURL: URL?
#endif

  var body: some View {
    accountPage
      .sheet(item: $checkoutConfirmationRequest) { request in
        PaymentCheckoutConfirmationSheet(
          request: request,
          organizationName: activePaymentOrganizationName,
          playerName: request.player_name ?? appState.myProfile?.displayName ?? "Player",
          onConfirm: { Task { await openPaymentRequestCheckout(for: request) } }
        )
      }
      .task(id: appState.activeOrgId) { await reload() }
      .task(id: paymentRequestLoadKey) { await reloadPlayerPaymentRequests() }
      .onChange(of: scenePhase) { _, next in
        guard next == .active, paymentCheckoutState.shouldRefreshWhenActive else { return }
        Task { await reloadPlayerPaymentRequests() }
      }
      .onChange(of: profileAutosaveKey) { _, _ in scheduleProfileAutosave() }
  }

  private var profileAutosaveKey: String {
    [
      fullName, phone, gradYear, primaryPosition, bats, throwsHand, school, team,
      heightIn, weightLb, notes, professionalTitle, professionalBio, specialties,
      website, yearsExperience,
    ].joined(separator: "\u{1F}")
  }

  private var accountPage: some View {
    HPSettingsScreenLayout { _ in
      HPWorkspaceHeader(
        title,
        orgLabel: activeOrganizationName,
        context: subtitle
      )
    } sections: { context in
      VStack(alignment: .leading, spacing: HP.Space.md) {
        identityCard
        if isLoading {
          HPCard(style: .flat) {
            HPLoadingState(text: "Loading account…")
          }
        }

        organizationCard
        profileCard(context: context)
        familyCard
        accessCard
        if isActiveOrganizationPlayer { paymentRequestsCard(context: context) }
        PushNotificationSettingsCard(manager: appState.pushNotifications)
        securityCard(context: context)

        if let toastText, !toastText.isEmpty {
          HPToast(text: toastText)
            .transition(.opacity)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } destructiveAction: { _ in
      signOutAction
    }
    .navigationTitle("Account")
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
  }

  private var title: String {
    if let p = appState.myProfile {
      if p.isCoach { return "Coach Account" }
      if p.isParent { return "Parent Account" }
      return "Player Account"
    }
    return "Account"
  }

  private var subtitle: String {
    appState.myProfile?.displayName ?? "Signed in"
  }

  private var initials: String {
    let s = (appState.myProfile?.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if s.isEmpty { return "?" }
    let parts = s.split(separator: " ").map { String($0) }
    if parts.count >= 2 { return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased() }
    return String(s.prefix(2)).uppercased()
  }

  private var identityCard: some View {
    HPCard {
      HStack(alignment: .center, spacing: HP.Space.md) {
        AccountProfileAvatar(
          url: avatarURL,
          name: subtitle,
          fallbackInitials: initials,
          size: .lg
        )
        VStack(alignment: .leading, spacing: 2) {
          Text(subtitle)
            .font(HP.Font.headline)
            .foregroundStyle(HP.Color.text)
            .fixedSize(horizontal: false, vertical: true)
          Text(title)
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }
    }
  }

  @ViewBuilder
  private var organizationCard: some View {
    if !appState.availableOrganizations.isEmpty {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Organization")
          HStack(spacing: HP.Space.sm) {
            Group {
              if let path = appState.activeOrgSettings?.logo_path,
                 let url = appState.supabase?.publicOrganizationLogoURL(path: path) {
                AsyncImage(url: url) { image in
                  image.resizable().scaledToFill()
                } placeholder: {
                  ProgressView()
                }
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous))
              } else {
                Image(systemName: "building.2.fill")
                  .font(.title3)
                  .foregroundStyle(HP.Color.primary)
                  .frame(width: 34, height: 34)
              }
            }
            VStack(alignment: .leading, spacing: 2) {
              Text("Active organization")
                .font(HP.Font.caption)
                .foregroundStyle(HP.Color.textMuted)
              Text(activeOrganizationName)
                .font(HP.Font.callout.weight(.semibold))
                .foregroundStyle(HP.Color.text)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
          }
          if appState.availableOrganizations.count > 1 {
            Menu {
              ForEach(appState.availableOrganizations) { organization in
                Button {
                  Task { await appState.switchActiveOrganization(to: organization.id) }
                } label: {
                  Label(
                    organization.displayName,
                    systemImage: organization.id == appState.activeOrgId ? "checkmark" : "building.2"
                  )
                }
              }
            } label: {
              Label("Switch", systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(HPButtonStyle(variant: .secondary, size: .md, fullWidth: true))
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
          }
        }
      }
    }
  }

  private var activeOrganizationName: String {
    if let active = appState.availableOrganizations.first(where: { $0.id == appState.activeOrgId }) {
      return active.displayName
    }
    return appState.activeOrgSettings?.display_name ?? "Organization"
  }

  private func profileCard(context: HPScreenLayoutContext) -> some View {
    let avatarLayout = context.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
      : AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.md))

    return HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("Profile") {
          HPButton(
            title: "Refresh",
            systemImage: "arrow.clockwise",
            variant: .secondary,
            size: .sm,
            fullWidth: context.isAccessibilitySize,
            action: { Task { await reload() } }
          )
        }

        avatarLayout {
          AccountProfileAvatar(
            url: avatarURL,
            name: subtitle,
            fallbackInitials: initials,
            size: .lg
          )
          avatarChangeControls(context: context)
          if !context.isAccessibilitySize {
            Spacer(minLength: 0)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if appState.myProfile?.isCoach == true {
          coachProfileFields
        } else {
          athleteProfileFields
        }

        VStack(alignment: .leading, spacing: HP.Space.xs) {
          HPButton(
            title: "Save now",
            systemImage: "checkmark.circle.fill",
            variant: .primary,
            size: .md,
            isLoading: isLoading || isSavingProfile,
            fullWidth: context.isAccessibilitySize,
            action: { Task { await saveProfile(isAutomatic: false) } }
          )
          .disabled(isLoading || isSavingProfile)
          if isSavingProfile {
            HStack(spacing: 6) {
              ProgressView().controlSize(.small)
              Text("Saving…")
            }
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
          } else {
            Text("Saves automatically")
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.textMuted)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func avatarChangeControls(context: HPScreenLayoutContext) -> some View {
    VStack(alignment: .leading, spacing: HP.Space.xs) {
#if canImport(UIKit)
      PhotosPicker(selection: $photoItem, matching: .images) {
        Label("Change photo", systemImage: "photo")
      }
      .buttonStyle(
        HPButtonStyle(
          variant: .secondary,
          size: .sm,
          fullWidth: context.isAccessibilitySize
        )
      )
      .frame(maxWidth: context.isAccessibilitySize ? .infinity : nil, minHeight: 44)
      .contentShape(Rectangle())
      .onChange(of: photoItem) { _, newValue in
        guard let newValue else { return }
        Task { await loadPhotoPickerItem(newValue) }
      }
#else
      Button {
        showFilePicker = true
      } label: {
        Label("Change photo", systemImage: "photo")
      }
      .buttonStyle(
        HPButtonStyle(
          variant: .secondary,
          size: .sm,
          fullWidth: context.isAccessibilitySize
        )
      )
      .frame(maxWidth: context.isAccessibilitySize ? .infinity : nil, minHeight: 44)
      .contentShape(Rectangle())
      .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.image]) { res in
        switch res {
        case .success(let url):
          macPickedURL = url
          Task { await loadMacImageURL(url) }
        case .failure(let err):
          errorText = err.localizedDescription
        }
      }
#endif
      if pendingAvatarJPEG != nil {
        Text("Photo selected • saving automatically")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var athleteProfileFields: some View {
    VStack(alignment: .leading, spacing: HP.Space.sm) {
      HPFormField(label: "Full name", text: $fullName, placeholder: "Full name")
      HPFormField(label: "Phone (optional)", text: $phone, placeholder: "Phone")
      HPFormField(label: "Grad year", text: $gradYear, placeholder: "Graduation year")
      HPFormField(label: "Primary position", text: $primaryPosition, placeholder: "Primary position")
      Picker("Bats", selection: $bats) {
        Text("R").tag("R")
        Text("L").tag("L")
        Text("S").tag("S")
        Text("Unknown").tag("unknown")
      }
      .pickerStyle(.menu)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(minHeight: 44)
      .contentShape(Rectangle())
      Picker("Throws", selection: $throwsHand) {
        Text("R").tag("R")
        Text("L").tag("L")
        Text("Unknown").tag("unknown")
      }
      .pickerStyle(.menu)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(minHeight: 44)
      .contentShape(Rectangle())
      HPFormField(label: "School", text: $school, placeholder: "School")
      HPFormField(label: "Team", text: $team, placeholder: "Team")
      HPFormField(label: "Height (in)", text: $heightIn, placeholder: "Height in inches")
      HPFormField(label: "Weight (lb)", text: $weightLb, placeholder: "Weight in pounds")
      HPFormField(label: "Notes", text: $notes, kind: .multiline, placeholder: "Notes")
    }
    .font(HP.Font.body)
    .foregroundStyle(HP.Color.text)
    .tint(HP.Color.accent)
  }

  private var coachProfileFields: some View {
    VStack(alignment: .leading, spacing: HP.Space.sm) {
      HPFormField(label: "Full name", text: $fullName, placeholder: "Full name")
      HPFormField(label: "Professional title", text: $professionalTitle, placeholder: "Professional title")
      HPFormField(label: "Phone (optional)", text: $phone, placeholder: "Phone")
      HPFormField(label: "Organization / school", text: $school, placeholder: "Organization or school")
      HPFormField(label: "Specialties", text: $specialties, placeholder: "Specialties")
      HPFormField(label: "Years coaching", text: $yearsExperience, placeholder: "Years coaching")
      HPFormField(label: "Website or profile link", text: $website, placeholder: "Website or profile link")
      HPFormField(label: "Professional bio", text: $professionalBio, kind: .multiline, placeholder: "Professional bio")
    }
  }

  private var familyCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Family / Parents")

        if appState.myProfile?.isCoach == true {
          CoachParentRequestsPanel()
            .environmentObject(appState)
        } else if appState.myProfile?.isPlayer == true {
          if let code = myParentCode, !code.isEmpty {
            VStack(alignment: .leading, spacing: HP.Space.xs) {
              Text("PARENT CODE")
                .font(HP.Font.eyebrow)
                .tracking(HP.Font.eyebrowTracking)
                .foregroundStyle(HP.Color.textMuted)
              VStack(alignment: .leading, spacing: HP.Space.xs) {
                Text(code)
                  .font(.system(.body, design: .monospaced))
                  .foregroundStyle(HP.Color.text)
                  .textSelection(.enabled)
                HPButton(
                  title: "Copy",
                  systemImage: "doc.on.doc",
                  variant: .secondary,
                  size: .sm,
                  fullWidth: true,
                  action: {
                    copyToPasteboard(code)
                    toast("Copied parent code.")
                  }
                )
              }
            }
            Text("Share this code with a parent/guardian so they can create a Parent account and link to you.")
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.textMuted)
              .fixedSize(horizontal: false, vertical: true)
          } else {
            Text("Parent code: —")
              .foregroundStyle(HP.Color.textMuted)
              .font(HP.Font.callout)
          }
          PlayerParentRequestsPanel()
            .environmentObject(appState)
        } else if appState.myProfile?.isParent == true {
          Text("Use the Children list to view linked players. Pending invites will appear automatically when available.")
            .foregroundStyle(HP.Color.textMuted)
            .font(HP.Font.callout)
            .fixedSize(horizontal: false, vertical: true)
        } else {
          Text("—")
            .foregroundStyle(HP.Color.textMuted)
        }
      }
    }
  }

  private var accessCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Subscription / Access")

        if appState.myProfile?.isPlayer == true {
          entitlementSummary(entitlement: appState.myEntitlement)
          Text("Access is managed by your organization. Contact an organization administrator if this status is incorrect.")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        } else if appState.myProfile?.isCoach == true {
          Text("Player access is managed individually from Players → Program. Organization owners and platform administrators can grant access or require payment.")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)

        } else if appState.myProfile?.isParent == true {
          Text("Player access and payment requirements are managed by the organization.")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        } else {
          Text("—")
            .foregroundStyle(HP.Color.textMuted)
        }
      }
    }
  }

  private var paymentRequestLoadKey: String {
    "\(appState.activeOrgAuthorizationKey):\(appState.myProfile?.id.uuidString ?? "none")"
  }

  private func paymentRequestsCard(context: HPScreenLayoutContext) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Payment Requests") {
          HStack(spacing: HP.Space.xs) {
            if isPaymentRequestLoading {
              ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Loading payment requests")
            }
            HPButton(
              title: "Refresh",
              systemImage: "arrow.clockwise",
              variant: .secondary,
              size: .sm,
              fullWidth: context.isAccessibilitySize,
              action: { Task { await reloadPlayerPaymentRequests() } }
            )
            .disabled(isPaymentRequestLoading)
          }
        }

        Text("Organization payment requests are separate from your Apple player subscription.")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)

        if let paymentRequestErrorText {
          VStack(alignment: .leading, spacing: HP.Space.xs) {
            Text(paymentRequestErrorText)
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.danger)
              .fixedSize(horizontal: false, vertical: true)
            HPButton(
              title: "Try Again",
              systemImage: "arrow.clockwise",
              variant: .secondary,
              size: .sm,
              fullWidth: context.isAccessibilitySize,
              action: { Task { await reloadPlayerPaymentRequests() } }
            )
          }
        } else if paymentRequestState.requests.isEmpty, !isPaymentRequestLoading {
          Text("No payment requests for this organization.")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
        } else {
          ForEach(paymentRequestState.requests) { request in
            PaymentRequestCard(
              request: request,
              organizationName: activePaymentOrganizationName,
              playerName: request.player_name ?? appState.myProfile?.displayName ?? "Player",
              context: .player,
              checkoutState: paymentCheckoutState,
              onPay: { checkoutConfirmationRequest = request }
            )
          }
        }
      }
    }
  }

  private func reloadPlayerPaymentRequests() async {
    paymentRequestErrorText = nil
    guard isActiveOrganizationPlayer,
          let playerId = appState.myProfile?.id,
          let orgId = appState.activeOrgId,
          let supabase = appState.supabase else {
      paymentRequestState.clear()
      paymentCheckoutState = .idle
      checkoutConfirmationRequest = nil
      return
    }
    if paymentRequestState.organizationId != orgId {
      paymentCheckoutState = .idle
      checkoutConfirmationRequest = nil
    }
    paymentRequestState.beginLoading(organizationId: orgId)
    isPaymentRequestLoading = true
    defer { isPaymentRequestLoading = false }
    do {
      let requests = try await supabase.listPaymentRequests(orgId: orgId, playerId: playerId)
      paymentRequestState.apply(requests, organizationId: orgId)
      paymentCheckoutState.reconcile(with: requests)
    } catch {
      guard paymentRequestState.organizationId == orgId else { return }
      paymentRequestErrorText = "Payment requests could not be loaded. \(error.localizedDescription)"
    }
  }

  private var isActiveOrganizationPlayer: Bool {
    appState.activeOrgMembership?.normalizedRole == "player"
  }

  private func openPaymentRequestCheckout(for request: SDPaymentRequest) async {
    guard let supabase = appState.supabase else { return }
    guard paymentCheckoutState.beginOpening(requestId: request.id) else { return }
    do {
      let response = try await supabase.createPaymentRequestCheckout(paymentRequestId: request.id)
      guard response.checkout.payment_request_id == request.id else {
        paymentCheckoutState.fail(
          requestId: request.id,
          message: "Checkout returned the wrong payment request. Refresh and try again."
        )
        return
      }
      let wasOpened: Bool = await withCheckedContinuation { continuation in
        openURL(response.checkout.url) { accepted in
          continuation.resume(returning: accepted)
        }
      }
      if !wasOpened {
        paymentCheckoutState.fail(
          requestId: request.id,
          message: "Stripe Checkout could not be opened in the system browser."
        )
      } else {
        paymentCheckoutState.browserOpened(requestId: request.id)
      }
    } catch {
      paymentCheckoutState.fail(requestId: request.id, message: error.localizedDescription)
    }
  }

  private var activePaymentOrganizationName: String {
    if let orgId = appState.activeOrgId,
       let organization = appState.availableOrganizations.first(where: { $0.id == orgId }) {
      return organization.displayName
    }
    return appState.activeOrgSettings?.display_name ?? "Organization"
  }

  private func displayPaymentRequestDate(_ value: String) -> String {
    let input = DateFormatter()
    input.locale = Locale(identifier: "en_US_POSIX")
    input.dateFormat = "yyyy-MM-dd"
    guard let date = input.date(from: value) else { return value }
    return date.formatted(date: .abbreviated, time: .omitted)
  }

  private func securityCard(context: HPScreenLayoutContext) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Security")
        HPButton(
          title: "Send password reset email",
          systemImage: "key",
          variant: .secondary,
          size: .md,
          fullWidth: context.isAccessibilitySize,
          action: { Task { await sendPasswordResetToMe() } }
        )
      }
    }
  }

  private var signOutAction: some View {
    HPButton(
      title: "Sign out",
      systemImage: "rectangle.portrait.and.arrow.right",
      variant: .destructive,
      size: .md,
      fullWidth: true,
      action: { Task { await appState.signOut() } }
    )
  }


  private func entitlementSummary(entitlement: SDAccessEntitlement?) -> some View {
    VStack(alignment: .leading, spacing: HP.Space.xs) {
      let active = entitlement?.is_active == true
      HStack {
        HPStatusBadge(text: active ? "Active" : "Inactive", kind: active ? .success : .danger)
        Spacer(minLength: 0)
      }
      if let end = entitlement?.current_period_end {
        HPStatTile(label: "Renews/Ends", value: end.formatted(date: .abbreviated, time: .omitted))
      }
      if let src = entitlement?.source, !src.isEmpty {
        HPStatTile(label: "Source", value: src)
      }
    }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      isApplyingProfile = true
      defer { isApplyingProfile = false }
      let d = try await supabase.fetchMyProfileDetails()
      details = d
      fullName = (d.full_name ?? "")
      phone = (d.phone ?? "")
      gradYear = d.grad_year.map(String.init) ?? ""
      primaryPosition = (d.primary_position ?? "")
      bats = (d.bats ?? "unknown")
      throwsHand = (d.throws_hand ?? "unknown")
      school = (d.school ?? "")
      team = (d.team ?? "")
      heightIn = d.height_in.map(String.init) ?? ""
      weightLb = d.weight_lb.map(String.init) ?? ""
      notes = (d.notes ?? "")
      professionalTitle = d.professional_title ?? ""
      professionalBio = d.bio ?? ""
      specialties = d.specialties ?? ""
      website = d.website ?? ""
      yearsExperience = d.years_experience.map(String.init) ?? ""

      pendingAvatarJPEG = nil
      if let p = d.avatar_path, let url = supabase.publicAvatarURL(path: p) {
        avatarURL = url
      } else {
        avatarURL = nil
      }

      if appState.myProfile?.isPlayer == true {
        myParentCode = try await supabase.fetchMyParentCode()
      } else {
        myParentCode = nil
      }

    } catch {
      errorText = error.localizedDescription
    }
  }

  private func copyToPasteboard(_ text: String) {
#if canImport(UIKit)
    UIPasteboard.general.string = text
#elseif canImport(AppKit)
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
#endif
  }

  private func scheduleProfileAutosave() {
    guard !isApplyingProfile, details != nil else { return }
    profileSaveTask?.cancel()
    profileSaveTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(650))
      guard !Task.isCancelled else { return }
      await saveProfile(isAutomatic: true)
    }
  }

  private func saveProfile(isAutomatic: Bool) async {
    guard let supabase = appState.supabase else { return }
    if isAutomatic { isSavingProfile = true } else { isLoading = true }
    defer {
      if isAutomatic { isSavingProfile = false } else { isLoading = false }
    }
    var avatarPath: String? = details?.avatar_path
    if let jpeg = pendingAvatarJPEG {
      do {
        avatarPath = try await supabase.uploadMyAvatarJPEG(jpeg)
      } catch {
        errorText = "Your profile photo could not be uploaded. Please try again. (avatar_upload_failed)"
        return
      }
    }

    let patch = SupabaseService.SDProfileDetailsPatch(
      full_name: cleanOrNil(fullName),
      avatar_path: avatarPath,
      phone: cleanOrNil(phone),
      grad_year: Int(cleanDigits(gradYear) ?? ""),
      primary_position: cleanOrNil(primaryPosition),
      bats: cleanOrNil(bats) ?? "unknown",
      throws_hand: cleanOrNil(throwsHand) ?? "unknown",
      school: cleanOrNil(school),
      team: cleanOrNil(team),
      height_in: Int(cleanDigits(heightIn) ?? ""),
      weight_lb: Int(cleanDigits(weightLb) ?? ""),
      notes: cleanOrNil(notes),
      professional_title: cleanOrNil(professionalTitle),
      bio: cleanOrNil(professionalBio),
      specialties: cleanOrNil(specialties),
      website: cleanOrNil(website),
      years_experience: Int(cleanDigits(yearsExperience) ?? "")
    )
    do {
      try await supabase.updateMyProfileDetails(patch)
    } catch {
      errorText = "Your profile details could not be saved. Please try again. (profile_update_failed)"
      return
    }
    pendingAvatarJPEG = nil
    if !isAutomatic {
      toast("Saved.")
      await appState.loadMyProfile()
      await reload()
    }
  }

  private func sendPasswordResetToMe() async {
    guard let supabase = appState.supabase else { return }
    do {
      let session = try await supabase.client.auth.session
      let email = session.user.email ?? ""
      if email.isEmpty {
        toast("No email found for this account.")
        return
      }
      await appState.resetPassword(email: email)
      toast(appState.authError ?? "Password reset email sent.")
    } catch {
      errorText = error.localizedDescription
    }
  }

#if canImport(UIKit)
  private func loadPhotoPickerItem(_ item: PhotosPickerItem) async {
    do {
      if let data = try await item.loadTransferable(type: Data.self),
         let jpeg = AvatarImageProcessor.squareJPEG(from: data, side: 512) {
        pendingAvatarJPEG = jpeg
        // Show immediate preview by decoding jpeg data locally.
        avatarURL = AvatarImageProcessor.localPreviewURL(for: jpeg)
        scheduleProfileAutosave()
      }
    } catch {
      errorText = error.localizedDescription
    }
  }
#else
  private func loadMacImageURL(_ url: URL) async {
    let isAccessing = url.startAccessingSecurityScopedResource()
    defer {
      if isAccessing {
        url.stopAccessingSecurityScopedResource()
      }
    }
    do {
      let data = try Data(contentsOf: url)
      if let jpeg = AvatarImageProcessor.squareJPEG(from: data, side: 512) {
        pendingAvatarJPEG = jpeg
        avatarURL = AvatarImageProcessor.localPreviewURL(for: jpeg)
        scheduleProfileAutosave()
      }
    } catch {
      errorText = error.localizedDescription
    }
  }
#endif

  private func toast(_ text: String) {
    withAnimation(.easeInOut(duration: 0.15)) {
      toastText = text
    }
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      withAnimation(.easeInOut(duration: 0.2)) { toastText = nil }
    }
  }

  private func cleanOrNil(_ s: String) -> String? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
  }

  private func cleanDigits(_ s: String) -> String? {
    let digits = s.filter { $0.isNumber }
    return digits.isEmpty ? nil : digits
  }
}

// MARK: - Avatar helpers

struct DHDAvatarView: View {
  let url: URL?
  let initials: String
  let size: CGFloat

  var body: some View {
    Group {
      if let url {
        AsyncImage(url: url) { phase in
          switch phase {
          case .empty:
            placeholder
          case .success(let image):
            image
              .resizable()
              .scaledToFill()
          case .failure:
            placeholder
          @unknown default:
            placeholder
          }
        }
      } else {
        placeholder
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .overlay(
      Circle()
        .strokeBorder(HP.Color.borderStrong, lineWidth: 1)
        .allowsHitTesting(false)
    )
  }

  private var placeholder: some View {
    ZStack {
      Circle().fill(HP.Color.primary.opacity(0.22))
      Text(initials)
        .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
        .foregroundStyle(HP.Color.primary)
    }
  }
}

enum AvatarImageProcessor {
  static func squareJPEG(from input: Data, side: Int) -> Data? {
#if canImport(UIKit)
    guard let ui = UIImage(data: input) else { return nil }
    let img = ui.fixOrientation()
    guard let cg = img.cgImage else { return nil }
    return renderSquareJPEG(from: cg, side: side)
#elseif canImport(AppKit)
    guard let ns = NSImage(data: input) else { return nil }
    guard let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    return renderSquareJPEG(from: cg, side: side)
#else
    return nil
#endif
  }

  private static func renderSquareJPEG(from cg: CGImage, side: Int) -> Data? {
    let w = cg.width
    let h = cg.height
    let s = min(w, h)
    let x = (w - s) / 2
    let y = (h - s) / 2
    guard let cropped = cg.cropping(to: CGRect(x: x, y: y, width: s, height: s)) else { return nil }

    let size = CGSize(width: side, height: side)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
      data: nil,
      width: Int(size.width),
      height: Int(size.height),
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.interpolationQuality = .high
    ctx.draw(cropped, in: CGRect(origin: .zero, size: size))
    guard let outCG = ctx.makeImage() else { return nil }

#if canImport(UIKit)
    let out = UIImage(cgImage: outCG)
    return out.jpegData(compressionQuality: 0.86)
#elseif canImport(AppKit)
    let rep = NSBitmapImageRep(cgImage: outCG)
    return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.86])
#else
    return nil
#endif
  }

  /// Creates a local preview URL (memory-backed) so the UI can show a selected image before upload.
  static func localPreviewURL(for jpeg: Data) -> URL? {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dhd-avatar-previews", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("preview-\(UUID().uuidString).jpg")
    try? jpeg.write(to: url, options: [.atomic])
    return url
  }
}

#if canImport(UIKit)
import UIKit

fileprivate extension UIImage {
  func fixOrientation() -> UIImage {
    if imageOrientation == .up { return self }
    UIGraphicsBeginImageContextWithOptions(size, false, scale)
    draw(in: CGRect(origin: .zero, size: size))
    let normalized = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return normalized ?? self
  }
}
#endif
