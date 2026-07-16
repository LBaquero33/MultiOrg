import SwiftUI

/// Template 10 — **Admin console**.
///
/// Purpose: manage an organization (or, for platform admin, organizations).
/// Anatomy: header (+ support-mode banner when applicable) → section nav →
/// managed lists (staff/roles/memberships) → feature toggles → dangerous actions.
///
/// Rules:
/// - **Platform support mode is always visually explicit** — a gold read-only
///   banner. Support ≠ ownership; never imply Stripe/owner authority.
/// - Role/permission changes are presentation only here; authorization logic is
///   untouched and remains server-authoritative.
/// - Destructive org actions are isolated and confirmed (`HPConfirmationDialog`).
struct HPAdminScreenTemplate: View {
  @Environment(\.dynamicTypeSize) private var dts

  var isWide: Bool = false
  /// Renders the explicit platform-support banner.
  var isSupportMode: Bool = false

  @State private var section = "staff"
  @State private var chatEnabled = true
  @State private var financeEnabled = true

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPWorkspaceHeader("Organization",
                          orgLabel: HPSample.orgIdentity.name,
                          context: "12 staff · 148 members",
                          identity: HPSample.orgIdentity) {
          HPButton(title: "Invite staff", systemImage: "person.badge.plus", variant: .primary, size: .sm)
        }

        if isSupportMode { supportBanner }

        HPCard {
          HPSegmentedControl(
            options: [(value: "staff", label: "Staff"),
                      (value: "members", label: "Members"),
                      (value: "features", label: "Features")],
            selection: $section
          )
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Staff & roles")
            HPTable(columns: [HPColumn(title: "Name"),
                              HPColumn(title: "Role", alignment: .trailing),
                              HPColumn(title: "Status", alignment: .trailing)],
                    rows: [HPTableRow(cells: ["A. Ramirez", "Coach", ""], badge: ("Active", .success)),
                           HPTableRow(cells: ["K. Lee", "Owner", ""], badge: ("Active", .success)),
                           HPTableRow(cells: ["T. Brooks", "Coach", ""], badge: ("Invited", .warning))],
                    layout: dts.isAccessibilitySize ? .stacked : .auto)
          }
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Features")
            Toggle("Chat", isOn: $chatEnabled)
            Toggle("Finance", isOn: $financeEnabled)
            Text("Feature flags are read from organization settings — this screen only presents them.")
              .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
              .fixedSize(horizontal: false, vertical: true)
          }
          .font(HP.Font.callout)
          .foregroundStyle(HP.Color.text)
          .tint(HP.Color.accent)
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Danger zone")
            Text("Archiving an organization hides it for every member. This cannot be undone from the app.")
              .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
              .fixedSize(horizontal: false, vertical: true)
            HPButton(title: "Archive organization", variant: .destructive, size: .md,
                     fullWidth: dts.isAccessibilitySize)
          }
        }
      }
      .padding(HP.Space.md)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(HP.Color.bg)
  }

  private var supportBanner: some View {
    HPCard {
      HStack(alignment: .top, spacing: HP.Space.sm) {
        Image(systemName: "person.badge.shield.checkmark")
          .font(.title3).foregroundStyle(HP.Color.accent)
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: HP.Space.xs) {
            Text("Platform Support").font(HP.Font.headline).foregroundStyle(HP.Color.text)
            HPStatusBadge(text: "Read-only", kind: .gold)
          }
          Text("You are viewing \(HPSample.orgIdentity.name) as platform support. This does not make you an organization owner or member.")
            .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }
    }
  }
}

#Preview("Admin — iPhone") { HPAdminScreenTemplate() }
#Preview("Admin — support mode") { HPAdminScreenTemplate(isSupportMode: true) }
#Preview("Admin — iPad/macOS") { HPAdminScreenTemplate(isWide: true, isSupportMode: true) }
