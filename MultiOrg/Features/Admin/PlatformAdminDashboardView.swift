import SwiftUI

@MainActor
final class PlatformOrganizationCreationWorkflow: ObservableObject {
  @Published var isPresented = false
  @Published private(set) var isSubmitting = false
  @Published private(set) var errorText: String?
  @Published private(set) var successText: String?

  func present() {
    guard !isSubmitting else { return }
    errorText = nil
    successText = nil
    isPresented = true
  }

  func dismiss() {
    guard !isSubmitting else { return }
    isPresented = false
    errorText = nil
  }

  @discardableResult
  func submit(
    draft: PlatformOrganizationCreateDraft,
    create: (PlatformOrganizationCreateDraft) async throws -> SDPlatformOrganization,
    refresh: () async -> Void,
    errorMessage: (Error) -> String
  ) async -> SDPlatformOrganization? {
    guard !isSubmitting else { return nil }
    guard draft.isValid else {
      errorText = "Enter a name, a valid slug, and a positive optional member limit."
      return nil
    }

    isSubmitting = true
    errorText = nil
    defer { isSubmitting = false }
    do {
      let organization = try await create(draft)
      await refresh()
      successText = "\(organization.name) was created."
      isPresented = false
      return organization
    } catch {
      errorText = errorMessage(error)
      isPresented = true
      return nil
    }
  }
}

/// Platform-wide controls. This is intentionally separate from Org Admin:
/// it spans every organization and is only exposed after server authorization.
struct PlatformAdminDashboardView: View {
  @EnvironmentObject private var appState: AppState
  @State private var dashboard: SDPlatformDashboard?
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var toastText: String?
  @State private var editingOrganization: PlatformOrganizationDraft?
  @State private var organizationSearch = ""
  @State private var selectedOrganizationId: UUID?
  @State private var members: [SDPlatformMember] = []
  @State private var memberSearch = ""
  @State private var memberFilter: SDPlatformMemberFilter = .all
  @State private var isLoadingMembers = false
  @State private var editingMember: PlatformMembershipEditDraft?
  @State private var userSearch = ""
  @State private var userResults: [SDPlatformUserDirectoryEntry] = []
  @State private var isSearchingUsers = false
  @State private var platformAdministrators: [SDPlatformAdministrator] = []
  @State private var platformFeatureFlags: [SDPlatformFeatureFlag] = []
  @State private var platformFeatureMutationKey: String?
  @State private var auditEntries: [SDPlatformAuditEntry] = []
  @State private var pendingPlatformAdminChange: PlatformAdministratorChange?
  @StateObject private var creationWorkflow = PlatformOrganizationCreationWorkflow()

  var body: some View {
    Group {
      if appState.isPlatformAdmin {
        HPAdminScreenLayout(
          supportContext: HPAdminSupportContext(
            organizationName: "all organizations",
            message: "Platform support does not grant organization membership or ownership. Platform-authorized changes here are separately authenticated and audited by the backend."
          )
        ) { _ in
          HPWorkspaceHeader(
            "Platform Admin",
            orgLabel: "Home Plate Platform",
            context: "Organizations, access, and billing health across MultiOrg."
          ) {
            HPButton(
              title: "New Organization",
              systemImage: "plus",
              variant: .primary,
              size: .md,
              action: { creationWorkflow.present() }
            )
          }
        } sectionNavigation: { context in
          refreshCard(context)
        } content: { context in
          dashboardContent(context)
        } dangerZone: { _ in
          EmptyView()
        }
      } else {
        HPScreenScaffold(maxContentWidth: 560) { _ in
          HPCard {
            HPEmptyState(
              title: "Platform Administration forbidden",
              message: "This workspace requires a server-authorized Home Plate platform administrator entitlement.",
              systemImage: "lock.shield"
            )
          }
        }
      }
    }
    .hpToast($toastText)
    .navigationTitle("Platform Admin")
    .alert("Platform Admin", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .sheet(item: $editingOrganization) { draft in
      PlatformOrganizationEditor(draft: draft) { updated in
        Task { await save(updated) }
      }
      #if os(macOS)
      .frame(minWidth: 520, minHeight: 430)
      #endif
    }
    .sheet(item: $editingMember) { draft in
      PlatformMembershipEditor(draft: draft) { update in
        Task { await applyMembershipUpdate(update) }
      }
      #if os(macOS)
      .frame(minWidth: 520, minHeight: 470)
      #endif
    }
    .sheet(isPresented: $creationWorkflow.isPresented, onDismiss: {
      creationWorkflow.dismiss()
    }) {
      PlatformOrganizationCreateEditor(
        isSubmitting: creationWorkflow.isSubmitting,
        errorText: creationWorkflow.errorText
      ) { draft in
        Task { await create(draft) }
      }
      #if os(macOS)
      .frame(minWidth: 520, minHeight: 430)
      #endif
    }
    .confirmationDialog(
      "Confirm Platform Administrator Change",
      isPresented: Binding(
        get: { pendingPlatformAdminChange != nil },
        set: { if !$0 { pendingPlatformAdminChange = nil } }
      ),
      titleVisibility: .visible
    ) {
      if let change = pendingPlatformAdminChange {
        Button(change.granted ? "Grant Platform Admin" : "Revoke Platform Admin", role: change.granted ? nil : .destructive) {
          Task { await applyPlatformAdministratorChange(change) }
        }
      }
      Button("Cancel", role: .cancel) { pendingPlatformAdminChange = nil }
    } message: {
      Text("This is a platform-wide permission change. It will be authenticated and audited by the backend.")
    }
    .task {
      guard appState.isPlatformAdmin else { return }
      await reload()
    }
  }

  private func refreshCard(_ context: HPScreenLayoutContext) -> some View {
    HPCard(style: .flat) {
      let layout = context.isExpanded
        ? AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.sm))
        : AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
      layout {
        VStack(alignment: .leading, spacing: 4) {
          HPSectionHeader("Platform overview")
          Text("Review organization health, membership access, and platform permissions.")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        if context.isExpanded { Spacer(minLength: HP.Space.sm) }
        let actionLayout = context.isExpanded
          ? AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.sm))
          : AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.xs))
        actionLayout {
          HPStatusBadge(text: isLoading ? "Refreshing" : "Ready", kind: isLoading ? .warning : .success)
          HPButton(
            title: "Refresh",
            systemImage: "arrow.clockwise",
            variant: .secondary,
            size: .md,
            isLoading: isLoading,
            fullWidth: !context.isExpanded,
            action: { Task { await reload() } }
          )
          .disabled(isLoading)
        }
        .frame(maxWidth: context.isExpanded ? nil : .infinity, alignment: .leading)
      }
    }
  }

  @ViewBuilder
  private func dashboardContent(_ context: HPScreenLayoutContext) -> some View {
    if isLoading && dashboard == nil {
      HPCard {
        HPLoadingState(text: "Loading platform health…")
          .frame(maxWidth: .infinity, minHeight: 180)
      }
    } else if let dashboard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        metricGrid(dashboard, context: context)
        ownerlessOrganizationWarning(dashboard.ownerless_organizations)
        unmanagedOrganizationWarning(dashboard.unmanaged_organizations)
        platformFeatureControlsCard(context)
        organizationDirectory(dashboard.organizations, context: context)
        if let organization = dashboard.organizations.first(where: { $0.id == selectedOrganizationId }) {
          organizationMemberCard(organization, context: context)
        }
        globalUserLookupCard(context)
        platformAdministratorsCard(context)
        auditHistoryCard(context)
      }
    } else {
      HPCard {
        HPErrorState(
          title: "Platform data unavailable",
          message: "Refresh to load organization data."
        )
      }
    }
  }

  @ViewBuilder
  private func ownerlessOrganizationWarning(_ organizations: [SDPlatformOrganization]) -> some View {
    if !organizations.isEmpty {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          Label("Owner assignment required", systemImage: "exclamationmark.shield.fill")
            .font(HP.Font.headline)
            .foregroundStyle(HP.Color.warning)
          Text("These organizations have no active owner. Active administrators do not satisfy the owner requirement; explicitly add an active owner before removing existing owner access.")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
          ForEach(organizations) { organization in
            ViewThatFits(in: .horizontal) {
              HStack(spacing: HP.Space.sm) {
                Text(organization.name)
                  .font(HP.Font.callout.weight(.semibold))
                  .foregroundStyle(HP.Color.text)
                Spacer(minLength: HP.Space.sm)
                Text(organization.slug)
                  .font(HP.Font.caption.monospaced())
                  .foregroundStyle(HP.Color.textMuted)
              }
              VStack(alignment: .leading, spacing: 2) {
                Text(organization.name)
                  .font(HP.Font.callout.weight(.semibold))
                  .foregroundStyle(HP.Color.text)
                Text(organization.slug)
                  .font(HP.Font.caption.monospaced())
                  .foregroundStyle(HP.Color.textMuted)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func unmanagedOrganizationWarning(_ organizations: [SDPlatformOrganization]) -> some View {
    if !organizations.isEmpty {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          Label("No active owner or administrator", systemImage: "person.crop.circle.badge.exclamationmark")
            .font(HP.Font.headline)
            .foregroundStyle(HP.Color.danger)
          Text("These organizations have neither an active owner nor an active administrator. They are included in the owner-required diagnostic above and need deliberate platform review.")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
          ForEach(organizations) { organization in
            ViewThatFits(in: .horizontal) {
              HStack(spacing: HP.Space.sm) {
                Text(organization.name)
                  .font(HP.Font.callout.weight(.semibold))
                  .foregroundStyle(HP.Color.text)
                Spacer(minLength: HP.Space.sm)
                Text(organization.slug)
                  .font(HP.Font.caption.monospaced())
                  .foregroundStyle(HP.Color.textMuted)
              }
              VStack(alignment: .leading, spacing: 2) {
                Text(organization.name)
                  .font(HP.Font.callout.weight(.semibold))
                  .foregroundStyle(HP.Color.text)
                Text(organization.slug)
                  .font(HP.Font.caption.monospaced())
                  .foregroundStyle(HP.Color.textMuted)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    }
  }

  private func metricGrid(_ dashboard: SDPlatformDashboard, context: HPScreenLayoutContext) -> some View {
    let orgs = dashboard.organizations
    return LazyVGrid(
      columns: context.gridColumns(compact: 2, regular: 3, wide: 5),
      spacing: HP.Space.sm
    ) {
      HPMetricCard(
        title: "Organizations",
        value: "\(orgs.count)",
        context: "Across the platform",
        valueColor: HP.Color.info
      )
      HPMetricCard(
        title: "Active members",
        value: "\(orgs.reduce(0) { $0 + $1.active_members })",
        context: "Active organization memberships",
        valueColor: HP.Color.success
      )
      HPMetricCard(
        title: "Players",
        value: "\(orgs.reduce(0) { $0 + $1.players })",
        context: "Player memberships",
        valueColor: HP.Color.info
      )
      HPMetricCard(
        title: "Active access",
        value: "\(orgs.reduce(0) { $0 + $1.active_entitlements })",
        context: "Current entitlements",
        valueColor: HP.Color.warning
      )
      HPMetricCard(
        title: "Teams",
        value: "\(orgs.reduce(0) { $0 + $1.teams })",
        context: "Across all organizations"
      )
    }
  }

  private func organizationDirectory(
    _ organizations: [SDPlatformOrganization],
    context: HPScreenLayoutContext
  ) -> some View {
    let filtered = SDPlatformDirectory.organizations(organizations, matching: organizationSearch)
    return HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Organizations") {
          HPStatusBadge(text: "\(filtered.count) shown", kind: .neutral)
        }
        HPSearchBar(text: $organizationSearch, placeholder: "Search organizations…")
        if filtered.isEmpty {
          HPEmptyState(
            title: "No organizations found",
            message: "No organizations match this search.",
            systemImage: "building.2"
          )
        } else {
          ForEach(Array(filtered.enumerated()), id: \.element.id) { index, organization in
            Button {
              selectedOrganizationId = organization.id
              Task { await loadMembers(for: organization.id) }
            } label: {
              organizationRow(organization, context: context)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityHint("Loads members for this organization")
            if index < filtered.count - 1 {
              Divider().overlay(HP.Color.border.opacity(0.5))
            }
          }
        }
      }
    }
  }

  private func organizationRow(
    _ organization: SDPlatformOrganization,
    context: HPScreenLayoutContext
  ) -> some View {
    let isSelected = selectedOrganizationId == organization.id
    let layout = context.isExpanded
      ? AnyLayout(HStackLayout(alignment: .top, spacing: HP.Space.sm))
      : AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
    return layout {
      HStack(alignment: .top, spacing: HP.Space.sm) {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "building.2")
          .foregroundStyle(isSelected ? HP.Color.accent : HP.Color.textMuted)
          .frame(width: 24, height: 24)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
          Text(organization.name)
            .font(HP.Font.headline)
            .foregroundStyle(HP.Color.text)
            .fixedSize(horizontal: false, vertical: true)
          Text(organization.id.uuidString.lowercased())
            .font(HP.Font.caption.monospaced())
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
          Text("\(organization.active_members) members • \(organization.players) players • \(organization.coaches) staff")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if context.isExpanded { Spacer(minLength: HP.Space.sm) }
      ViewThatFits(in: .horizontal) {
        HStack(spacing: HP.Space.xs) {
          if isSelected { HPStatusBadge(text: "Selected", kind: .gold) }
          HPStatusBadge(text: organization.status.capitalized, kind: statusKind(organization.status))
        }
        VStack(alignment: .leading, spacing: HP.Space.xs) {
          if isSelected { HPStatusBadge(text: "Selected", kind: .gold) }
          HPStatusBadge(text: organization.status.capitalized, kind: statusKind(organization.status))
        }
      }
    }
  }

  private func organizationMemberCard(
    _ organization: SDPlatformOrganization,
    context: HPScreenLayoutContext
  ) -> some View {
    let filtered = SDPlatformDirectory.members(
      members,
      matching: memberSearch,
      filter: memberFilter
    )
    return HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        let headerLayout = context.isExpanded
          ? AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.sm))
          : AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
        headerLayout {
          VStack(alignment: .leading, spacing: 3) {
            HPSectionHeader("Organization Details")
            Text("\(organization.name) • \(organization.slug)")
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.textMuted)
              .fixedSize(horizontal: false, vertical: true)
          }
          if context.isExpanded { Spacer(minLength: HP.Space.sm) }
          if context.isExpanded {
            HStack(spacing: HP.Space.sm) {
              organizationDetailActions(organization, fullWidth: false)
            }
          } else {
            VStack(alignment: .leading, spacing: HP.Space.xs) {
              organizationDetailActions(organization, fullWidth: true)
            }
          }
        }

        let filterLayout = context.isExpanded
          ? AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.sm))
          : AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
        filterLayout {
          HPSearchBar(text: $memberSearch, placeholder: "Search members by name, username, or email…")
          VStack(alignment: .leading, spacing: 4) {
            Text("ROLE FILTER")
              .font(HP.Font.eyebrow)
              .tracking(HP.Font.eyebrowTracking)
              .foregroundStyle(HP.Color.textMuted)
            Picker("Role", selection: $memberFilter) {
              ForEach(SDPlatformMemberFilter.allCases) { filter in
                Text(filter.title).tag(filter)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(HP.Color.accent)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, HP.Space.sm)
            .background(
              RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
                .fill(HP.Color.input)
            )
            .overlay(
              RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
                .strokeBorder(HP.Color.border, lineWidth: 1)
                .allowsHitTesting(false)
            )
          }
          .frame(maxWidth: context.isExpanded ? 220 : .infinity, alignment: .leading)
        }

        if isLoadingMembers {
          HPLoadingState(text: "Loading members…")
            .frame(maxWidth: .infinity, minHeight: 100)
        } else if filtered.isEmpty {
          HPEmptyState(
            title: "No members found",
            message: "No members match this search and filter.",
            systemImage: "person.3"
          )
        } else {
          ForEach(Array(filtered.enumerated()), id: \.element.id) { index, member in
            memberRow(member, context: context)
            if index < filtered.count - 1 {
              Divider().overlay(HP.Color.border.opacity(0.5))
            }
          }
        }

        Text("Ownership transfer is a protected two-step operation: first promote the replacement owner, then demote or deactivate the previous owner. The final active owner cannot be removed.")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @ViewBuilder
  private func organizationDetailActions(_ organization: SDPlatformOrganization, fullWidth: Bool) -> some View {
    NavigationLink {
      OrganizationSetupWizardView(
        organizationId: organization.id,
        organizationName: organization.name
      )
    } label: {
      Label("Assist Setup", systemImage: "checklist")
        .font(HP.Font.callout.weight(.semibold))
        .foregroundStyle(HP.Color.accent)
        .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 44, alignment: .leading)
    }
    HPButton(
      title: "Edit Organization",
      variant: .secondary,
      size: .sm,
      fullWidth: fullWidth,
      action: { editingOrganization = PlatformOrganizationDraft(organization) }
    )
    HPButton(
      title: "Refresh Members",
      systemImage: "arrow.clockwise",
      variant: .secondary,
      size: .sm,
      isLoading: isLoadingMembers,
      fullWidth: fullWidth,
      action: { Task { await loadMembers(for: organization.id) } }
    )
    .disabled(isLoadingMembers)
  }

  private func memberRow(_ member: SDPlatformMember, context: HPScreenLayoutContext) -> some View {
    let layout = context.isExpanded
      ? AnyLayout(HStackLayout(alignment: .top, spacing: HP.Space.sm))
      : AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
    return layout {
      VStack(alignment: .leading, spacing: 3) {
        Text(member.displayName)
          .font(HP.Font.headline)
          .foregroundStyle(HP.Color.text)
          .fixedSize(horizontal: false, vertical: true)
        if let username = member.username {
          Text("@\(username)")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
        }
        if let email = member.email {
          Text(email)
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        ViewThatFits(in: .horizontal) {
          HStack(spacing: HP.Space.xs) { memberBadges(member) }
          VStack(alignment: .leading, spacing: HP.Space.xs) { memberBadges(member) }
        }
        Text("Created: \(platformDate(member.created_at)) • Last activity: \(platformDate(member.last_activity))")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if context.isExpanded { Spacer(minLength: HP.Space.sm) }
      VStack(alignment: context.isExpanded ? .trailing : .leading, spacing: HP.Space.xs) {
        HPStatusBadge(
          text: member.status.capitalized,
          kind: member.isActive ? .success : statusKind(member.status)
        )
        HPButton(
          title: "Edit Permissions",
          variant: .secondary,
          size: .sm,
          fullWidth: !context.isExpanded,
          action: { editingMember = PlatformMembershipEditDraft(member: member) }
        )
      }
      .frame(maxWidth: context.isExpanded ? nil : .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private func memberBadges(_ member: SDPlatformMember) -> some View {
    ForEach(member.badges, id: \.self) { badge in
      HPStatusBadge(text: badge, kind: badge == "Player" ? .info : .neutral)
    }
  }

  private func globalUserLookupCard(_ context: HPScreenLayoutContext) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Global User Lookup")
        let searchLayout = context.isExpanded
          ? AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.sm))
          : AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
        searchLayout {
          HPSearchBar(text: $userSearch, placeholder: "Search name, username, email, or user ID…")
            .onSubmit { Task { await searchUsers() } }
          HPButton(
            title: "Search",
            systemImage: "magnifyingglass",
            variant: .secondary,
            size: .md,
            isLoading: isSearchingUsers,
            fullWidth: !context.isExpanded,
            action: { Task { await searchUsers() } }
          )
          .disabled(userSearch.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || isSearchingUsers)
        }
        if isSearchingUsers {
          HPLoadingState(text: "Searching global users…")
        }
        ForEach(userResults) { user in
          let resultLayout = context.isExpanded
            ? AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.sm))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
          resultLayout {
            VStack(alignment: .leading, spacing: 2) {
              Text(user.displayName)
                .font(HP.Font.callout.weight(.semibold))
                .foregroundStyle(HP.Color.text)
              Text(user.email ?? user.user_id.uuidString.lowercased())
                .font(HP.Font.caption)
                .foregroundStyle(HP.Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
              if !user.usernames.isEmpty {
                Text(user.usernames.map { "@\($0.username)" }.joined(separator: ", "))
                  .font(HP.Font.caption)
                  .foregroundStyle(HP.Color.textMuted)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if context.isExpanded { Spacer(minLength: HP.Space.sm) }
            HPButton(
              title: "Grant Platform Admin",
              variant: .secondary,
              size: .sm,
              fullWidth: !context.isExpanded,
              action: {
                pendingPlatformAdminChange = PlatformAdministratorChange(
                  userId: user.user_id,
                  granted: true
                )
              }
            )
            .disabled(platformAdministrators.contains(where: { $0.user_id == user.user_id }))
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }

  private func platformAdministratorsCard(_ context: HPScreenLayoutContext) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Platform Administrators")
        Text("Platform authority is separate from every organization membership and ownership role.")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
        if platformAdministrators.isEmpty {
          HPEmptyState(
            title: "No platform administrators",
            message: "No platform administrators were returned.",
            systemImage: "person.badge.shield.checkmark"
          )
        }
        ForEach(platformAdministrators) { administrator in
          let rowLayout = context.isExpanded
            ? AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.sm))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
          rowLayout {
            VStack(alignment: .leading, spacing: 2) {
              Text(administrator.displayName)
                .font(HP.Font.callout.weight(.semibold))
                .foregroundStyle(HP.Color.text)
              Text("Granted: \(platformDate(administrator.granted_at))")
                .font(HP.Font.caption)
                .foregroundStyle(HP.Color.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if context.isExpanded { Spacer(minLength: HP.Space.sm) }
            HPButton(
              title: "Revoke",
              variant: .destructive,
              size: .sm,
              fullWidth: !context.isExpanded,
              action: {
                pendingPlatformAdminChange = PlatformAdministratorChange(
                  userId: administrator.user_id,
                  granted: false
                )
              }
            )
            .disabled(administrator.user_id == appState.myProfile?.id)
          }
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
      }
    }
  }

  private func platformFeatureControlsCard(_ context: HPScreenLayoutContext) -> some View {
    let key = SDPlatformFeatureKey.playerDevelopmentCopilot
    let enabled = SDPlatformFeatureGate.playerDevelopmentCopilotEnabled(
      in: platformFeatureFlags
    )
    let isMutating = platformFeatureMutationKey == key
    let layout = context.isExpanded
      ? AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.md))
      : AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.md))
    return HPCard {
      layout {
        VStack(alignment: .leading, spacing: 4) {
          HPSectionHeader("Player Development Copilot")
          Text("Enables AI-assisted coach and player Copilot experiences across Home Plate.")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if context.isExpanded { Spacer(minLength: HP.Space.sm) }
        HStack(spacing: HP.Space.sm) {
          HPStatusBadge(
            text: isMutating ? "Updating" : (enabled ? "Enabled" : "Disabled"),
            kind: enabled ? .success : .neutral
          )
          Toggle(
            "Player Development Copilot",
            isOn: Binding(
              get: { enabled },
              set: { newValue in
                Task { await setPlayerDevelopmentCopilotEnabled(newValue) }
              }
            )
          )
          .labelsHidden()
          .accessibilityLabel("Player Development Copilot")
          .disabled(isMutating)
        }
      }
    }
  }

  private func auditHistoryCard(_ context: HPScreenLayoutContext) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Recent Permission Changes")
        if auditEntries.isEmpty {
          HPEmptyState(
            title: "No permission changes",
            message: "No recent permission changes.",
            systemImage: "clock.arrow.circlepath"
          )
        } else {
          HPTable(
            columns: [
              HPColumn(title: "Action"),
              HPColumn(title: "Change"),
              HPColumn(title: "Date", alignment: .trailing),
            ],
            rows: auditEntries.prefix(25).map { entry in
              HPTableRow(
                id: entry.id,
                cells: [
                  entry.action.replacingOccurrences(of: "_", with: " ").capitalized,
                  auditSummary(entry),
                  platformDate(entry.created_at),
                ]
              )
            },
            layout: context.tableLayout
          )
        }
      }
    }
  }

  private func statusKind(_ status: String) -> HPStatusKind {
    switch status.lowercased() {
    case "active": .success
    case "invited", "pending": .warning
    case "disabled", "suspended", "archived": .danger
    default: .neutral
    }
  }

  private func loadMembers(for organizationId: UUID) async {
    guard let supabase = appState.supabase,
          selectedOrganizationId == organizationId else { return }
    isLoadingMembers = true
    defer { isLoadingMembers = false }
    do {
      let response = try await supabase.platformOrganizationMembers(orgId: organizationId)
      guard selectedOrganizationId == response.organization.id else { return }
      members = response.members
    } catch {
      guard selectedOrganizationId == organizationId else { return }
      members = []
      errorText = "Organization members could not be loaded."
    }
  }

  private func searchUsers() async {
    guard let supabase = appState.supabase else { return }
    let query = userSearch.trimmingCharacters(in: .whitespacesAndNewlines)
    guard query.count >= 2 else { return }
    isSearchingUsers = true
    defer { isSearchingUsers = false }
    do {
      userResults = try await supabase.platformSearchUsers(query: query)
    } catch {
      userResults = []
      errorText = "Global users could not be searched."
    }
  }

  private func applyMembershipUpdate(_ update: PlatformMembershipEditDraft) async {
    guard let supabase = appState.supabase else { return }
    do {
      _ = try await supabase.platformUpdateMembership(
        orgId: update.member.org_id,
        userId: update.member.user_id,
        role: update.role,
        status: update.status,
        reason: update.cleanedReason,
        requestId: update.requestId
      )
      editingMember = nil
      toastText = "Permissions updated for \(update.member.displayName)."
      await loadMembers(for: update.member.org_id)
      await reloadPlatformSupportingData()
      await appState.refreshOrgContext()
    } catch {
      let raw = error.localizedDescription.lowercased()
      errorText = raw.contains("last_active_owner_required")
        ? "Promote another active owner before removing, demoting, or deactivating the final owner."
        : "The permission change could not be applied."
    }
  }

  private func applyPlatformAdministratorChange(_ change: PlatformAdministratorChange) async {
    guard let supabase = appState.supabase else { return }
    pendingPlatformAdminChange = nil
    do {
      try await supabase.platformSetAdministrator(
        userId: change.userId,
        granted: change.granted,
        reason: nil,
        requestId: change.requestId
      )
      toastText = change.granted
        ? "Platform administrator access granted."
        : "Platform administrator access revoked."
      await reloadPlatformSupportingData()
    } catch {
      errorText = "The platform administrator change could not be applied."
    }
  }

  private func reloadPlatformSupportingData() async {
    guard let supabase = appState.supabase else { return }
    async let loadedAdministrators = try? supabase.platformAdministrators()
    async let loadedFeatureFlags = try? supabase.platformAdminFeatureFlags()
    async let loadedAudit = try? supabase.platformAuditHistory()
    platformAdministrators = await loadedAdministrators ?? []
    platformFeatureFlags = await loadedFeatureFlags ?? []
    auditEntries = await loadedAudit ?? []
  }

  private func setPlayerDevelopmentCopilotEnabled(_ enabled: Bool) async {
    guard let supabase = appState.supabase else { return }
    let key = SDPlatformFeatureKey.playerDevelopmentCopilot
    guard platformFeatureMutationKey == nil else { return }
    platformFeatureMutationKey = key
    defer { platformFeatureMutationKey = nil }
    do {
      let updated = try await supabase.platformSetFeatureFlag(
        key: key,
        enabled: enabled,
        requestId: UUID()
      )
      platformFeatureFlags.removeAll(where: { $0.key == key })
      platformFeatureFlags.append(updated)
      await appState.refreshPlatformFeatureFlags()
      await reloadPlatformSupportingData()
      toastText = enabled
        ? "Player Development Copilot enabled."
        : "Player Development Copilot disabled."
    } catch {
      await reloadPlatformSupportingData()
      errorText = "The Player Development Copilot setting could not be updated."
    }
  }

  private func platformDate(_ value: String?) -> String {
    guard let value, !value.isEmpty else { return "Not available" }
    return String(value.prefix(10))
  }

  private func auditSummary(_ entry: SDPlatformAuditEntry) -> String {
    let previousEnabled = entry.details["previous_enabled"]?.boolValue
    let newEnabled = entry.details["new_enabled"]?.boolValue
    if let previousEnabled, let newEnabled {
      return "\(previousEnabled ? "Enabled" : "Disabled") → \(newEnabled ? "Enabled" : "Disabled")"
    }
    let previousRole = entry.details["previous_role"]?.stringValue
    let newRole = entry.details["new_role"]?.stringValue
    let previousStatus = entry.details["previous_status"]?.stringValue
    let newStatus = entry.details["new_status"]?.stringValue
    let roleChange = [previousRole, newRole].compactMap { $0 }.joined(separator: " → ")
    let statusChange = [previousStatus, newStatus].compactMap { $0 }.joined(separator: " → ")
    let changes = [roleChange, statusChange].filter { !$0.isEmpty }.joined(separator: " • ")
    return changes.isEmpty ? (entry.target_id ?? entry.target_type) : changes
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      dashboard = try await supabase.platformAdminDashboard()
      await reloadPlatformSupportingData()
      if let selectedOrganizationId {
        await loadMembers(for: selectedOrganizationId)
      }
    }
    catch { errorText = "Platform data could not be loaded." }
  }

  private func save(_ draft: PlatformOrganizationDraft) async {
    guard let supabase = appState.supabase else { return }
    do {
      try await supabase.platformUpdateOrganization(draft.organization)
      editingOrganization = nil
      await reload()
    } catch {
      errorText = "Organization changes could not be saved."
    }
  }

  private func create(_ draft: PlatformOrganizationCreateDraft) async {
    let created = await creationWorkflow.submit(
      draft: draft,
      create: { draft in
        guard let supabase = appState.supabase else {
          throw NSError(
            domain: "PlatformAdmin",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Platform service is unavailable."]
          )
        }
        return try await supabase.platformCreateOrganization(
          name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
          slug: draft.normalizedSlug,
          plan: draft.plan,
          billingEmail: draft.cleanedBillingEmail,
          maxMembers: Int(draft.maxMembers)
        )
      },
      refresh: {
        await appState.refreshOrgContext()
        await reload()
      },
      errorMessage: { error in
        platformAdminMessage(for: error, fallback: "The organization could not be created. \(error.localizedDescription)")
      }
    )
    if created != nil {
      toastText = creationWorkflow.successText
    }
  }

  private func platformAdminMessage(for error: Error, fallback: String) -> String {
    let raw = error.localizedDescription
    if raw.localizedCaseInsensitiveContains("organization_slug_exists") {
      return "That organization slug is already in use. Choose another slug."
    }
    if raw.localizedCaseInsensitiveContains("invalid_organization_slug") {
      return "Use only lowercase letters, numbers, and hyphens in the organization slug."
    }
    return fallback
  }
}

struct PlatformOrganizationCreateDraft: Equatable {
  var name = ""
  var slug = ""
  var plan = "starter"
  var billingEmail = ""
  var maxMembers = ""

  var normalizedSlug: String {
    slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  var cleanedBillingEmail: String? {
    let value = billingEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return value.isEmpty ? nil : value
  }

  var isValid: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && normalizedSlug.range(of: "^[a-z0-9][a-z0-9-]{1,62}$", options: .regularExpression) != nil
      && (maxMembers.isEmpty || (Int(maxMembers) ?? 0) > 0)
  }
}

struct PlatformOrganizationDraft: Identifiable {
  let original: SDPlatformOrganization
  var name: String
  var slug: String
  var status: String
  var plan: String
  var billingEmail: String
  var maxMembers: String
  var id: UUID { original.id }

  init(_ organization: SDPlatformOrganization) {
    original = organization
    name = organization.name
    slug = organization.slug
    status = organization.status
    plan = organization.plan
    billingEmail = organization.billing_email ?? ""
    maxMembers = organization.max_members.map(String.init) ?? ""
  }

  var organization: SDPlatformOrganization {
    SDPlatformOrganization(id: original.id, slug: slug, name: name, status: status, plan: plan,
      billing_email: billingEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : billingEmail,
      max_members: Int(maxMembers), active_members: original.active_members, players: original.players,
      coaches: original.coaches, active_entitlements: original.active_entitlements, teams: original.teams)
  }
}

struct PlatformMembershipEditDraft: Identifiable, Equatable {
  let member: SDPlatformMember
  var role: String
  var status: String
  var reason = ""
  let requestId: UUID
  var id: String { member.id }

  init(member: SDPlatformMember, requestId: UUID = UUID()) {
    self.member = member
    role = member.normalizedRole
    status = member.normalizedStatus
    self.requestId = requestId
  }

  var cleanedReason: String? {
    let value = reason.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }

  var hasChanges: Bool {
    role != member.normalizedRole || status != member.normalizedStatus
  }
}

struct PlatformAdministratorChange: Identifiable, Equatable {
  let userId: UUID
  let granted: Bool
  let requestId: UUID
  var id: UUID { requestId }

  init(userId: UUID, granted: Bool, requestId: UUID = UUID()) {
    self.userId = userId
    self.granted = granted
    self.requestId = requestId
  }
}

private struct PlatformMembershipEditor: View {
  @Environment(\.dismiss) private var dismiss
  @State var draft: PlatformMembershipEditDraft
  @State private var isConfirming = false
  let onApply: (PlatformMembershipEditDraft) -> Void

  init(
    draft: PlatformMembershipEditDraft,
    onApply: @escaping (PlatformMembershipEditDraft) -> Void
  ) {
    _draft = State(initialValue: draft)
    self.onApply = onApply
  }

  var body: some View {
    NavigationStack {
      HPFormScreenLayout { _ in
        HPWorkspaceHeader(
          "Permission Editor",
          orgLabel: "Platform Administration",
          context: draft.member.displayName
        )
      } sections: { _ in
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Member")
            Text(draft.member.displayName)
              .font(HP.Font.headline)
              .foregroundStyle(HP.Color.text)
              .fixedSize(horizontal: false, vertical: true)
            if let email = draft.member.email {
              Text(email)
                .font(HP.Font.callout)
                .foregroundStyle(HP.Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            }
            Text(draft.member.user_id.uuidString.lowercased())
              .font(HP.Font.caption.monospaced())
              .foregroundStyle(HP.Color.textMuted)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.md) {
            HPSectionHeader("Organization Permissions")
            VStack(alignment: .leading, spacing: 6) {
              Text("ROLE")
                .font(HP.Font.eyebrow)
                .tracking(HP.Font.eyebrowTracking)
                .foregroundStyle(HP.Color.textMuted)
              Picker("Role", selection: $draft.role) {
                ForEach(["owner", "admin", "coach", "player", "parent"], id: \.self) {
                  Text($0.capitalized).tag($0)
                }
              }
              .labelsHidden()
              .pickerStyle(.menu)
              .tint(HP.Color.accent)
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
              .padding(.horizontal, HP.Space.sm)
              .background(
                RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
                  .fill(HP.Color.input)
              )
              .overlay(
                RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
                  .strokeBorder(HP.Color.border, lineWidth: 1)
                  .allowsHitTesting(false)
              )
            }
            VStack(alignment: .leading, spacing: 6) {
              Text("STATUS")
                .font(HP.Font.eyebrow)
                .tracking(HP.Font.eyebrowTracking)
                .foregroundStyle(HP.Color.textMuted)
              HPSegmentedControl(
                options: [
                  (value: "active", label: "Active"),
                  (value: "invited", label: "Invited"),
                  (value: "disabled", label: "Disabled"),
                  (value: "suspended", label: "Suspended"),
                ],
                selection: $draft.status
              )
            }
            HPFormField(
              label: "Reason (optional)",
              text: $draft.reason,
              kind: .multiline,
              placeholder: "Reason for this permission change",
              helper: "Up to 500 characters. The backend audits the submitted change."
            )
            if draft.member.normalizedRole == "owner"
              && (draft.role != "owner" || draft.status != "active") {
              Label(
                "Another active owner must exist before this change can succeed.",
                systemImage: "exclamationmark.shield.fill"
              )
              .font(HP.Font.callout)
              .foregroundStyle(HP.Color.warning)
              .fixedSize(horizontal: false, vertical: true)
            }
            Text("Organization permissions come from this membership only. Platform administrator access is managed separately.")
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.textMuted)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      } primaryAction: { context in
        HPButton(
          title: "Review Change",
          systemImage: "checkmark.shield",
          variant: .primary,
          size: .lg,
          fullWidth: context.isAccessibilitySize,
          action: { isConfirming = true }
        )
        .disabled(!draft.hasChanges || draft.reason.count > 500)
      } secondaryAction: { context in
        HPButton(
          title: "Cancel",
          variant: .secondary,
          size: .lg,
          fullWidth: context.isAccessibilitySize,
          action: { dismiss() }
        )
      }
      .navigationTitle("Permission Editor")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            #if os(macOS)
            .keyboardShortcut(.cancelAction)
            #endif
        }
      }
      .confirmationDialog(
        "Apply Organization Permission Change?",
        isPresented: $isConfirming,
        titleVisibility: .visible
      ) {
        Button("Apply Change") { onApply(draft) }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Change \(draft.member.displayName) from \(draft.member.role)/\(draft.member.status) to \(draft.role)/\(draft.status). This request will be authorized, idempotent, and audited by the backend.")
      }
    }
  }
}

private struct PlatformOrganizationCreateEditor: View {
  @Environment(\.dismiss) private var dismiss
  @State private var draft = PlatformOrganizationCreateDraft()
  @State private var didEditSlug = false
  @State private var generatedSlug = ""
  let isSubmitting: Bool
  let errorText: String?
  let onCreate: (PlatformOrganizationCreateDraft) -> Void

  var body: some View {
    NavigationStack {
      HPFormScreenLayout { _ in
        HPWorkspaceHeader(
          "New Organization",
          orgLabel: "Platform Administration",
          context: "Manual organization provisioning"
        )
      } sections: { _ in
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.md) {
            HPSectionHeader("Organization")
            HPFormField(
              label: "Name",
              text: $draft.name,
              placeholder: "Organization name"
            )
            .onChange(of: draft.name) { _, newName in
              guard !didEditSlug || draft.slug == generatedSlug else { return }
              let nextSlug = slugify(newName)
              generatedSlug = nextSlug
              draft.slug = nextSlug
            }
            HPFormField(
              label: "Slug",
              text: $draft.slug,
              placeholder: "organization-slug",
              helper: "The slug identifies this organization at sign-in. Use lowercase letters, numbers, and hyphens."
            )
            .onChange(of: draft.slug) { _, value in
              if value != generatedSlug { didEditSlug = true }
            }
            HPFormField(
              label: "Billing email (optional)",
              text: $draft.billingEmail,
              placeholder: "billing@example.com"
            )
            HPFormField(
              label: "Member limit (optional)",
              text: $draft.maxMembers,
              placeholder: "Positive whole number"
            )
          }
        }
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.md) {
            HPSectionHeader("Plan")
            HPSegmentedControl(
              options: [
                (value: "starter", label: "Starter"),
                (value: "professional", label: "Professional"),
                (value: "enterprise", label: "Enterprise"),
              ],
              selection: $draft.plan
            )
            Text("Temporary manual provisioning: you will become this organization’s initial owner. Add another owner before removing your access.")
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.textMuted)
              .fixedSize(horizontal: false, vertical: true)
            if let errorText {
              Label(errorText, systemImage: "exclamationmark.triangle")
                .font(HP.Font.callout)
                .foregroundStyle(HP.Color.danger)
                .fixedSize(horizontal: false, vertical: true)
            }
            if isSubmitting {
              HStack(spacing: HP.Space.xs) {
                ProgressView()
                Text("Creating organization…")
                  .font(HP.Font.callout)
                  .foregroundStyle(HP.Color.text)
              }
              .accessibilityElement(children: .combine)
            }
          }
        }
      } primaryAction: { context in
        HPButton(
          title: isSubmitting ? "Creating…" : "Create",
          systemImage: "building.2.badge.plus",
          variant: .primary,
          size: .lg,
          isLoading: isSubmitting,
          fullWidth: context.isAccessibilitySize,
          action: { onCreate(draft) }
        )
        .disabled(!draft.isValid || isSubmitting)
      } secondaryAction: { context in
        HPButton(
          title: "Cancel",
          variant: .secondary,
          size: .lg,
          fullWidth: context.isAccessibilitySize,
          action: { dismiss() }
        )
        .disabled(isSubmitting)
      }
      .navigationTitle("New Organization")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .disabled(isSubmitting)
            #if os(macOS)
            .keyboardShortcut(.cancelAction)
            #endif
        }
      }
    }
  }

  private func slugify(_ input: String) -> String {
    input
      .lowercased()
      .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
  }
}

private struct PlatformOrganizationEditor: View {
  @Environment(\.dismiss) private var dismiss
  @State var draft: PlatformOrganizationDraft
  let onSave: (PlatformOrganizationDraft) -> Void

  init(draft: PlatformOrganizationDraft, onSave: @escaping (PlatformOrganizationDraft) -> Void) {
    _draft = State(initialValue: draft)
    self.onSave = onSave
  }

  var body: some View {
    NavigationStack {
      HPFormScreenLayout { _ in
        HPWorkspaceHeader(
          "Edit Organization",
          orgLabel: "Platform Administration",
          context: draft.original.name
        )
      } sections: { _ in
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.md) {
            HPSectionHeader("Organization")
            HPFormField(label: "Name", text: $draft.name, placeholder: "Organization name")
            HPFormField(label: "Slug", text: $draft.slug, placeholder: "organization-slug")
            HPFormField(label: "Billing email", text: $draft.billingEmail, placeholder: "billing@example.com")
            HPFormField(label: "Member limit", text: $draft.maxMembers, placeholder: "Positive whole number")
          }
        }
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.md) {
            HPSectionHeader("Plan & Status")
            VStack(alignment: .leading, spacing: 6) {
              Text("PLAN")
                .font(HP.Font.eyebrow)
                .tracking(HP.Font.eyebrowTracking)
                .foregroundStyle(HP.Color.textMuted)
              HPSegmentedControl(
                options: [
                  (value: "starter", label: "Starter"),
                  (value: "professional", label: "Professional"),
                  (value: "enterprise", label: "Enterprise"),
                ],
                selection: $draft.plan
              )
            }
            VStack(alignment: .leading, spacing: 6) {
              Text("STATUS")
                .font(HP.Font.eyebrow)
                .tracking(HP.Font.eyebrowTracking)
                .foregroundStyle(HP.Color.textMuted)
              HPSegmentedControl(
                options: [
                  (value: "active", label: "Active"),
                  (value: "suspended", label: "Suspended"),
                  (value: "archived", label: "Archived"),
                ],
                selection: $draft.status
              )
            }
          }
        }
      } primaryAction: { context in
        HPButton(
          title: "Save",
          systemImage: "checkmark",
          variant: .primary,
          size: .lg,
          fullWidth: context.isAccessibilitySize,
          action: {
            // Close immediately so a failed refresh cannot trap the admin in
            // this editor. The parent surface reports any save error clearly.
            dismiss()
            onSave(draft)
          }
        )
      } secondaryAction: { context in
        HPButton(
          title: "Cancel",
          variant: .secondary,
          size: .lg,
          fullWidth: context.isAccessibilitySize,
          action: { dismiss() }
        )
      }
      .navigationTitle("Edit Organization")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            #if os(macOS)
            .keyboardShortcut(.cancelAction)
            #endif
        }
      }
    }
  }
}
