import SwiftUI

struct LoginView: View {
  @EnvironmentObject private var appState: AppState

  enum Screen: String, CaseIterable, Identifiable {
    case signIn = "Sign In"
    case signUp = "Create Account"
    var id: String { rawValue }
  }

  @State private var screen: Screen = .signIn

  enum AccountType: String, CaseIterable, Identifiable {
    case player = "Player"
    case parent = "Parent"
    case coach = "Coach"
    var id: String { rawValue }

    var apiValue: String {
      switch self {
      case .player: return "player"
      case .parent: return "parent"
      case .coach: return "coach"
      }
    }
  }

  @State private var orgs: [SDOrg] = []
  @State private var selectedOrgId: UUID?
  @State private var isLoadingOrganizations = false
  @State private var organizationLoadError: String?

  @State private var emailOrUsername: String = ""
  @State private var signUpEmail: String = ""
  @State private var signUpUsername: String = ""
  @State private var password: String = ""
  @State private var fullName: String = ""
  @State private var accountType: AccountType = .player
  @State private var parentCode: String = ""
  @State private var relationship: String = ""
  @State private var coachInviteCode: String = ""
  @State private var isSubmitting = false
  @State private var showReset = false

  private var selectedOrg: SDOrg? {
    guard let selectedOrgId else { return nil }
    return orgs.first { $0.id == selectedOrgId }
  }

  private func normalizedUsername() -> String {
    emailOrUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private func normalizedSignUpEmail() -> String {
    signUpEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private func normalizedSignUpUsername() -> String {
    signUpUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private var isEmailSignIn: Bool {
    screen == .signIn && normalizedUsername().contains("@")
  }

  var body: some View {
    HPScreenScaffold(widthMode: .compact, maxContentWidth: 560) { _ in
      VStack(alignment: .leading, spacing: HP.Space.md) {
        loginHeader

        HPCard {
          organizationAndModeControls
        }

        HPCard {
          if screen == .signUp {
            signUpFields
          } else {
            signInFields
          }
        }

        HPCard(style: .flat) {
          troubleshootingDisclosure
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    #if os(iOS)
    .scrollDismissesKeyboard(.interactively)
    #endif
    .task {
      await loadOrgsIfNeeded()
    }
    .alert("Reset password", isPresented: $showReset) {
      Button("Send reset email") {
        let raw = emailOrUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.contains("@") else {
          appState.authError = "Enter your email address to reset your password."
          return
        }
        Task { await appState.resetPassword(email: raw.lowercased()) }
      }
      .keyboardShortcut(.defaultAction)
      Button("Cancel", role: .cancel) {}
        .keyboardShortcut(.cancelAction)
    } message: {
      Text("We’ll email a reset link if you entered a real email address.")
    }
  }

  private var loginHeader: some View {
    HStack(alignment: .top, spacing: HP.Space.sm) {
      Image(systemName: "baseball.diamond.bases")
        .font(.system(size: 28, weight: .semibold))
        .foregroundStyle(HP.Color.accent)
        .frame(width: 44, height: 44)
        .background(
          RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
            .fill(HP.Color.accent.opacity(0.14))
        )
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: HP.Space.xs) {
        Text(DHDAppConfig.displayName)
          .font(HP.Font.title)
          .tracking(HP.Font.titleTracking)
          .foregroundStyle(HP.Color.text)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)
        Text("Choose your organization, then sign in or create an account.")
          .font(HP.Font.callout)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var organizationAndModeControls: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      HPSectionHeader("Access")

      if orgs.isEmpty {
        if isLoadingOrganizations {
          HPLoadingState(text: "Loading organizations…")
        } else {
          VStack(alignment: .leading, spacing: HP.Space.xs) {
            HStack(alignment: .center, spacing: HP.Space.sm) {
              Text("Organization list unavailable")
                .font(HP.Font.callout.weight(.semibold))
                .foregroundStyle(HP.Color.text)
                .fixedSize(horizontal: false, vertical: true)
              Spacer(minLength: 0)
              HPButton(
                title: "Retry",
                systemImage: "arrow.clockwise",
                variant: .secondary,
                size: .sm
              ) {
                Task { await loadOrgsIfNeeded(force: true) }
              }
            }
            if let organizationLoadError {
              Text(organizationLoadError)
                .font(HP.Font.caption)
                .foregroundStyle(HP.Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            }
            Text("Email sign-in still works without selecting an organization.")
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.textMuted)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 6) {
          Text("ORGANIZATION")
            .font(HP.Font.eyebrow)
            .tracking(HP.Font.eyebrowTracking)
            .foregroundStyle(HP.Color.textMuted)
          Picker("Organization", selection: $selectedOrgId) {
            ForEach(orgs) { org in
              Text(org.displayName).tag(Optional(org.id))
            }
          }
          .pickerStyle(.menu)
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
      }

      HPSegmentedControl(
        options: Screen.allCases.map { (value: $0, label: $0.rawValue) },
        selection: $screen
      )
      .accessibilityLabel("Authentication screen")
    }
  }

  private var signInFields: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      HPSectionHeader("Sign in")

      HPFormField(
        label: "Email or username",
        text: $emailOrUsername,
        placeholder: "Email or organization username"
      )
      #if canImport(UIKit)
        .textInputAutocapitalization(.never)
      #endif
        .autocorrectionDisabled()
        .frame(minHeight: 44)

      passwordField
      authErrorView
      submitButton

      HStack(spacing: HP.Space.sm) {
        Rectangle().fill(HP.Color.border).frame(height: 1)
        Text("OR")
          .font(HP.Font.eyebrow)
          .tracking(HP.Font.eyebrowTracking)
          .foregroundStyle(HP.Color.textMuted)
        Rectangle().fill(HP.Color.border).frame(height: 1)
      }
      .accessibilityElement(children: .combine)

      AppleSignInButtonView()
        .environmentObject(appState)

      HPButton(
        title: "Forgot password?",
        variant: .tertiary,
        size: .sm
      ) {
        showReset = true
      }
    }
  }

  private var signUpFields: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      HPSectionHeader("Create account")

      HPFormField(label: "Email", text: $signUpEmail, placeholder: "Account email")
      #if canImport(UIKit)
        .textInputAutocapitalization(.never)
      #endif
        .autocorrectionDisabled()
        .frame(minHeight: 44)

      HPFormField(label: "Username", text: $signUpUsername, placeholder: "Organization username")
      #if canImport(UIKit)
        .textInputAutocapitalization(.never)
      #endif
        .autocorrectionDisabled()
        .frame(minHeight: 44)

      VStack(alignment: .leading, spacing: 6) {
        Text("ACCOUNT TYPE")
          .font(HP.Font.eyebrow)
          .tracking(HP.Font.eyebrowTracking)
          .foregroundStyle(HP.Color.textMuted)
        HPSegmentedControl(
          options: AccountType.allCases.map { (value: $0, label: $0.rawValue) },
          selection: $accountType
        )
      }

      HPFormField(label: "Full name (optional)", text: $fullName, placeholder: "Full name")
      #if canImport(UIKit)
        .textInputAutocapitalization(.words)
      #endif
        .autocorrectionDisabled()
        .frame(minHeight: 44)

      if accountType == .parent {
        HPFormField(
          label: "Parent code",
          text: $parentCode,
          placeholder: "Code from player",
          helper: "Ask your child for their Parent code in Account → Family."
        )
        #if canImport(UIKit)
          .textInputAutocapitalization(.characters)
        #endif
          .autocorrectionDisabled()
          .frame(minHeight: 44)

        HPFormField(
          label: "Relationship (optional)",
          text: $relationship,
          placeholder: "Relationship to player"
        )
        #if canImport(UIKit)
          .textInputAutocapitalization(.words)
        #endif
          .autocorrectionDisabled()
          .frame(minHeight: 44)
      }

      if accountType == .coach {
        HPFormField(
          label: "Coach invite code",
          text: $coachInviteCode,
          placeholder: "Invite code",
          helper: "Coach accounts require an invite code."
        )
        #if canImport(UIKit)
          .textInputAutocapitalization(.never)
        #endif
          .autocorrectionDisabled()
          .frame(minHeight: 44)
      }

      passwordField
      authErrorView
      submitButton
    }
  }

  private var passwordField: some View {
    HPFormField(label: "Password", text: $password, kind: .secure, placeholder: "Password")
      .frame(minHeight: 44)
  }

  @ViewBuilder
  private var authErrorView: some View {
    if let error = appState.authError, !error.isEmpty {
      if error.localizedCaseInsensitiveContains("password reset email sent") {
        HStack(alignment: .top, spacing: HP.Space.sm) {
          HPStatusBadge(text: "Sent", kind: .success)
          Text("Password reset email sent. Check your inbox and spam folder.")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.text)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
      } else {
        HPErrorState(
          title: screen == .signUp ? "Account couldn’t be created" : "Authentication issue",
          message: safeAuthMessage(error)
        )
      }
    }
  }

  private var submitButton: some View {
    HPButton(
      title: screen == .signUp ? "Create Account" : "Sign In",
      systemImage: screen == .signUp ? "person.badge.plus" : "arrow.right.circle",
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

  private var isSubmitDisabled: Bool {
    isSubmitting
      || password.isEmpty
      || (!isEmailSignIn && selectedOrg == nil)
      || (screen == .signIn && normalizedUsername().isEmpty)
      || (screen == .signUp && normalizedSignUpEmail().isEmpty)
      || (screen == .signUp && normalizedSignUpUsername().isEmpty)
      || (screen == .signUp && accountType == .parent && parentCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      || (screen == .signUp && accountType == .coach && coachInviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  private var troubleshootingDisclosure: some View {
    DisclosureGroup("Having trouble signing in?") {
      Text("You can sign in with either your account email or your organization-specific username. Password reset requires your email address.")
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, HP.Space.xs)
    }
    .font(HP.Font.callout.weight(.semibold))
    .foregroundStyle(HP.Color.textTertiary)
    .frame(minHeight: 44)
  }

  private func safeAuthMessage(_ error: String) -> String {
    let knownMessages = [
      "Enter your email address to reset your password.",
      "Pick an organization first.",
      "Pick an organization before signing in with a username.",
      "Login credentials are incorrect.",
      "We couldn't sign you in right now. Check your connection and try again.",
      "The selected organization could not be found. Refresh the organization list and try again.",
    ]
    if let known = knownMessages.first(where: { error.caseInsensitiveCompare($0) == .orderedSame }) {
      return known
    }

    let normalized = error.lowercased()
    if normalized.contains("already registered")
      || normalized.contains("already exists")
      || normalized.contains("username_taken")
      || normalized.contains("username taken")
      || normalized.contains("duplicate") {
      return "An account with those details already exists. Try signing in or use different account details."
    }
    if normalized.contains("invite")
      || normalized.contains("parent code")
      || normalized.contains("parent_code")
      || normalized.contains("coach code")
      || normalized.contains("coach_code") {
      return "The invite or family code could not be verified. Check the code and try again."
    }
    if normalized.contains("coach_signup_disabled") {
      return "Coach account creation is unavailable for this organization. Ask an organization owner for an invite."
    }
    if normalized.contains("invalid email")
      || normalized.contains("invalid_email")
      || normalized.contains("email address is invalid") {
      return "Enter a valid email address and try again."
    }
    if normalized.contains("rate limit")
      || normalized.contains("too many requests")
      || normalized.contains("request limit") {
      return "Too many requests were made. Wait a moment, then try again."
    }
    if normalized.contains("password")
      && (normalized.contains("weak")
        || normalized.contains("length")
        || normalized.contains("characters")
        || normalized.contains("requirements")) {
      return "The password does not meet the account requirements. Use a longer, stronger password and try again."
    }
    if normalized.contains("reset") || normalized.contains("recovery") {
      return "The password-reset request could not be completed. Check the email address and try again."
    }
    if normalized.contains("not configured") {
      return "Sign-in is unavailable in this build. Install a configured Home Plate build or contact support."
    }
    return screen == .signUp
      ? "Home Plate couldn’t create your account. Check the details and try again."
      : "Home Plate couldn’t complete the authentication request. Check your connection and try again."
  }

  private func submit() async {
    isSubmitting = true
    defer { isSubmitting = false }
    if screen == .signUp {
      guard let org = selectedOrg else {
        appState.authError = "Pick an organization first."
        return
      }
      await appState.signUp(
        orgSlug: org.slug,
        username: normalizedSignUpUsername(),
        email: normalizedSignUpEmail(),
        password: password,
        fullName: fullName,
        accountType: accountType.apiValue,
        parentCode: parentCode,
        relationship: relationship,
        coachCode: coachInviteCode
      )
    } else {
      let identifier = normalizedUsername()
      if !identifier.contains("@"), selectedOrg == nil {
        appState.authError = "Pick an organization before signing in with a username."
        return
      }
      await appState.signIn(
        orgSlug: selectedOrg?.slug ?? "",
        identifier: identifier,
        password: password
      )
    }
  }

  private func loadOrgsIfNeeded(force: Bool = false) async {
    guard force || orgs.isEmpty else { return }
    guard !isLoadingOrganizations else { return }
    guard let supabase = appState.supabase else { return }
    isLoadingOrganizations = true
    organizationLoadError = nil
    defer { isLoadingOrganizations = false }
    do {
      let fetched = try await supabase.listOrgs()
      orgs = fetched
      if selectedOrgId == nil {
        selectedOrgId = fetched.first?.id
      }
    } catch {
      organizationLoadError = "Retry to load organizations, or use your account email to sign in now."
    }
  }
}
