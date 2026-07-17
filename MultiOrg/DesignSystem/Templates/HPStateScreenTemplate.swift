import SwiftUI

/// Reusable centered shell for locked, offline, error, and upgrade states.
///
/// The supplied content owns its truthful copy and action callbacks. The shell
/// does not inspect entitlement, StoreKit, authentication, or connectivity.
struct HPStateScreenLayout<Content: View>: View {
  private let widthMode: HPScreenWidthMode
  private let content: (HPScreenLayoutContext) -> Content

  init(
    widthMode: HPScreenWidthMode = .automatic,
    @ViewBuilder content: @escaping (HPScreenLayoutContext) -> Content
  ) {
    self.widthMode = widthMode
    self.content = content
  }

  var body: some View {
    HPScreenScaffold(widthMode: widthMode, maxContentWidth: 560) { context in
      VStack(spacing: HP.Space.md) {
        content(context)
      }
      .frame(maxWidth: .infinity, alignment: .center)
    }
  }
}

/// Template 11 — **Permission / locked / upgrade / full-screen state**.
///
/// Covers the whole-screen state family: locked (no entitlement), paywall
/// (upgrade), offline, stale data, config error, and sign-in required.
///
/// Purpose: explain *why* the user is here and give exactly one way forward.
/// Anatomy: icon → title → one-sentence explanation → single primary action →
/// optional secondary escape → honest fine print.
///
/// Rules:
/// - Never a dead end: every state offers a next step (retry / upgrade / back).
/// - **Never** imply entitlement state the app hasn't verified — paywall copy is
///   presentation only; StoreKit/entitlement checks are untouched.
/// - Offline/stale states say when data was last updated — never silently lie.
struct HPStateScreenTemplate: View {
  enum Kind: String, CaseIterable, Identifiable {
    case locked, paywall, offline, stale, configError, signInRequired
    var id: String { rawValue }
  }

  var kind: Kind = .paywall
  var isWide: Bool = false
  var onPrimaryAction: () -> Void = {}
  var onSecondaryAction: () -> Void = {}

  init(
    kind: Kind = .paywall,
    isWide: Bool = false,
    onPrimaryAction: @escaping () -> Void = {},
    onSecondaryAction: @escaping () -> Void = {}
  ) {
    self.kind = kind
    self.isWide = isWide
    self.onPrimaryAction = onPrimaryAction
    self.onSecondaryAction = onSecondaryAction
  }

  var body: some View {
    HPStateScreenLayout(widthMode: isWide ? .automatic : .compact) { context in
      switch kind {
      case .locked:
        HPCard {
          HPEmptyState(title: "Analytics isn’t enabled",
                       message: "This organization hasn’t enabled the Analytics workspace. Your coach or admin can turn it on.",
                       systemImage: "lock",
                       actionTitle: "Back to Overview",
                       actionIsPrimary: false,
                       action: onSecondaryAction)
        }
      case .paywall:
        paywall
      case .offline:
        HPCard {
          VStack(spacing: HP.Space.sm) {
            HPEmptyState(title: "You’re offline",
                         message: "Showing the last data we downloaded. New changes won’t appear until you reconnect.",
                         systemImage: "wifi.slash",
                         actionTitle: "Retry",
                         actionIsPrimary: true,
                         action: onPrimaryAction)
            HPStatusBadge(text: "Last updated 12 min ago", kind: .warning)
          }
        }
      case .stale:
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HStack(spacing: HP.Space.xs) {
              Image(systemName: "clock.arrow.circlepath").foregroundStyle(HP.Color.warning)
              Text("Showing cached data").font(HP.Font.headline).foregroundStyle(HP.Color.text)
              Spacer(minLength: 0)
              HPStatusBadge(text: "Stale", kind: .warning)
            }
            Text("Last updated 12 minutes ago. Pull to refresh for the latest.")
              .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
              .fixedSize(horizontal: false, vertical: true)
            HPButton(title: "Refresh now", systemImage: "arrow.clockwise",
                     variant: .secondary, size: .sm,
                     fullWidth: context.isAccessibilitySize,
                     action: onPrimaryAction)
          }
        }
      case .configError:
        HPCard {
          HPErrorState(title: "App isn’t configured",
                       message: "Supabase credentials are missing from this build. Reinstall or contact support.",
                       retryTitle: "Try again",
                       onRetry: onPrimaryAction)
        }
      case .signInRequired:
        HPCard {
          HPEmptyState(title: "Sign in to continue",
                       message: "Your session expired. Sign in again to pick up where you left off.",
                       systemImage: "person.crop.circle.badge.exclamationmark",
                       actionTitle: "Sign in",
                       actionIsPrimary: true,
                       action: onPrimaryAction)
        }
      }
    }
  }

  private var paywall: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        VStack(alignment: .leading, spacing: HP.Space.xs) {
          Image(systemName: "sparkles")
            .font(.system(size: 30)).foregroundStyle(HP.Color.accent)
          Text("Unlock Player Access")
            .font(HP.Font.title).tracking(HP.Font.titleTracking)
            .foregroundStyle(HP.Color.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
          Text("Your daily program, testing history, and trends — updated by your coach.")
            .font(HP.Font.callout).foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }

        VStack(alignment: .leading, spacing: HP.Space.xs) {
          benefit("Today’s assigned program")
          benefit("Strength + hitting logging")
          benefit("Improvement trends and testing history")
        }

        HPCard(style: .flat) {
          VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
              Text("$19").font(HP.Font.number(.title, weight: .bold)).foregroundStyle(HP.Color.text)
              Text("/ month").font(HP.Font.callout).foregroundStyle(HP.Color.textMuted)
            }
            Text("Cancel anytime in the App Store.")
              .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
          }
        }

        HPButton(title: "Subscribe", variant: .primary, size: .lg,
                 fullWidth: true, action: onPrimaryAction)
        HPButton(title: "Restore purchases", variant: .tertiary, size: .sm,
                 fullWidth: true, action: onSecondaryAction)

        Text("Billed through the App Store. Access is granted only after Apple confirms the purchase.")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func benefit(_ text: String) -> some View {
    HStack(alignment: .top, spacing: HP.Space.xs) {
      Image(systemName: "checkmark.circle.fill").foregroundStyle(HP.Color.success)
      Text(text).font(HP.Font.callout).foregroundStyle(HP.Color.text)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
  }
}

#Preview("State — paywall") { HPStateScreenTemplate(kind: .paywall) }
#Preview("State — locked") { HPStateScreenTemplate(kind: .locked) }
#Preview("State — offline") { HPStateScreenTemplate(kind: .offline) }
