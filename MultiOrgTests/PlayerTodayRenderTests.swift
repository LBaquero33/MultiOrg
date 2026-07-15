import XCTest
import SwiftUI
@testable import MultiOrg
#if canImport(UIKit)
import UIKit
#endif

/// EVIDENCE-ONLY, TEST-ONLY render harness for the Player "Today" (Program Day
/// Execution) pilot — Stage 5B.
///
/// The production `SDPlayerTodayView` interleaves presentation with live
/// `AppState`/Supabase data, so it can't be rendered headlessly. Instead this
/// harness composes the **reskinned presentation** with representative local
/// **mock model data** — no network, no `AppState`, not wired to production
/// navigation. It renders the genuine reskinned subviews (`StrengthExerciseLogger`,
/// `ImprovementTile`, `ProgressRing`) alongside the same Home Plate components
/// (`HPWorkspaceHeader`/`HPCard`/`HPSectionHeader`/`HPButton`/`HPStatusBadge`/
/// `HPFormField`/`HPSegmentedControl`/`HPStatTile`/`HPToast`/`HPLoadingState`/
/// `HPErrorState`) used by the production screen.
///
/// Captures via a real `UIWindow` + `drawHierarchy(afterScreenUpdates:)` so the
/// live editable fields (strength weight/notes `TextField`s) rasterize correctly
/// (a headless `ImageRenderer` shows a yellow prohibited glyph for those).
///
/// Split into several short test methods so each stays well under the per-test
/// execution timeout. Safe to delete.
@MainActor
final class PlayerTodayRenderTests: XCTestCase {
  #if canImport(UIKit)
  private struct Spec {
    let name: String
    let width: CGFloat
    let dts: DynamicTypeSize
    let state: PlayerTodayHarness.State
  }

  func testRenderPlayerPrograms() throws {
    try render([
      Spec(name: "iphone-strength-hitting",     width: 393, dts: .large,          state: .strengthAndHitting),
      Spec(name: "iphone-coach-instructions",   width: 393, dts: .large,          state: .coachInstructions),
      Spec(name: "iphone-partial",              width: 393, dts: .large,          state: .partiallyCompleted),
      Spec(name: "ipad-strength-hitting",       width: 834, dts: .large,          state: .strengthAndHitting),
    ])
  }

  func testRenderPlayerCompletion() throws {
    try render([
      Spec(name: "iphone-complete",             width: 393, dts: .large,          state: .fullyCompleted),
      Spec(name: "iphone-submit-ready",         width: 393, dts: .large,          state: .submitReady),
      Spec(name: "iphone-submit-success",       width: 393, dts: .large,          state: .submissionSuccess),
      Spec(name: "ipad-complete",               width: 834, dts: .large,          state: .fullyCompleted),
    ])
  }

  func testRenderPlayerStates() throws {
    try render([
      Spec(name: "iphone-no-program",           width: 393, dts: .large,          state: .noProgram),
      Spec(name: "iphone-loading",              width: 393, dts: .large,          state: .loading),
      Spec(name: "iphone-error",                width: 393, dts: .large,          state: .error),
    ])
  }

  func testRenderPlayerAccessibility() throws {
    try render([
      Spec(name: "iphone-ax3-strength-hitting", width: 393, dts: .accessibility3, state: .strengthAndHitting),
      Spec(name: "iphone-ax3-submit-ready",     width: 393, dts: .accessibility3, state: .submitReady),
    ])
  }

  private func render(_ specs: [Spec]) throws {
    let dir = FileManager.default.temporaryDirectory

    for spec in specs {
      try autoreleasepool {
        // Accessibility renders are very tall; use 1x there to stay within the
        // simulator's memory budget when this runs inside the full test suite.
        let format = UIGraphicsImageRendererFormat()
        format.scale = spec.dts.isAccessibilitySize ? 1 : 2

        let view = PlayerTodayHarness(state: spec.state)
          .environment(\.dynamicTypeSize, spec.dts)
          .frame(width: spec.width)
          .background(HP.Color.bg)
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = .dark
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: spec.width, height: 2000))
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let fitted = host.sizeThatFits(in: CGSize(width: spec.width, height: .greatestFiniteMagnitude))
        window.frame = CGRect(x: 0, y: 0, width: spec.width, height: ceil(fitted.height))
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        // Editable fields (weight / notes TextFields) need drawHierarchy to
        // rasterize their live content correctly.
        let renderer = UIGraphicsImageRenderer(size: host.view.bounds.size, format: format)
        let image = renderer.image { _ in
          host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let url = dir.appendingPathComponent("player-\(spec.name).png")
        if let data = image.pngData() { try data.write(to: url) }
        print("PLAYER_PNG \(url.path) size=\(Int(host.view.bounds.width))x\(Int(host.view.bounds.height))")

        window.isHidden = true
        window.rootViewController = nil
      }
    }
  }
  #else
  func testRenderPlayerPrograms() throws { throw XCTSkip("UIKit required") }
  #endif
}

#if canImport(UIKit)
/// Test-only host composing the reskinned "Today" presentation with mock data.
/// Mirrors the production card order: header → improvement → program →
/// strength → BP → self-assessment → submit, varying content per state.
struct PlayerTodayHarness: View {
  enum State {
    case strengthAndHitting   // assigned program with strength + hitting (BP)
    case coachInstructions    // scheduled program emphasizing coach instructions
    case partiallyCompleted   // some exercises logged
    case fullyCompleted       // all exercises logged, day saved
    case noProgram            // no active program assigned
    case loading              // initial load in progress
    case error                // fetch error presentation
    case submitReady          // filled in, ready to submit
    case submissionSuccess    // just submitted — success toast visible
  }

  let state: State

  var body: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      header
      improvement
      program
      if isScheduled { strength }
      bp
      selfAssessment
      submit
    }
    .padding(HP.Space.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(HP.Color.bg)
    .overlay(alignment: .top) {
      if state == .submissionSuccess {
        HPToast(text: "Saved.")
          .padding(.top, HP.Space.md)
      }
    }
  }

  // MARK: Derived state

  private var isScheduled: Bool {
    switch state {
    case .noProgram, .loading: return false
    default: return true
    }
  }

  private var isDaySaved: Bool {
    switch state {
    case .fullyCompleted, .partiallyCompleted, .submissionSuccess: return true
    default: return false
    }
  }

  // MARK: Cards (mirror the reskinned production builders)

  private var header: some View {
    VStack(alignment: .leading, spacing: HP.Space.sm) {
      HPWorkspaceHeader("Today", context: "Tuesday, July 14") {
        HStack(spacing: HP.Space.xs) {
          HPStatusBadge(text: isScheduled ? "Scheduled" : "Off day",
                        kind: isScheduled ? .success : .neutral)
          HPStatusBadge(text: isDaySaved ? "Saved" : "Not logged",
                        kind: isDaySaved ? .success : .warning)
        }
      }
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HStack(alignment: .firstTextBaseline, spacing: HP.Space.sm) {
            Text("Viewing").font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            DatePicker("", selection: .constant(PlayerMock.date), displayedComponents: .date)
              .datePickerStyle(.compact).labelsHidden().tint(HP.Color.accent)
            Spacer(minLength: 0)
          }
          Text("Tap the date to view a different day.")
            .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
          if state == .loading {
            HPLoadingState()
          }
        }
      }
    }
  }

  @ViewBuilder private var improvement: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Improvement")
        if state == .noProgram || state == .loading {
          Text("Add your first Testing entry to see improvement trends.")
            .font(HP.Font.callout).foregroundStyle(HP.Color.textMuted)
        } else {
          HStack(spacing: HP.Space.sm) {
            ImprovementTile(title: "Latest test", value: "2026-07-10", delta: nil)
            ImprovementTile(title: "Max EV", value: "88.4", delta: "+2.3 mph")
          }
          HStack(spacing: HP.Space.sm) {
            ImprovementTile(title: "Avg EV", value: "81.2", delta: "−1 mph")
            ImprovementTile(title: "Strength total", value: "915", delta: "+35 lb")
          }
        }
      }
    }
  }

  @ViewBuilder private var program: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Strength program") {
          if isScheduled {
            ProgressRing(progress: progressFraction).frame(width: 44, height: 44)
          }
        }
        switch state {
        case .noProgram:
          Text("No active program assigned yet.")
            .font(HP.Font.callout).foregroundStyle(HP.Color.textMuted)
        case .loading:
          Text("Program: Summer Strength — Phase 2")
            .font(HP.Font.callout).foregroundStyle(HP.Color.textMuted)
        default:
          Text("Program: Summer Strength — Phase 2")
            .font(HP.Font.callout).foregroundStyle(HP.Color.textMuted)
          Text("Scheduled today • Week 2 Day 1")
            .font(HP.Font.headline).foregroundStyle(HP.Color.text)
          Text(progressSubtitle)
            .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        }
      }
    }
  }

  @ViewBuilder private var strength: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        Text("Log today’s lifts").font(HP.Font.headline).foregroundStyle(HP.Color.text)
        ForEach(Array(PlayerMock.exercises.enumerated()), id: \.offset) { idx, ex in
          StrengthExerciseLogger(
            exercise: ex,
            weights: .constant(weights(for: idx)),
            noWeight: .constant(ex.unit == "bw"),
            setsCompleted: .constant(setsCompleted(for: idx, ex: ex)),
            notes: .constant(notes(for: idx))
          )
        }
      }
    }
  }

  @ViewBuilder private var bp: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        Text("Hitting (BP)").font(HP.Font.headline).foregroundStyle(HP.Color.text)
        if state == .strengthAndHitting || state == .fullyCompleted || state == .submitReady || state == .submissionSuccess {
          VStack(alignment: .leading, spacing: 6) {
            Text("Reps type").font(HP.Font.eyebrow).tracking(HP.Font.eyebrowTracking).foregroundStyle(HP.Color.textMuted)
            HPSegmentedControl(options: [(value: "practice", label: "Practice"), (value: "game", label: "Game")],
                               selection: .constant("practice"))
          }
          VStack(alignment: .leading, spacing: 6) {
            Text("Upload type").font(HP.Font.eyebrow).tracking(HP.Font.eyebrowTracking).foregroundStyle(HP.Color.textMuted)
            HPSegmentedControl(options: BPImportSource.allCases.map { (value: $0.rawValue, label: $0.label) },
                               selection: .constant("rapsodo"))
          }
          HPButton(title: "Import CSV", systemImage: "square.and.arrow.down", variant: .secondary, size: .md) {}
          VStack(alignment: .leading, spacing: 4) {
            HPStatTile(label: "Events", value: "24")
            HPStatTile(label: "Max EV", value: "93 mph")
            HPStatTile(label: "Avg EV", value: "81.6 mph")
          }
        } else {
          Text("BP details stay hidden on off days.")
            .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        }
      }
    }
  }

  @ViewBuilder private var selfAssessment: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        Text("Self assessment").font(HP.Font.headline).foregroundStyle(HP.Color.text)
        Toggle("Did I get video today?", isOn: .constant(filledForms))
        Toggle("Did I eat breakfast?", isOn: .constant(filledForms))
        Toggle("Did I hit my daily goals?", isOn: .constant(filledForms))
        Toggle("Did I stick to my process?", isOn: .constant(false))
        HPFormField(label: "Where did I fall short? (optional)",
                    text: .constant(filledForms ? "Rushed my warmup." : ""),
                    kind: .multiline, placeholder: "Optional")
        HPFormField(label: "How did I excel? (optional)",
                    text: .constant(filledForms ? "Stayed on my process between sets." : ""),
                    kind: .multiline, placeholder: "Optional")
        if isScheduled {
          HPFormField(label: "Comments (optional)",
                      text: .constant(filledForms ? "Felt strong on squats." : ""),
                      kind: .multiline, placeholder: "Optional")
          VStack(alignment: .leading, spacing: 6) {
            Text("How did you feel? (\(filledForms ? 8 : 5))")
              .font(HP.Font.caption.weight(.semibold)).foregroundStyle(HP.Color.textMuted)
            Slider(value: .constant(filledForms ? 8 : 5), in: 1...10, step: 1).tint(HP.Color.accent)
          }
        }
      }
      .font(HP.Font.callout)
      .foregroundStyle(HP.Color.text)
      .tint(HP.Color.accent)
    }
  }

  @ViewBuilder private var submit: some View {
    if state == .error {
      HPCard {
        HPErrorState(message: "We couldn’t load today’s program. Check your connection and try again.", onRetry: {})
      }
    } else {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPButton(title: "Submit day", variant: .primary, size: .lg,
                   isLoading: false, fullWidth: true) {}
          Text(isScheduled
               ? "Submitting saves your self assessment and any lift logs for today."
               : "Submitting saves your self assessment for today.")
            .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        }
      }
    }
  }

  // MARK: Mock-content helpers

  private var filledForms: Bool {
    switch state {
    case .submitReady, .fullyCompleted, .submissionSuccess: return true
    default: return false
    }
  }

  private var progressFraction: Double {
    switch state {
    case .fullyCompleted, .submitReady, .submissionSuccess: return 1
    case .partiallyCompleted: return 0.5
    case .coachInstructions: return 0
    default: return 0
    }
  }

  private var progressSubtitle: String {
    switch state {
    case .fullyCompleted, .submitReady, .submissionSuccess: return "4 / 4 exercises logged"
    case .partiallyCompleted: return "2 / 4 exercises logged"
    default: return "0 / 4 exercises logged"
    }
  }

  private func weights(for idx: Int) -> [String] {
    let ex = PlayerMock.exercises[idx]
    let n = max(0, ex.sets ?? 0)
    guard ex.unit != "bw" else { return [] }
    let logged: Bool
    switch state {
    case .fullyCompleted, .submitReady, .submissionSuccess: logged = true
    case .partiallyCompleted: logged = idx < 2
    default: logged = false
    }
    return logged ? Array(repeating: "135", count: n) : Array(repeating: "", count: n)
  }

  private func setsCompleted(for idx: Int, ex: SDExercise) -> Int {
    guard ex.unit == "bw" else { return ex.sets ?? 0 }
    switch state {
    case .fullyCompleted, .submitReady, .submissionSuccess: return ex.sets ?? 0
    default: return 0
    }
  }

  private func notes(for idx: Int) -> String {
    guard state == .coachInstructions else { return "" }
    return idx == 0 ? "Focus on bar speed out of the hole." : ""
  }
}

/// Local mock program/testing data (no network).
enum PlayerMock {
  static let date = Calendar(identifier: .gregorian)
    .date(from: DateComponents(year: 2026, month: 7, day: 14)) ?? Date()

  static let exercises: [SDExercise] = [
    SDExercise(name: "Back Squat", sets: 3, reps: "5", unit: "lb", notes: "Build to a heavy triple."),
    SDExercise(name: "Bench Press", sets: 3, reps: "5", unit: "lb", notes: "Pause each rep."),
    SDExercise(name: "Romanian Deadlift", sets: 3, reps: "8", unit: "lb", notes: "Controlled eccentric."),
    SDExercise(name: "Box Jumps", sets: 4, reps: "3", unit: "bw", notes: "Max height, soft landing."),
  ]
}
#endif
