import SwiftUI

struct OnboardingWizardView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appState: AppState

  enum Mode {
    case required
    case edit
  }

  let mode: Mode

  @State private var step: Int = 1
  @State private var improveFocus: String = ""
  @State private var improvePlan: String = ""
  @State private var dailyGoals: String = ""
  @State private var isWorking = false
  @State private var errorText: String?

  private let focusOptions: [String] = [
    "Exit Velocity",
    "Launch Angle",
    "Improve contact rate",
    "Have better at-bats",
    "Lose Weight",
    "Gain Weight",
    "Get Stronger"
  ]

  var body: some View {
    NavigationStack {
      VStack(spacing: 18) {
        ProgressView(value: Double(step), total: 3)
          .padding(.top, 6)

        Group {
          switch step {
          case 1:
            step1
          case 2:
            step2
          default:
            step3
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Spacer()

        HStack(spacing: 12) {
          if step > 1 {
            Button("Back") { step -= 1 }
              .buttonStyle(.bordered)
          }

          Spacer()

          Button {
            Task { await nextOrFinish() }
          } label: {
            if isWorking {
              ProgressView()
            } else {
              Text(step == 3 ? "Finish" : "Next").fontWeight(.semibold)
            }
          }
          .buttonStyle(.borderedProminent)
          .disabled(isWorking || (step == 1 && improveFocus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
        }
      }
      .padding()
      .navigationTitle("Onboarding")
      #if !os(macOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        if mode == .edit {
          ToolbarItem(placement: .cancellationAction) {
            Button("Close") { dismiss() }
          }
        }
      }
      .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorText ?? "")
      }
      .task {
        await preloadIfAny()
      }
    }
  }

  private var step1: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("What are you looking to improve on?")
        .font(.title3.weight(.semibold))
      Picker("Improve focus", selection: $improveFocus) {
        Text("Select…").tag("")
        ForEach(focusOptions, id: \.self) { opt in
          Text(opt).tag(opt)
        }
      }
      .pickerStyle(.menu)
    }
  }

  private var step2: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("How are you going to get there?")
        .font(.title3.weight(.semibold))
      TextEditor(text: $improvePlan)
        .frame(minHeight: 160)
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .stroke(separatorColor, lineWidth: 1)
        )
    }
  }

  private var step3: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("What are YOUR daily goals?")
        .font(.title3.weight(.semibold))
      TextEditor(text: $dailyGoals)
        .frame(minHeight: 160)
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .stroke(separatorColor, lineWidth: 1)
        )
    }
  }

  private var separatorColor: Color {
  #if canImport(UIKit)
    return Color(uiColor: .separator)
  #elseif canImport(AppKit)
    return Color(nsColor: .separatorColor)
  #else
    return Color.gray.opacity(0.35)
  #endif
  }

  private func preloadIfAny() async {
    guard let supabase = appState.supabase else { return }
    do {
      let session = try await supabase.client.auth.session
      let uid = session.user.id
      if let existing = try await supabase.fetchOnboarding(playerId: uid) {
        improveFocus = existing.improve_focus
        improvePlan = existing.improve_plan ?? ""
        dailyGoals = existing.daily_goals ?? ""
      }
    } catch {
      // Non-fatal; wizard still works without preload.
    }
  }

  private func nextOrFinish() async {
    if step < 3 {
      step += 1
      return
    }

    guard let supabase = appState.supabase else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      let session = try await supabase.client.auth.session
      let uid = session.user.id

      let focus = improveFocus.trimmingCharacters(in: .whitespacesAndNewlines)
      let plan = improvePlan.trimmingCharacters(in: .whitespacesAndNewlines)
      let goals = dailyGoals.trimmingCharacters(in: .whitespacesAndNewlines)

      _ = try await supabase.upsertOnboarding(
        playerId: uid,
        improveFocus: focus,
        improvePlan: plan.isEmpty ? nil : plan,
        dailyGoals: goals.isEmpty ? nil : goals,
        completed: true,
        orgId: appState.activeOrgId
      )
      // Refresh caller state (best-effort).
      await appState.refreshOnboarding()
      dismiss()
    } catch {
      errorText = error.localizedDescription
    }
  }
}
