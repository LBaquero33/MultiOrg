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

/// Unified Account / Profile screen (role-aware).
/// - Profile: avatar + full bio fields
/// - Parents/Family: request/approve parent linking
/// - Subscription/Access: entitlement status (read-only)
/// - Security: password reset + sign out
struct AccountView: View {
  @EnvironmentObject private var appState: AppState

  @State private var details: SupabaseService.SDProfileDetails?
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var toastText: String?

  @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
  @State private var myParentCode: String?

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
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        DHDHeaderCard {
          HStack(spacing: 14) {
            DHDAvatarView(url: avatarURL, initials: initials, size: 54)
            VStack(alignment: .leading, spacing: 2) {
              Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
              Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))
            }
            Spacer()
          }
        }

        if isLoading {
          DHDCard(style: .flat) { HStack(spacing: 10) { ProgressView(); Text("Loading…").foregroundStyle(DHDTheme.textSecondary) } }
        }

        organizationCard
        profileCard
        familyCard
        accessCard
        if appState.myProfile?.isCoach == true { notificationsCard }
        securityCard

        if let toastText, !toastText.isEmpty {
          DHDToast(text: toastText)
            .transition(.opacity)
        }
      }
      .padding(DHDTheme.pagePadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(maxHeight: .infinity, alignment: .topLeading)
    }
    .background(DHDTheme.pageBackground)
    .navigationTitle("Account")
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .task(id: appState.activeOrgId) { await reload() }
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

  @ViewBuilder
  private var organizationCard: some View {
    if !appState.availableOrganizations.isEmpty {
      DHDCard {
        HStack(spacing: 12) {
          Image(systemName: "building.2.fill")
            .font(.title3)
            .foregroundStyle(DHDTheme.accent)
            .frame(width: 28)
          VStack(alignment: .leading, spacing: 2) {
            Text("Active organization")
              .font(.caption.weight(.semibold))
              .foregroundStyle(DHDTheme.textSecondary)
            Text(activeOrganizationName)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(DHDTheme.textPrimary)
          }
          Spacer()
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
            .buttonStyle(.bordered)
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

  private var profileCard: some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        DHDSectionHeader("Profile") {
          HStack(spacing: 8) {
            Button {
              Task { await reload() }
            } label: {
              Label("Refresh", systemImage: "arrow.clockwise")
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
          }
        }

        HStack(alignment: .center, spacing: 12) {
          DHDAvatarView(url: avatarURL, initials: initials, size: 72)
          VStack(alignment: .leading, spacing: 8) {
#if canImport(UIKit)
            PhotosPicker(selection: $photoItem, matching: .images) {
              Label("Change photo", systemImage: "photo")
            }
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
              Text("Photo selected • will upload on Save")
                .font(.caption)
                .foregroundStyle(DHDTheme.textSecondary)
            }
          }
          Spacer()
        }

        Group {
          TextField("Full name", text: $fullName)
            .textFieldStyle(.roundedBorder)
          TextField("Phone (optional)", text: $phone)
            .textFieldStyle(.roundedBorder)

          HStack(spacing: 10) {
            TextField("Grad year", text: $gradYear)
              .textFieldStyle(.roundedBorder)
              .frame(maxWidth: 140)
            TextField("Primary position", text: $primaryPosition)
              .textFieldStyle(.roundedBorder)
          }

          HStack(spacing: 10) {
            Picker("Bats", selection: $bats) {
              Text("R").tag("R")
              Text("L").tag("L")
              Text("S").tag("S")
              Text("Unknown").tag("unknown")
            }
            .pickerStyle(.menu)

            Picker("Throws", selection: $throwsHand) {
              Text("R").tag("R")
              Text("L").tag("L")
              Text("Unknown").tag("unknown")
            }
            .pickerStyle(.menu)
          }

          HStack(spacing: 10) {
            TextField("School", text: $school)
              .textFieldStyle(.roundedBorder)
            TextField("Team", text: $team)
              .textFieldStyle(.roundedBorder)
          }

          HStack(spacing: 10) {
            TextField("Height (in)", text: $heightIn)
              .textFieldStyle(.roundedBorder)
              .frame(maxWidth: 140)
            TextField("Weight (lb)", text: $weightLb)
              .textFieldStyle(.roundedBorder)
              .frame(maxWidth: 140)
          }

          TextField("Notes", text: $notes, axis: .vertical)
            .lineLimit(4...10)
            .textFieldStyle(.roundedBorder)
        }

        HStack(spacing: 10) {
          Button {
            Task { await saveProfile() }
          } label: {
            Label("Save", systemImage: "checkmark.circle.fill")
              .frame(maxWidth: 220)
          }
          .buttonStyle(.borderedProminent)

          if appState.myProfile?.isPlayer == true {
            Button {
              appState.showOnboardingEditor = true
            } label: {
              Label("Edit onboarding", systemImage: "sparkles")
            }
            .buttonStyle(.bordered)
          }

          Spacer()
        }
      }
    }
  }

  private var familyCard: some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        DHDSectionHeader("Family / Parents") { EmptyView() }

        if appState.myProfile?.isCoach == true {
          CoachParentRequestsPanel()
            .environmentObject(appState)
        } else if appState.myProfile?.isPlayer == true {
          if let code = myParentCode, !code.isEmpty {
            DHDFormRow("Parent code") {
              HStack(spacing: 8) {
                Text(code)
                  .font(.system(.body, design: .monospaced))
                  .textSelection(.enabled)
                Button {
                  copyToPasteboard(code)
                  toast("Copied parent code.")
                } label: {
                  Label("Copy", systemImage: "doc.on.doc")
                    .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
              }
            }
            Text("Share this code with a parent/guardian so they can create a Parent account and link to you.")
              .font(.footnote)
              .foregroundStyle(DHDTheme.textSecondary)
          } else {
            Text("Parent code: —")
              .foregroundStyle(DHDTheme.textSecondary)
              .font(.subheadline)
          }
          PlayerParentRequestsPanel()
            .environmentObject(appState)
        } else if appState.myProfile?.isParent == true {
          Text("Use the Children list to view linked players. Pending invites will appear automatically when available.")
            .foregroundStyle(DHDTheme.textSecondary)
            .font(.subheadline)
        } else {
          Text("—")
            .foregroundStyle(DHDTheme.textSecondary)
        }
      }
    }
  }

  private var accessCard: some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 10) {
        DHDSectionHeader("Subscription / Access") { EmptyView() }

        if appState.myProfile?.isPlayer == true {
          entitlementSummary(entitlement: appState.myEntitlement)
          if appState.myEntitlement?.is_active != true {
            SubscribeButtonRow(label: "Subscribe (6-month)")
              .environmentObject(appState)
          }
          Button("Manage subscription (coming soon)") {
            toast("Subscription management is coming soon.")
          }
          .buttonStyle(.bordered)
        } else if appState.myProfile?.isCoach == true {
          Text("Access gating applies to player accounts only.")
            .foregroundStyle(DHDTheme.textSecondary)

          SubscribeButtonRow(label: "Open subscription page")
            .environmentObject(appState)

          if AppFlags.enableEntitlementTestUI {
            Divider().padding(.vertical, 4)
            EntitlementTestPanel()
              .environmentObject(appState)
          }
        } else if appState.myProfile?.isParent == true {
          Text("You can request payments on behalf of your child from the child’s Billing tab.")
            .foregroundStyle(DHDTheme.textSecondary)

          SubscribeButtonRow(label: "Open subscription page")
            .environmentObject(appState)
        } else {
          Text("—")
            .foregroundStyle(DHDTheme.textSecondary)
        }
      }
    }
  }

  private struct SubscribeButtonRow: View {
    let label: String

    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) private var openURL
    @State private var err: String?

    private var stripeSubscribeURL: URL? {
      let rawAny = Bundle.main.object(forInfoDictionaryKey: "DHD_STRIPE_SUBSCRIBE_URL")
      let raw0 = (rawAny as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let raw = raw0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
      guard !raw.isEmpty else { return nil }
      let candidate = raw.lowercased().hasPrefix("http") ? raw : "https://\(raw)"
      guard let url = URL(string: candidate), url.scheme?.hasPrefix("http") == true, url.host != nil else { return nil }
      return url
    }

    private func withClientReferenceId(base: URL, userId: UUID) -> URL {
      let key = "client_reference_id"
      let val = userId.uuidString
      guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return base }
      var items = comps.queryItems ?? []
      items.removeAll { $0.name == key }
      items.append(URLQueryItem(name: key, value: val))
      comps.queryItems = items
      return comps.url ?? base
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        if let err, !err.isEmpty {
          Text(err)
            .font(.footnote)
            .foregroundStyle(.red)
        }
        Button {
          err = nil
          Task {
            do {
              guard let supabase = appState.supabase else { throw NSError(domain: "DHD", code: 1, userInfo: [NSLocalizedDescriptionKey: "Supabase not configured."]) }
              guard let base = stripeSubscribeURL else { throw NSError(domain: "DHD", code: 2, userInfo: [NSLocalizedDescriptionKey: "Stripe subscribe link not configured."]) }
              let session = try await supabase.client.auth.session
              let url = withClientReferenceId(base: base, userId: session.user.id)
              openURL(url)
            } catch {
              err = error.localizedDescription
            }
          }
        } label: {
          Label(label, systemImage: "creditcard")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
      }
    }
  }

  private struct EntitlementTestPanel: View {
    @EnvironmentObject var appState: AppState
    @State private var targetUserIdText: String = ""
    @State private var isBusy = false

    var body: some View {
      VStack(alignment: .leading, spacing: 10) {
        DHDSectionHeader("DEV: Entitlement Test") { EmptyView() }
        Text("Simulates a subscription toggle without Stripe or any payment. Coach-only.")
          .font(.footnote)
          .foregroundStyle(DHDTheme.textSecondary)

        DHDFormRow("Target user UUID") {
          TextField("UUID", text: $targetUserIdText)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 420)
        }

        HStack(spacing: 10) {
          Button {
            Task { await setActive(true) }
          } label: {
            Label("Set Active", systemImage: "checkmark.seal")
          }
          .buttonStyle(.borderedProminent)
          .disabled(isBusy)

          Button(role: .destructive) {
            Task { await setActive(false) }
          } label: {
            Label("Set Inactive", systemImage: "xmark.seal")
          }
          .buttonStyle(.bordered)
          .disabled(isBusy)

          Spacer()

          Button {
            if let uid = appState.myProfile?.id {
              targetUserIdText = uid.uuidString
            }
          } label: {
            Label("Use mine", systemImage: "person.crop.circle")
          }
          .buttonStyle(.borderless)
          .disabled(isBusy)
        }
      }
      .task {
        if targetUserIdText.isEmpty, let uid = appState.myProfile?.id {
          targetUserIdText = uid.uuidString
        }
      }
    }

    private func setActive(_ active: Bool) async {
      guard let supabase = appState.supabase else { return }
      guard let uid = UUID(uuidString: targetUserIdText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        appState.globalToastText = "Invalid UUID."
        return
      }
      isBusy = true
      defer { isBusy = false }
      do {
        try await supabase.entitlementTestSet(userId: uid, isActive: active)
        appState.globalToastText = active ? "Set Active." : "Set Inactive."
        // Refresh current user's entitlement so you can immediately see the effect when targeting yourself.
        await appState.refreshEntitlement()
      } catch {
        appState.globalToastText = error.localizedDescription
      }
    }
  }

  private var securityCard: some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 10) {
        DHDSectionHeader("Security") { EmptyView() }

        Button {
          Task { await sendPasswordResetToMe() }
        } label: {
          Label("Send password reset email", systemImage: "key")
        }
        .buttonStyle(.bordered)

        Button(role: .destructive) {
          Task { await appState.signOut() }
        } label: {
          Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
        }
        .buttonStyle(.bordered)
      }
    }
  }

  private var notificationsCard: some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 10) {
        DHDSectionHeader("Notifications") { EmptyView() }

        DHDFormRow("Messages and facility activity") {
          Text(notificationStatusLabel)
        }

        Button {
          Task {
            await appState.requestCoachNotificationPermission()
            await refreshNotificationStatus()
          }
        } label: {
          Label("Enable notifications", systemImage: "bell")
        }
        .buttonStyle(.bordered)
      }
    }
  }

  private var notificationStatusLabel: String {
    switch notificationStatus {
    case .authorized: return "Enabled"
    case .denied: return "Denied"
    case .notDetermined: return "Not set"
    case .provisional: return "Provisional"
    case .ephemeral: return "Ephemeral"
    @unknown default: return "Unknown"
    }
  }

  private func entitlementSummary(entitlement: SDAccessEntitlement?) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      let active = entitlement?.is_active == true
      HStack {
        DHDStatusBadge(text: active ? "Active" : "Inactive", color: active ? .green : .red)
        Spacer()
      }
      if let end = entitlement?.current_period_end {
        DHDFormRow("Renews/Ends") { Text(end.formatted(date: .abbreviated, time: .omitted)) }
      }
      if let src = entitlement?.source, !src.isEmpty {
        DHDFormRow("Source") { Text(src) }
      }
    }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
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

      await refreshNotificationStatus()
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

  private func refreshNotificationStatus() async {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    notificationStatus = settings.authorizationStatus
  }

  private func saveProfile() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      var avatarPath: String? = details?.avatar_path
      if let jpeg = pendingAvatarJPEG {
        avatarPath = try await supabase.uploadMyAvatarJPEG(jpeg)
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
        notes: cleanOrNil(notes)
      )
      try await supabase.updateMyProfileDetails(patch)
      toast("Saved.")
      await appState.loadMyProfile()
      await reload()
    } catch {
      errorText = error.localizedDescription
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
      }
    } catch {
      errorText = error.localizedDescription
    }
  }
#else
  private func loadMacImageURL(_ url: URL) async {
    do {
      let data = try Data(contentsOf: url)
      if let jpeg = AvatarImageProcessor.squareJPEG(from: data, side: 512) {
        pendingAvatarJPEG = jpeg
        avatarURL = AvatarImageProcessor.localPreviewURL(for: jpeg)
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
    .overlay(Circle().strokeBorder(DHDTheme.separator.opacity(0.45), lineWidth: 1))
  }

  private var placeholder: some View {
    ZStack {
      Circle().fill(DHDTheme.accent.opacity(0.18))
      Text(initials)
        .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
        .foregroundStyle(DHDTheme.accent)
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
