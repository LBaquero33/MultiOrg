import SwiftUI

/// Template 5 — **Player program-execution screen**.
///
/// Canonical production example: `SDPlayerTodayView` (Stage 5B pilot, approved).
/// Purpose: do today's work with the fewest taps and the least typing.
///
/// Anatomy: `HPWorkspaceHeader` (+ Scheduled/Off + Saved/Not-logged badges) →
/// date context → improvement metrics → program + completion ring →
/// per-exercise loggers → sub-activity section → self-assessment →
/// ONE dominant gold "Submit day".
///
/// Rules:
/// - Exactly one `.primary` (Submit). Import/Add/Remove are `.secondary`.
/// - Persistence happens on Submit only — templates never imply autosave.
/// - Coach instructions are read-only and visually distinct from player input.
/// - Large tap targets; steppers over typing wherever a number is bounded.
struct HPProgramExecutionTemplate: View {
  @Environment(\.dynamicTypeSize) private var dts

  var isWide: Bool = false
  var state: HPTemplateState = .loaded

  @State private var noWeight = false
  @State private var sets = 3
  @State private var weight = "135"
  @State private var notes = ""
  @State private var feel = 8.0

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPWorkspaceHeader("Today",
                          orgLabel: HPSample.orgIdentity.name,
                          context: "Tuesday, July 14",
                          identity: HPSample.orgIdentity) {
          HStack(spacing: HP.Space.xs) {
            HPStatusBadge(text: "Scheduled", kind: .success)
            HPStatusBadge(text: "Not logged", kind: .warning)
          }
        }

        switch state {
        case .loading:
          HPCard { HPLoadingState(text: "Loading today’s program…") }
        case .empty:
          HPCard {
            HPEmptyState(title: "No program assigned",
                         message: "Your coach hasn’t assigned a program yet. You can still log a self-assessment.",
                         systemImage: "figure.strengthtraining.traditional",
                         actionTitle: "Log self-assessment",
                         actionIsPrimary: false)
          }
        case .error:
          HPCard {
            HPErrorState(message: "We couldn’t load today’s program. Check your connection and try again.",
                         onRetry: {})
          }
        case .loaded:
          programCard
          exerciseLogger
        }

        submitCard
      }
      .padding(HP.Space.md)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(HP.Color.bg)
  }

  private var programCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Strength program") {
          HPProgressIndicator(value: 0.5, style: .ring, lineWidth: 6)
            .environment(\.dynamicTypeSize, .large)
            .frame(width: 44, height: 44)
        }
        Text("Program: Rotational Power")
          .font(HP.Font.callout).foregroundStyle(HP.Color.textMuted)
        Text("Scheduled today • Week 2 Day 1")
          .font(HP.Font.headline).foregroundStyle(HP.Color.text)
        Text("2 / 4 exercises logged")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
      }
    }
  }

  private var exerciseLogger: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        Text("Log today’s lifts").font(HP.Font.headline).foregroundStyle(HP.Color.text)
        HPCard(style: .flat) {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
              Text("Back Squat").font(HP.Font.headline).foregroundStyle(HP.Color.text)
              Text("3 x 5 • lb").font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            }
            // Coach instructions — read-only, visually distinct from inputs.
            VStack(alignment: .leading, spacing: 4) {
              Text("Coach instructions")
                .font(HP.Font.eyebrow).tracking(HP.Font.eyebrowTracking)
                .foregroundStyle(HP.Color.accent)
              Text("Build to a heavy triple.")
                .font(HP.Font.callout).foregroundStyle(HP.Color.text)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(HP.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HP.Color.surfaceRaised, in: RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
              Toggle("No weight", isOn: $noWeight)
                .font(HP.Font.callout).foregroundStyle(HP.Color.text).tint(HP.Color.accent)
              Text("Use for bodyweight, jumps, or other unweighted work.")
                .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            }

            if noWeight {
              Stepper(value: $sets, in: 0...50) {
                Text("Sets completed: \(sets)")
                  .font(HP.Font.callout).foregroundStyle(HP.Color.text)
              }
            } else {
              HPFormField(label: "Set 1 weight", text: $weight, placeholder: "Weight")
              ViewThatFits(in: .horizontal) {
                HStack(spacing: HP.Space.sm) {
                  HPButton(title: "Add set", systemImage: "plus", variant: .secondary, size: .sm)
                  HPButton(title: "Remove set", systemImage: "minus", variant: .secondary, size: .sm)
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(spacing: HP.Space.xs) {
                  HPButton(title: "Add set", systemImage: "plus", variant: .secondary, size: .sm, fullWidth: true)
                  HPButton(title: "Remove set", systemImage: "minus", variant: .secondary, size: .sm, fullWidth: true)
                }
              }
            }
            HPFormField(label: "Notes (optional)", text: $notes, kind: .multiline, placeholder: "Optional")
          }
        }
      }
    }
  }

  private var submitCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPButton(title: "Submit day", variant: .primary, size: .lg, fullWidth: true)
        Text("Submitting saves your self assessment and any lift logs for today.")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
      }
    }
  }
}

#Preview("Program execution — iPhone") { HPProgramExecutionTemplate() }
#Preview("Program execution — empty") { HPProgramExecutionTemplate(state: .empty) }
