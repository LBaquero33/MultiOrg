import SwiftUI

/// Reusable presentation shell for account and settings surfaces.
///
/// The caller supplies identity, sections, bindings, and callbacks. The shell
/// guarantees a single 720-point column and keeps the destructive action last
/// in its own card, without interpreting subscription or entitlement state.
struct HPSettingsScreenLayout<Header: View, Sections: View, DestructiveAction: View>: View {
  private let widthMode: HPScreenWidthMode
  private let header: (HPScreenLayoutContext) -> Header
  private let sections: (HPScreenLayoutContext) -> Sections
  private let destructiveAction: (HPScreenLayoutContext) -> DestructiveAction

  init(
    widthMode: HPScreenWidthMode = .automatic,
    @ViewBuilder header: @escaping (HPScreenLayoutContext) -> Header,
    @ViewBuilder sections: @escaping (HPScreenLayoutContext) -> Sections,
    @ViewBuilder destructiveAction: @escaping (HPScreenLayoutContext) -> DestructiveAction
  ) {
    self.widthMode = widthMode
    self.header = header
    self.sections = sections
    self.destructiveAction = destructiveAction
  }

  var body: some View {
    HPScreenScaffold(widthMode: widthMode, maxContentWidth: 720) { context in
      VStack(alignment: .leading, spacing: HP.Space.md) {
        header(context)
        sections(context)
        HPCard {
          destructiveAction(context)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }
}

/// Template 9 — **Settings / account screen**.
///
/// Purpose: identity, org switching, preferences, subscription, sign out.
/// Anatomy: identity card → grouped setting sections → subscription/billing →
/// destructive actions last.
///
/// Rules:
/// - Destructive actions (Sign out / Delete) live at the bottom, use
///   `.destructive`, and are never adjacent to a `.primary`.
/// - Subscription surfaces are **presentation only** — never touch StoreKit
///   verification or entitlement logic.
/// - Settings is single-column at every width (a settings grid is an anti-pattern).
struct HPSettingsScreenTemplate: View {
  var isWide: Bool = false

  @State private var pushEnabled = true
  @State private var emailEnabled = false

  var body: some View {
    HPSettingsScreenLayout(widthMode: isWide ? .automatic : .compact) { _ in
      HPWorkspaceHeader("Account",
                        orgLabel: HPSample.orgIdentity.name,
                        context: "jose@example.com",
                        identity: HPSample.orgIdentity)
    } sections: { context in
      HPCard {
        HStack(spacing: HP.Space.md) {
          HPAvatar(name: "Jose Alvarez", size: .lg, tint: HPSample.orgIdentity.primary)
          VStack(alignment: .leading, spacing: 2) {
            Text("Jose Alvarez").font(HP.Font.headline).foregroundStyle(HP.Color.text)
            Text("Player · 14U National").font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
          }
          Spacer(minLength: 0)
        }
      }

      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Organization")
          HPStatTile(label: "Active organization", value: HPSample.orgIdentity.shortName, systemImage: "building.2")
          HPButton(title: "Switch organization", variant: .secondary, size: .sm,
                   fullWidth: context.isAccessibilitySize)
        }
      }

      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Notifications")
          Toggle("Push notifications", isOn: $pushEnabled)
          Toggle("Email summaries", isOn: $emailEnabled)
        }
        .font(HP.Font.callout)
        .foregroundStyle(HP.Color.text)
        .tint(HP.Color.accent)
      }

      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Subscription") {
            HPStatusBadge(text: "Active", kind: .success)
          }
          HPStatTile(label: "Plan", value: "Player Access · $19/mo")
          HPStatTile(label: "Renews", value: "Aug 14, 2026")
          Text("Managed by the App Store. Presentation only — entitlement state is authoritative.")
            .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
          HPButton(title: "Manage subscription", variant: .secondary, size: .sm,
                   fullWidth: context.isAccessibilitySize)
        }
      }
    } destructiveAction: { _ in
      HPButton(title: "Sign out", systemImage: "rectangle.portrait.and.arrow.right",
               variant: .destructive, size: .md, fullWidth: true)
    }
  }
}

#Preview("Settings — iPhone") { HPSettingsScreenTemplate() }
#Preview("Settings — iPad/macOS") { HPSettingsScreenTemplate(isWide: true) }
