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
    Group {
      #if os(iOS)
      if screen == .signIn {
        signInPage
      } else {
        scrollingPage
      }
      #else
      scrollingPage
      #endif
    }
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
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("We’ll email a reset link if you entered a real email address.")
    }
  }

  private var signInPage: some View {
    VStack(alignment: .leading, spacing: 16) {
      loginHeader
      organizationAndModeControls
      signInFields
      troubleshootingDisclosure
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 24)
    .safeAreaPadding(.top, 12)
    .padding(.bottom, 16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(DHDTheme.pageBackground.ignoresSafeArea())
  }

  private var scrollingPage: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        loginHeader
        organizationAndModeControls
        if screen == .signUp {
          signUpFields
        } else {
          signInFields
        }
        troubleshootingDisclosure
      }
      .padding(DHDTheme.pagePadding)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(DHDTheme.pageBackground.ignoresSafeArea())
    #if os(iOS)
    .scrollDismissesKeyboard(.interactively)
    #endif
  }

  private var loginHeader: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(DHDAppConfig.displayName)
        .font(.largeTitle.bold())
      Text("Choose your organization, then sign in or create an account.")
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var organizationAndModeControls: some View {
    VStack(spacing: 12) {
      if orgs.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 10) {
            if isLoadingOrganizations {
              ProgressView()
              Text("Loading organizations…")
                .foregroundStyle(.secondary)
            } else {
              Text("Organization list unavailable")
                .foregroundStyle(.secondary)
              Button("Retry") {
                Task { await loadOrgsIfNeeded(force: true) }
              }
            }
          }
          if let organizationLoadError {
            Text(organizationLoadError)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          Text("Email sign-in still works without selecting an organization.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        Picker("Organization", selection: $selectedOrgId) {
          ForEach(orgs) { org in
            Text(org.displayName).tag(Optional(org.id))
          }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      Picker("Auth screen", selection: $screen) {
        ForEach(Screen.allCases) { option in
          Text(option.rawValue).tag(option)
        }
      }
      .pickerStyle(.segmented)
    }
  }

  private var signInFields: some View {
    VStack(spacing: 12) {
      TextField("Email or username", text: $emailOrUsername)
      #if canImport(UIKit)
        .textInputAutocapitalization(.never)
      #endif
        .autocorrectionDisabled()
        .textFieldStyle(RoundedBorderTextFieldStyle())

      passwordField
      authErrorView
      submitButton

      Text("or")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.top, 2)
      AppleSignInButtonView()
        .environmentObject(appState)

      Button("Forgot password?") { showReset = true }
        .font(.footnote.weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
  }

  private var signUpFields: some View {
    VStack(spacing: 12) {
      TextField("Email", text: $signUpEmail)
      #if canImport(UIKit)
        .textInputAutocapitalization(.never)
      #endif
        .autocorrectionDisabled()
        .textFieldStyle(RoundedBorderTextFieldStyle())

      TextField("Username", text: $signUpUsername)
      #if canImport(UIKit)
        .textInputAutocapitalization(.never)
      #endif
        .autocorrectionDisabled()
        .textFieldStyle(RoundedBorderTextFieldStyle())

      Picker("Account type", selection: $accountType) {
        ForEach(AccountType.allCases) { type in
          Text(type.rawValue).tag(type)
        }
      }
      .pickerStyle(.segmented)

      TextField("Full name (optional)", text: $fullName)
      #if canImport(UIKit)
        .textInputAutocapitalization(.words)
      #endif
        .autocorrectionDisabled()
        .textFieldStyle(RoundedBorderTextFieldStyle())

      if accountType == .parent {
        TextField("Parent code (from player)", text: $parentCode)
        #if canImport(UIKit)
          .textInputAutocapitalization(.characters)
        #endif
          .autocorrectionDisabled()
          .textFieldStyle(RoundedBorderTextFieldStyle())
        TextField("Relationship (optional)", text: $relationship)
        #if canImport(UIKit)
          .textInputAutocapitalization(.words)
        #endif
          .autocorrectionDisabled()
          .textFieldStyle(RoundedBorderTextFieldStyle())
        Text("Ask your child for their Parent code in Account → Family.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      if accountType == .coach {
        TextField("Coach invite code", text: $coachInviteCode)
        #if canImport(UIKit)
          .textInputAutocapitalization(.never)
        #endif
          .autocorrectionDisabled()
          .textFieldStyle(RoundedBorderTextFieldStyle())
        Text("Coach accounts require an invite code.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      passwordField
      authErrorView
      submitButton
    }
  }

  private var passwordField: some View {
    SecureField("Password", text: $password)
      .textFieldStyle(RoundedBorderTextFieldStyle())
  }

  @ViewBuilder
  private var authErrorView: some View {
    if let error = appState.authError, !error.isEmpty {
      Text(error)
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var submitButton: some View {
    Button {
      Task { await submit() }
    } label: {
      HStack {
        if isSubmitting { ProgressView().tint(.white) }
        Text(screen == .signUp ? "Create Account" : "Sign In").fontWeight(.semibold)
      }
      .frame(maxWidth: .infinity)
    }
    .buttonStyle(.borderedProminent)
    .disabled(isSubmitDisabled)
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
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.top, 6)
    }
    .font(.footnote.weight(.semibold))
    .foregroundStyle(.secondary)
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
