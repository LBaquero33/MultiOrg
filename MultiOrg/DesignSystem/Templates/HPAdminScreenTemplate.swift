import SwiftUI

/// Explicit presentation context for platform-support viewing.
///
/// This value is visual context only. It does not confer membership,
/// authorization, billing authority, or permission to mutate anything.
struct HPAdminSupportContext: Equatable, Sendable {
  let organizationName: String
  var message: String? = nil

  var resolvedMessage: String {
    message ?? "You are viewing \(organizationName) as platform support. This does not make you an organization owner or member."
  }
}

/// Reusable presentation shell for organization and platform administration.
///
/// The caller owns section selection, authorization, disabled state, mutation
/// callbacks, and confirmation state. This layout only orders the header,
/// explicit support context, section navigation, managed content, and isolated
/// danger-zone slot.
struct HPAdminScreenLayout<Header: View, SectionNavigation: View, Content: View, DangerZone: View>: View {
  private let widthMode: HPScreenWidthMode
  private let supportContext: HPAdminSupportContext?
  private let header: (HPScreenLayoutContext) -> Header
  private let sectionNavigation: (HPScreenLayoutContext) -> SectionNavigation
  private let content: (HPScreenLayoutContext) -> Content
  private let dangerZone: (HPScreenLayoutContext) -> DangerZone

  init(
    widthMode: HPScreenWidthMode = .automatic,
    supportContext: HPAdminSupportContext? = nil,
    @ViewBuilder header: @escaping (HPScreenLayoutContext) -> Header,
    @ViewBuilder sectionNavigation: @escaping (HPScreenLayoutContext) -> SectionNavigation,
    @ViewBuilder content: @escaping (HPScreenLayoutContext) -> Content,
    @ViewBuilder dangerZone: @escaping (HPScreenLayoutContext) -> DangerZone
  ) {
    self.widthMode = widthMode
    self.supportContext = supportContext
    self.header = header
    self.sectionNavigation = sectionNavigation
    self.content = content
    self.dangerZone = dangerZone
  }

  var body: some View {
    HPScreenScaffold(widthMode: widthMode) { context in
      VStack(alignment: .leading, spacing: HP.Space.md) {
        header(context)
        if let supportContext {
          supportBanner(supportContext)
        }
        sectionNavigation(context)
        content(context)
        dangerZone(context)
      }
    }
  }

  private func supportBanner(_ support: HPAdminSupportContext) -> some View {
    HPCard {
      HStack(alignment: .top, spacing: HP.Space.sm) {
        Image(systemName: "person.badge.shield.checkmark")
          .font(.title3)
          .foregroundStyle(HP.Color.accent)
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: HP.Space.xs) {
            Text("Platform Support")
              .font(HP.Font.headline)
              .foregroundStyle(HP.Color.text)
            HPStatusBadge(text: "Read-only", kind: .gold)
          }
          Text(support.resolvedMessage)
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }
    }
  }
}

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
  var isWide: Bool = false
  /// Renders the explicit platform-support banner.
  var isSupportMode: Bool = false

  @State private var section = "staff"
  @State private var chatEnabled = true
  @State private var financeEnabled = true
  @State private var showsArchiveConfirmation = false

  var body: some View {
    HPAdminScreenLayout(
      widthMode: isWide ? .automatic : .compact,
      supportContext: isSupportMode
        ? HPAdminSupportContext(organizationName: HPSample.orgIdentity.name)
        : nil
    ) { _ in
      HPWorkspaceHeader("Organization",
                        orgLabel: HPSample.orgIdentity.name,
                        context: "12 staff · 148 members",
                        identity: HPSample.orgIdentity) {
        if !isSupportMode {
          HPButton(title: "Invite staff", systemImage: "person.badge.plus",
                   variant: .primary, size: .sm)
        }
      }
    } sectionNavigation: { _ in
      HPCard {
        HPSegmentedControl(
          options: [(value: "staff", label: "Staff"),
                    (value: "members", label: "Members"),
                    (value: "features", label: "Features")],
          selection: $section
        )
      }
    } content: { context in
      sectionContent(context)
    } dangerZone: { context in
      if !isSupportMode {
        dangerZone(context)
      }
    }
    .hpModal(isPresented: $showsArchiveConfirmation) {
      HPConfirmationDialog(
        title: "Archive organization?",
        message: "Archiving hides this organization for every member. This cannot be undone from the app.",
        confirmTitle: "Archive organization",
        destructive: true,
        onConfirm: { showsArchiveConfirmation = false },
        onCancel: { showsArchiveConfirmation = false }
      )
    }
  }

  @ViewBuilder
  private func sectionContent(_ context: HPScreenLayoutContext) -> some View {
    switch section {
    case "members":
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Organization members")
          HPTable(
            columns: [
              HPColumn(title: "Name"),
              HPColumn(title: "Role", alignment: .trailing),
              HPColumn(title: "Status", alignment: .trailing),
            ],
            rows: [
              HPTableRow(cells: ["Jose Alvarez", "Player", ""], badge: ("Active", .success)),
              HPTableRow(cells: ["Maya Alvarez", "Parent", ""], badge: ("Active", .success)),
              HPTableRow(cells: ["N. Patel", "Player", ""], badge: ("Invited", .warning)),
            ],
            layout: context.tableLayout
          )
        }
      }
    case "features":
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Features")
          Toggle("Chat", isOn: $chatEnabled)
          Toggle("Finance", isOn: $financeEnabled)
          Text(isSupportMode
               ? "Feature settings are read-only in platform support mode."
               : "Feature flags are read from organization settings — this screen only presents them.")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .font(HP.Font.callout)
        .foregroundStyle(HP.Color.text)
        .tint(HP.Color.accent)
        .disabled(isSupportMode)
      }
    default:
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Staff & roles")
          HPTable(
            columns: [
              HPColumn(title: "Name"),
              HPColumn(title: "Role", alignment: .trailing),
              HPColumn(title: "Status", alignment: .trailing),
            ],
            rows: [
              HPTableRow(cells: ["A. Ramirez", "Coach", ""], badge: ("Active", .success)),
              HPTableRow(cells: ["K. Lee", "Owner", ""], badge: ("Active", .success)),
              HPTableRow(cells: ["T. Brooks", "Coach", ""], badge: ("Invited", .warning)),
            ],
            layout: context.tableLayout
          )
        }
      }
    }
  }

  private func dangerZone(_ context: HPScreenLayoutContext) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Danger zone")
        Text("Archiving an organization hides it for every member. This cannot be undone from the app.")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
        HPButton(title: "Archive organization", variant: .destructive, size: .md,
                 fullWidth: context.isAccessibilitySize) {
          showsArchiveConfirmation = true
        }
      }
    }
  }
}

#Preview("Admin — iPhone") { HPAdminScreenTemplate() }
#Preview("Admin — support mode") { HPAdminScreenTemplate(isSupportMode: true) }
#Preview("Admin — iPad/macOS") { HPAdminScreenTemplate(isWide: true, isSupportMode: true) }
