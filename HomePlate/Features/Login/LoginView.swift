import SwiftUI

struct LoginView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  enum Mode: String, CaseIterable, Identifiable {
    case email = "Sign in"
    case create = "Create account"
    var id: String { rawValue }
  }

  enum AccountType: String, CaseIterable, Identifiable {
    case player = "Player"
    case parent = "Parent or guardian"
    case coach = "Coach"
    var id: String { rawValue }
    var apiValue: String {
      switch self {
      case .player: "player"
      case .parent: "parent"
      case .coach: "coach"
      }
    }
  }

  @State private var mode: Mode = .email
  @State private var orgSlug = ""
  @State private var email = ""
  @State private var password = ""
  @State private var fullName = ""
  @State private var accountType: AccountType = .player
  @State private var parentCode = ""
  @State private var relationship = ""
  @State private var coachCode = ""
  @State private var isSubmitting = false
  @State private var publicMenuOpen = false

  var body: some View {
    VStack(spacing: 0) {
      publicHeader

      ScrollView {
        VStack(spacing: 0) {
          brand.padding(.bottom, 24)
          signInPanel

          HStack(spacing: 4) {
            Text("Need help?")
            Link("Contact support", destination: supportURL)
              .foregroundStyle(HP.Color.accent)
          }
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .padding(.top, 24)
        }
        .frame(maxWidth: 448)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 48)

        publicFooter
      }
      .background(HP.Color.bg)
      #if os(iOS)
      .scrollDismissesKeyboard(.interactively)
      #endif
    }
    .background(HP.Color.bg.ignoresSafeArea())
    .task { await applyInvitationContext() }
    .onChange(of: appState.pendingInvitation) { _, _ in
      Task { await applyInvitationContext() }
    }
  }

  private var publicHeader: some View {
    VStack(spacing: 0) {
      HStack(spacing: 16) {
        publicLogo(markSize: 32, textSize: 18)
        Spacer(minLength: 12)

        Button {
          withAnimation(.easeInOut(duration: 0.18)) {
            publicMenuOpen.toggle()
          }
        } label: {
          Image(systemName: publicMenuOpen ? "xmark" : "line.3.horizontal")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(HP.Color.text)
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(publicMenuOpen ? "Close menu" : "Open menu")
      }
      .frame(maxWidth: 1152)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 16)
      .frame(height: 64)

      if publicMenuOpen {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(publicNavigationLinks, id: \.label) { link in
            Link(destination: websiteURL(path: link.path)) {
              Text(link.label)
                .font(.custom("Instrument Sans", size: 14, relativeTo: .subheadline).weight(.medium))
                .foregroundStyle(HP.Color.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
            }
          }

          VStack(spacing: 8) {
            Button("Sign In") {
              withAnimation(.easeInOut(duration: 0.18)) {
                publicMenuOpen = false
              }
            }
            .buttonStyle(HPOutlineButtonStyle())

            Link(destination: websiteURL(path: "/#early-access")) {
              Text("Request Early Access")
                .font(.custom("Instrument Sans", size: 16, relativeTo: .body).weight(.semibold))
                .foregroundStyle(HP.Color.accentText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(HP.Color.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
          }
          .padding(.top, 16)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .background(HP.Color.bg)
        .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .background(HP.Color.bg.opacity(0.96))
    .overlay(alignment: .bottom) {
      Rectangle().fill(HP.Color.border).frame(height: 1)
    }
    .zIndex(2)
  }

  private var publicFooter: some View {
    VStack(alignment: .leading, spacing: 0) {
      publicLogo(markSize: 32, textSize: 18)

      Text("Home Plate — The operating system for baseball development businesses.")
        .font(.custom("Instrument Sans", size: 14, relativeTo: .subheadline))
        .foregroundStyle(HP.Color.textMuted)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 320, alignment: .leading)
        .padding(.top, 16)

      Link(supportEmail, destination: supportURL)
        .font(.custom("Instrument Sans", size: 14, relativeTo: .subheadline))
        .foregroundStyle(HP.Color.accent)
        .padding(.top, 16)

      VStack(alignment: .leading, spacing: 32) {
        footerLinks(
          heading: "Product",
          links: [
            ("Platform", "/platform"),
            ("Player Development", "/player-development"),
            ("Scheduling", "/scheduling"),
            ("Payments", "/payments"),
            ("Analytics", "/analytics")
          ]
        )
        footerLinks(
          heading: "Company",
          links: [
            ("Home", "/"),
            ("Pricing", "/pricing"),
            ("About", "/about"),
            ("Support", "/support")
          ]
        )
        footerLinks(
          heading: "Legal",
          links: [
            ("Privacy Policy", "/privacy"),
            ("Terms of Service", "/terms")
          ]
        )
      }
      .padding(.top, 40)

      VStack(alignment: .leading, spacing: 12) {
        Text("© 2026 Home Plate. All rights reserved.")
        Text("Built for baseball facilities, academies, travel organizations, and coaches.")
      }
      .font(.custom("Instrument Sans", size: 12, relativeTo: .caption))
      .foregroundStyle(HP.Color.textMuted)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 24)
      .overlay(alignment: .top) {
        Rectangle().fill(HP.Color.border).frame(height: 1)
      }
      .padding(.top, 48)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 56)
    .frame(maxWidth: 1152)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .top) {
      Rectangle().fill(HP.Color.border).frame(height: 1)
    }
  }

  private func publicLogo(markSize: CGFloat, textSize: CGFloat) -> some View {
    HStack(spacing: 10) {
      Image("BrandMark")
        .resizable()
        .scaledToFit()
        .frame(width: markSize, height: markSize)
      Text("Home Plate")
        .font(.custom("Archivo", size: textSize, relativeTo: .headline).weight(.bold))
        .foregroundStyle(HP.Color.text)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Home Plate")
  }

  private func footerLinks(heading: String, links: [(String, String)]) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(heading)
        .font(.custom("Instrument Sans", size: 14, relativeTo: .subheadline).weight(.semibold))
        .foregroundStyle(HP.Color.text)
        .padding(.bottom, 12)
      ForEach(links, id: \.0) { link in
        Link(link.0, destination: websiteURL(path: link.1))
          .font(.custom("Instrument Sans", size: 14, relativeTo: .subheadline))
          .foregroundStyle(HP.Color.textMuted)
          .padding(.bottom, 8)
      }
    }
  }

  private var publicNavigationLinks: [(label: String, path: String)] {
    [
      ("Home", "/"),
      ("Platform", "/platform"),
      ("Player Development", "/player-development"),
      ("Scheduling", "/scheduling"),
      ("Payments", "/payments"),
      ("Analytics", "/analytics"),
      ("Pricing", "/pricing"),
      ("About", "/about"),
      ("Support", "/support")
    ]
  }

  private var brand: some View {
    HStack(spacing: 10) {
      Image("BrandMark")
        .resizable()
        .scaledToFit()
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
      Text("Home Plate")
        .font(.custom("Archivo", size: 20, relativeTo: .title3).weight(.bold))
        .foregroundStyle(HP.Color.text)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Home Plate")
  }

  private var signInPanel: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(mode == .create ? "Create your account" : "Sign in")
        .font(.custom("Archivo", size: 24, relativeTo: .title2).weight(.bold))
        .foregroundStyle(HP.Color.text)
        .accessibilityAddTraits(.isHeader)

      Text(subtitle)
        .font(HP.Font.body)
        .foregroundStyle(HP.Color.textMuted)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 6)

      modeTabs.padding(.top, 20)

      VStack(alignment: .leading, spacing: 16) {
        if let invitation = appState.pendingInvitation {
          invitationNotice(invitation)
        } else if let invitationError = appState.invitationErrorText {
          HPErrorState(
            title: "Invitation unavailable",
            message: invitationError,
            onRetry: retryInvitation
          )
        }

        if mode == .create {
          HPFormField(label: "Organization code", text: $orgSlug, placeholder: "your-organization")
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
        }

        switch mode {
        case .email:
          HPFormField(label: "Email", text: $email)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)
            #endif
            .autocorrectionDisabled()
        case .create:
          createAccountFields
        }

        HPFormField(label: "Password", text: $password, kind: .secure)

        if let error = appState.authError, !error.isEmpty {
          errorNotice(safeAuthMessage(error))
        }

        HPButton(
          title: isSubmitting ? "Please wait…" : (mode == .create ? "Create account" : "Sign in"),
          variant: .primary,
          size: .lg,
          isLoading: isSubmitting,
          fullWidth: true
        ) {
          Task { await submit() }
        }
        .disabled(isSubmitDisabled)
        .keyboardShortcut(.defaultAction)
      }
      .padding(.top, 24)
    }
    .padding(panelPadding)
    .background(HP.Color.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(HP.Color.border, lineWidth: 1)
    }
  }

  private var panelPadding: CGFloat {
    #if os(macOS)
    32
    #else
    horizontalSizeClass == .regular ? 32 : 24
    #endif
  }

  private var modeTabs: some View {
    LazyVGrid(columns: tabColumns, spacing: 8) {
      ForEach(Mode.allCases) { item in
        Button {
          mode = item
          appState.authError = nil
        } label: {
          Text(item.rawValue)
            .font(.custom("Instrument Sans", size: 14, relativeTo: .subheadline).weight(.semibold))
            .foregroundStyle(mode == item ? HP.Color.text : HP.Color.textMuted)
            .frame(maxWidth: .infinity, minHeight: 36)
            .padding(.horizontal, 12)
            .background(mode == item ? HP.Color.surfaceRaised : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == item ? [.isButton, .isSelected] : .isButton)
      }
    }
  }

  private var tabColumns: [GridItem] {
    #if os(macOS)
    Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)
    #else
    Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)
    #endif
  }

  @ViewBuilder
  private var createAccountFields: some View {
    HPFormField(label: "Email", text: $email)
      #if os(iOS)
      .textInputAutocapitalization(.never)
      .keyboardType(.emailAddress)
      #endif
      .autocorrectionDisabled()

    HPFormField(label: "Full name", text: $fullName)
      #if os(iOS)
      .textInputAutocapitalization(.words)
      #endif

    VStack(alignment: .leading, spacing: 6) {
      Text("I am a")
        .font(HP.Font.body.weight(.medium))
        .foregroundStyle(HP.Color.text)
      Picker("I am a", selection: $accountType) {
        ForEach(AccountType.allCases) { item in
          Text(item.rawValue).tag(item)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
      .padding(.horizontal, 14)
      .background(HP.Color.surfaceRaised)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(HP.Color.input, lineWidth: 1)
      }
    }

    if accountType == .parent && appState.pendingInvitation == nil {
      HPFormField(label: "Parent code", text: $parentCode)
      HPFormField(label: "Relationship to player", text: $relationship, placeholder: "Mother, father, guardian…")
    }

    if accountType == .coach && appState.pendingInvitation == nil {
      HPFormField(label: "Coach code", text: $coachCode)
    }
  }

  private var subtitle: String {
    switch mode {
    case .email: "Use the email and password on your account."
    case .create: "Ask your organization for its code before you start."
    }
  }

  private var isSubmitDisabled: Bool {
    let cleanOrg = normalized(orgSlug)
    let cleanEmail = normalized(email)
    return isSubmitting
      || password.count < 6
      || (mode == .create && cleanOrg.isEmpty)
      || (mode == .email && !cleanEmail.contains("@"))
      || (mode == .create && !cleanEmail.contains("@"))
      || (mode == .create && appState.pendingInvitation == nil && accountType == .parent && normalized(parentCode).isEmpty)
  }

  private func submit() async {
    isSubmitting = true
    defer { isSubmitting = false }
    appState.authError = nil
    switch mode {
    case .email:
      await appState.signIn(email: normalized(email), password: password)
    case .create:
      await appState.signUp(
        orgSlug: normalized(orgSlug),
        email: normalized(email),
        password: password,
        fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
        accountType: accountType.apiValue,
        parentCode: parentCode,
        relationship: relationship,
        coachCode: coachCode,
        invitationToken: appState.pendingInvitationToken
      )
    }
  }

  private func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private func applyInvitationContext() async {
    guard let invitation = appState.pendingInvitation else { return }
    mode = .create
    accountType = invitation.invitation_context == .family ? .parent : .coach
    guard orgSlug.isEmpty, let supabase = appState.supabase else { return }
    let organizations = try? await supabase.listOrgs()
    if let org = organizations?.first(where: { $0.id == invitation.organization_id }) {
      orgSlug = org.slug
    }
  }

  private func retryInvitation() {
    guard let token = appState.pendingInvitationToken,
          let url = URL(string: "homeplate://invite/\(token)") else { return }
    Task { await appState.handleInvitationURL(url) }
  }

  private func invitationNotice(_ invitation: SDOrganizationInvitationValidation) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "person.badge.key").foregroundStyle(HP.Color.accent)
      Text("Continue to \(invitation.organization_name) as \(invitation.invitation_context.invitedRole.lowercased()).")
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.text)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(HP.Color.accent.opacity(0.10))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func errorNotice(_ message: String) -> some View {
    Text(message)
      .font(.custom("Instrument Sans", size: 14, relativeTo: .subheadline))
      .foregroundStyle(HP.Color.danger)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(HP.Color.danger.opacity(0.10))
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func safeAuthMessage(_ raw: String) -> String {
    let value = raw.lowercased()
    if value.contains("already registered") || value.contains("already exists") || value.contains("duplicate") {
      return "An account with those details already exists. Try signing in or use different account details."
    }
    if value.contains("invite") || value.contains("parent code") || value.contains("coach code") {
      return "The invite or family code could not be verified. Check the code and try again."
    }
    if value.contains("invalid") && value.contains("email") {
      return "Enter a valid email address and try again."
    }
    if value.contains("rate limit") || value.contains("too many requests") {
      return "Too many requests were made. Wait a moment, then try again."
    }
    if value.contains("credentials") || value.contains("password") || value.contains("unauthorized") {
      return "Login credentials are incorrect."
    }
    if value.contains("not configured") {
      return "Sign-in is unavailable in this build. Contact support."
    }
    return mode == .create
      ? "Home Plate couldn’t create your account. Check the details and try again."
      : "Home Plate couldn’t sign you in. Check your details and try again."
  }

  private var supportURL: URL {
    if let email = DHDAppConfig.supportEmail,
       let url = URL(string: "mailto:\(email)") {
      return url
    }
    return URL(string: "mailto:support@homeplateapp.com")!
  }

  private var supportEmail: String {
    DHDAppConfig.supportEmail ?? "support@homeplateapp.com"
  }

  private func websiteURL(path: String) -> URL {
    let configured = DHDAppConfig.websiteHost?.trimmingCharacters(in: .whitespacesAndNewlines)
    let rawBase: String
    if let configured, !configured.isEmpty {
      rawBase = configured.hasPrefix("http://") || configured.hasPrefix("https://")
        ? configured
        : "https://\(configured)"
    } else {
      rawBase = "https://homeplateapp.com"
    }

    if path.hasPrefix("/#"), let base = URL(string: rawBase) {
      var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
      components?.fragment = String(path.dropFirst(2))
      return components?.url ?? base
    }

    return URL(string: path, relativeTo: URL(string: rawBase))?.absoluteURL
      ?? URL(string: "https://homeplateapp.com")!
  }
}

private struct HPOutlineButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.custom("Instrument Sans", size: 16, relativeTo: .body).weight(.semibold))
      .foregroundStyle(HP.Color.text)
      .frame(maxWidth: .infinity, minHeight: 44)
      .background(HP.Color.bg)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(HP.Color.border, lineWidth: 1)
      }
      .opacity(configuration.isPressed ? 0.78 : 1)
  }
}
