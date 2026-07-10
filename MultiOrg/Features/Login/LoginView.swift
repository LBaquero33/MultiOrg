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

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
          VStack(alignment: .leading, spacing: 6) {
            Text(DHDAppConfig.displayName)
              .font(.largeTitle.bold())
            Text("Choose your organization, then sign in or create an account.")
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          VStack(spacing: 12) {
            if orgs.isEmpty {
              HStack(spacing: 10) {
                ProgressView()
                Text("Loading organizations…")
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
              ForEach(Screen.allCases) { s in
                Text(s.rawValue).tag(s)
              }
            }
            .pickerStyle(.segmented)

            if screen == .signUp {
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
                ForEach(AccountType.allCases) { t in
                  Text(t.rawValue).tag(t)
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

                Text("Ask your child for their Parent code (Account → Family).")
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
            } else {
              TextField("Username", text: $emailOrUsername)
              #if canImport(UIKit)
                .textInputAutocapitalization(.never)
              #endif
                .autocorrectionDisabled()
                .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            SecureField("Password", text: $password)
              .textFieldStyle(RoundedBorderTextFieldStyle())

            if let err = appState.authError, !err.isEmpty {
              Text(err)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
              Task {
                isSubmitting = true
                defer { isSubmitting = false }
                guard let org = selectedOrg else {
                  appState.authError = "Pick an organization first."
                  return
                }
                if screen == .signUp {
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
                  await appState.signIn(orgSlug: org.slug, username: normalizedUsername(), password: password)
                }
              }
            } label: {
              HStack {
                if isSubmitting { ProgressView().tint(.white) }
                Text(screen == .signUp ? "Create Account" : "Sign In").fontWeight(.semibold)
              }
              .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(
              isSubmitting
              || password.isEmpty
              || selectedOrg == nil
              || (screen == .signIn && emailOrUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
              || (screen == .signUp && signUpEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
              || (screen == .signUp && signUpUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
              || (screen == .signUp && accountType == .parent && parentCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
              || (screen == .signUp && accountType == .coach && coachInviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            )

            if screen == .signIn {
              Text("or")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
              AppleSignInButtonView()
                .environmentObject(appState)
            }

            if screen == .signIn {
              Button("Forgot password?") {
                showReset = true
              }
              .font(.footnote.weight(.semibold))
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.top, 4)
            }
          }

          DisclosureGroup("Having trouble signing in?") {
            Text("This iOS app signs in using Supabase Auth (email + password). If you were previously using the Shiny app’s old “username/password” table, we can migrate those accounts or build a secure server-side login bridge. The iOS app cannot safely include database passwords.")
              .font(.footnote)
              .foregroundStyle(.secondary)
              .padding(.top, 6)
          }
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      .padding()
      .frame(maxWidth: .infinity)
      .frame(maxHeight: .infinity, alignment: .topLeading)
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
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("We’ll email a reset link if you entered a real email address.")
    }
  }

  private func loadOrgsIfNeeded() async {
    guard orgs.isEmpty else { return }
    guard let supabase = appState.supabase else { return }
    do {
      let fetched = try await supabase.listOrgs()
      orgs = fetched
      if selectedOrgId == nil {
        selectedOrgId = fetched.first?.id
      }
    } catch {
      appState.authError = error.localizedDescription
    }
  }
}
