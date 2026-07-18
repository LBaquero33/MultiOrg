import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct OrgAdminConsoleView: View {
  let platformSupportOrganization: SDPlatformOrganization?

  @EnvironmentObject private var appState: AppState
  @Environment(\.scenePhase) private var scenePhase

  @State private var settings: SDOrgSettings?
  @State private var facilities: [SDFacility] = []
  @State private var adminMembers: [SDOrgAdminMember] = []
  @State private var upcomingBookings: [SDFacilityBooking] = []
  @State private var templateCount = 0
  @State private var channelCount = 0
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var toastText: String?
  @State private var isApplyingSettings = false
  @State private var isSavingSettings = false
  @State private var settingsSaveTask: Task<Void, Never>?
  @State private var organizationSubscription: SDOrgSubscription?
  @State private var isBillingLoading = false
  @State private var billingErrorText: String?
  @State private var billingAction: BillingAction?
  @State private var connectStatus: SupabaseService.StripeConnectAccountStatus?
  @State private var isConnectLoading = false
  @State private var connectErrorText: String?
  @State private var connectAction: ConnectAction?
  @State private var didOpenConnectOnboarding = false
  @State private var paymentRequestState = SDPaymentRequestListState()
  @State private var isPaymentRequestLoading = false
  @State private var paymentRequestErrorText: String?
  @State private var paymentRequestCreatePresentation = SDPaymentRequestCreatePresentationState()
  @State private var paymentRequestDraft = SDPaymentRequestCreateDraft()
  @State private var paymentRequestMutationId: UUID?
  @State private var paymentRequestRosterState = SDPaymentRequestEligibleRosterState.idle
  @State private var paymentRequestContextOrgId: UUID?
  @State private var paymentRequestLoadToken: UUID?
  @State private var paymentRequestPlayerSearchText = ""
  @State private var authorizationValidatedOrgId: UUID?
  @State private var isCheckingAuthorization = true

  @State private var selectedTab: Tab = .dashboard
  @State private var editingFacility: FacilityDraft?
  @State private var facilityPendingDeletion: SDFacility?
  @State private var isShowingCreateMember = false
  @State private var editingMember: MemberDraft?

  // Branding/settings
  @State private var displayName = ""
  @State private var shortName = ""
  @State private var supportEmail = ""
  @State private var websiteHost = ""
  @State private var primaryHex = "#0D2445"
  @State private var secondaryHex = "#0A3854"
  @State private var accentHex = "#4D9EF9"
  @State private var logoURL: URL?
  @State private var pendingLogoJPEG: Data?
  @State private var logoPickerItem: PhotosPickerItem?

  // Features
  @State private var featureFacilities = true
  @State private var featureChat = true
  @State private var featurePrograms = true
  @State private var featureTesting = true
  @State private var featureBPAnalysis = true
  @State private var featureParentPortal = true
  @State private var featureBilling = true

  // Booking policy
  @State private var defaultDuration = "60"
  @State private var minDuration = "30"
  @State private var maxDuration = "120"
  @State private var allowPlayerRequests = true
  @State private var requireCoachApproval = true

  // Team scope: coaches can always see teams by default, but their ability to
  // change assignments is intentionally controlled by organization admins.
  @State private var coachesCanViewAllTeams = true
  @State private var restrictCoachActionsToTeam = true
  @State private var coachesCanManageTeams = false

  enum Tab: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case branding = "Branding"
    case features = "Features"
    case billing = "Billing"
    case finance = "Finance"
    case communication = "Communication"
    case registration = "Registration"
    case analytics = "Analytics"
    case facilities = "Facilities"
    case members = "Members"
    case teamOperations = "Team Operations"
    var id: String { rawValue }

    var systemImage: String {
      switch self {
      case .dashboard: "rectangle.3.group"
      case .branding: "paintbrush"
      case .features: "switch.2"
      case .billing: "creditcard"
      case .finance: "chart.line.uptrend.xyaxis"
      case .communication: "bubble.left.and.bubble.right"
      case .registration: "person.crop.circle.badge.plus"
      case .analytics: "chart.bar.xaxis"
      case .facilities: "building.2"
      case .members: "person.2.badge.gearshape"
      case .teamOperations: "person.3.sequence.fill"
      }
    }
  }

  private enum BillingAction {
    case checkout
    case portal
  }

  private enum ConnectAction {
    case onboarding
    case refresh
  }

  init(platformSupportOrganization: SDPlatformOrganization? = nil) {
    self.platformSupportOrganization = platformSupportOrganization
  }

  private var isPlatformSupportMode: Bool {
    platformSupportOrganization != nil
  }

  private var paymentRequestOrganizationId: UUID? {
    platformSupportOrganization?.id ?? appState.activeOrgId
  }

  private var hasSelectedActivePaymentRequestOrganization: Bool {
    guard paymentRequestOrganizationId != nil else { return false }
    if let platformSupportOrganization {
      return platformSupportOrganization.status
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() == "active"
    }
    return appState.activeOrgId != nil
  }

  private var hasActiveOwnerOrAdminPaymentRequestMembership: Bool {
    OrganizationAuthorization.canAdminister(
      userId: appState.myProfile?.id,
      orgId: paymentRequestOrganizationId,
      memberships: appState.myOrgMemberships
    )
  }

  private var isPlatformSupportAuthorized: Bool {
    isPlatformSupportMode
      && (
        paymentRequestState.hasSuccessfulResponse(for: paymentRequestOrganizationId)
          || paymentRequestRosterState.hasSuccessfulResponse(for: paymentRequestOrganizationId)
      )
  }

  private var canManagePaymentRequests: Bool {
    SDPaymentRequestAuthorization.canManagePaymentRequests(
      selectedOrganizationIsActive: hasSelectedActivePaymentRequestOrganization,
      hasActiveOwnerOrAdminMembership: hasActiveOwnerOrAdminPaymentRequestMembership,
      isPlatformAdmin: appState.isPlatformAdmin,
      isPlatformSupportAuthorized: isPlatformSupportAuthorized,
      currentUserId: appState.myProfile?.id
    )
  }

  private var paymentRequestCreateDisabledReason: String? {
    SDPaymentRequestAuthorization.createControlDisabledReason(
      canManagePaymentRequests: canManagePaymentRequests,
      selectedOrganizationIsActive: hasSelectedActivePaymentRequestOrganization,
      hasMutationInFlight: paymentRequestMutationId != nil
    )
  }

  private var createPaymentRequestPresented: Binding<Bool> {
    Binding(
      get: { paymentRequestCreatePresentation.isPresented },
      set: { paymentRequestCreatePresentation.setPresented($0) }
    )
  }

  var body: some View {
    Group {
      if isCheckingAuthorization || authorizationValidatedOrgId != paymentRequestOrganizationId {
        HPScreenScaffold(maxContentWidth: 560) { _ in
          HPCard {
            HPLoadingState(text: "Checking organization access…")
          }
        }
      } else if canManagePaymentRequests {
        if isPlatformSupportMode || !hasActiveOwnerOrAdminPaymentRequestMembership {
          platformSupportPresentation
        } else {
          memberPresentation
        }
      } else {
        accessDeniedSurface
      }
    }
      .task(id: paymentRequestOrganizationId) {
        await validateAuthorizationAndLoad()
      }
      .onChange(of: scenePhase) { _, next in
        guard next == .active else { return }
        Task {
          await validateAuthorizationAndLoad(refreshAllData: false)
        }
      }
      .onChange(of: settingsAutosaveKey) { _, _ in scheduleSettingsAutosave() }
  }

  private var accessDeniedSurface: some View {
    HPScreenScaffold(maxContentWidth: 560) { _ in
      HPCard {
        HPEmptyState(
          title: isPlatformSupportMode
            ? "Platform Support Access Required"
            : "Organization Admin Access Required",
          message: isPlatformSupportMode
            ? "Only a verified platform administrator can manage payment requests in support mode."
            : "Only an active owner or administrator for the selected organization can open these controls.",
          systemImage: "lock.shield"
        )
      }
    }
    .navigationTitle("Org Admin")
  }

  private var platformSupportPresentation: some View {
    HPAdminScreenLayout(
      supportContext: HPAdminSupportContext(
        organizationName: platformSupportOrganization?.name ?? "Organization",
        message: "Organization settings remain read-only. Verified platform support may perform only the payment-request operations separately authorized by the server; this does not make you an organization owner or member."
      )
    ) { _ in
      HPWorkspaceHeader(
        "Payment Support",
        orgLabel: platformSupportOrganization?.name ?? "Organization",
        context: "Authorized payment-request operations",
        identity: supportOrganizationIdentity
      )
    } sectionNavigation: { _ in
      HPCard {
        HStack(spacing: HP.Space.sm) {
          Image(systemName: "creditcard.and.123")
            .foregroundStyle(HP.Color.accent)
            .accessibilityHidden(true)
          Text("Payment requests")
            .font(HP.Font.headline)
            .foregroundStyle(HP.Color.text)
          Spacer(minLength: 0)
          HPStatusBadge(text: "Support scope", kind: .gold)
        }
      }
    } content: { context in
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.md) {
          paymentRequestsSection(context)
        }
      }
    } dangerZone: { _ in
      EmptyView()
    }
    .navigationTitle("Payment Support")
    .hpToast($toastText)
    .sheet(isPresented: createPaymentRequestPresented) {
      PaymentRequestCreateSheet(
        organizationId: paymentRequestOrganizationId,
        supabase: appState.supabase,
        draft: $paymentRequestDraft,
        playerSearchText: $paymentRequestPlayerSearchText,
        isSubmitting: paymentRequestMutationId != nil,
        errorText: paymentRequestErrorText,
        onCreate: { eligiblePlayers in
          Task { await createPaymentRequest(eligiblePlayers: eligiblePlayers) }
        }
      )
      #if os(macOS)
      .frame(minWidth: 540, minHeight: 560)
      #endif
    }
  }

  /// A single value keeps the compiler (and the save behavior) sane instead
  /// of attaching a long chain of individual `onChange` modifiers to the page.
  private var settingsAutosaveKey: String {
    [
      displayName, shortName, supportEmail, websiteHost, primaryHex, secondaryHex, accentHex,
      String(featureFacilities), String(featureChat), String(featurePrograms), String(featureTesting),
      String(featureBPAnalysis), String(featureParentPortal), String(featureBilling),
      defaultDuration, minDuration, maxDuration, String(allowPlayerRequests), String(requireCoachApproval),
      String(coachesCanViewAllTeams), String(restrictCoachActionsToTeam), String(coachesCanManageTeams),
    ].joined(separator: "\u{1F}")
  }

  private var pageSurface: some View {
    HPAdminScreenLayout { _ in
      header
    } sectionNavigation: { context in
      HPCard {
        adminSectionNavigation(context)
      }
    } content: { context in
      memberSectionContent(context)
    } dangerZone: { _ in
      EmptyView()
    }
    .navigationTitle("Org Admin")
  }

  @ViewBuilder
  private func adminSectionNavigation(_ context: HPScreenLayoutContext) -> some View {
    if context.isWide || context.isAccessibilitySize {
      HPSegmentedControl(
        options: visibleTabs.map { (value: $0, label: $0.rawValue) },
        selection: $selectedTab
      )
    } else {
      Menu {
        ForEach(visibleTabs) { tab in
          Button {
            selectedTab = tab
          } label: {
            Label(tab.rawValue, systemImage: selectedTab == tab ? "checkmark" : tab.systemImage)
          }
        }
      } label: {
        HStack(spacing: HP.Space.sm) {
          Label(selectedTab.rawValue, systemImage: selectedTab.systemImage)
          Spacer(minLength: HP.Space.sm)
          Image(systemName: "chevron.up.chevron.down")
            .font(.caption.weight(.semibold))
        }
        .font(HP.Font.callout.weight(.semibold))
        .foregroundStyle(HP.Color.text)
        .padding(.horizontal, HP.Space.sm)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(
          RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
            .fill(HP.Color.surfaceRaised)
        )
        .overlay(
          RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
            .strokeBorder(HP.Color.borderStrong, lineWidth: 1)
            .allowsHitTesting(false)
        )
      }
      .accessibilityLabel("Admin section")
      .accessibilityValue(selectedTab.rawValue)
    }
  }

  @ViewBuilder
  private func memberSectionContent(_ context: HPScreenLayoutContext) -> some View {
    switch selectedTab {
    case .dashboard:
      dashboardCard(context)
    case .branding:
      VStack(alignment: .leading, spacing: HP.Space.md) {
        brandingCard
        bookingPolicyCard
      }
    case .features:
      featureFlagsCard
    case .billing:
      if appState.canAdminActiveOrg {
        billingSection(context)
      } else {
        HPCard {
          HPEmptyState(
            title: "Billing access required",
            message: "Billing controls are available to active organization owners and administrators only.",
            systemImage: "lock.shield"
          )
        }
      }
    case .finance:
      if appState.canAdminActiveOrg, let organizationId = appState.activeOrgId {
        FinanceDashboardView(
          organizationId: organizationId,
          organizationName: financeOrganizationName,
          platformSupportMode: false,
          embedded: true
        )
        .environmentObject(appState)
      } else {
        HPCard {
          HPEmptyState(
            title: "Finance access required",
            message: "Finance data is available to active organization owners and administrators only.",
            systemImage: "lock.shield"
          )
        }
      }
    case .communication:
      organizationOperationsSection(.communication)
    case .registration:
      organizationOperationsSection(.registration)
    case .analytics:
      organizationOperationsSection(.analytics)
    case .facilities:
      facilitiesCard(context)
    case .members:
      membersCard(context)
    case .teamOperations:
      OrgTeamOperationsAdminView()
    }
  }

  private var visibleTabs: [Tab] {
    Tab.allCases.filter {
      ($0 != .billing && $0 != .finance) || appState.canAdminActiveOrg
    }
  }

  @ViewBuilder
  private func organizationOperationsSection(
    _ section: OrganizationOperationsAdminView.Section
  ) -> some View {
    if appState.canAdminActiveOrg, let organizationId = appState.activeOrgId {
      OrganizationOperationsAdminView(section: section, organizationId: organizationId)
        .environmentObject(appState)
    } else {
      HPCard {
        HPEmptyState(
          title: "Organization access required",
          message: "This workspace is available to active organization owners and administrators.",
          systemImage: "lock.shield"
        )
      }
    }
  }

  private var financeOrganizationName: String {
    appState.availableOrganizations.first(where: { $0.id == appState.activeOrgId })?.name
      ?? settings?.display_name
      ?? "Organization"
  }

  private var modalSurface: some View {
    memberPresentation
  }

  private var errorPresentation: AnyView {
    AnyView(pageSurface
      .hpToast($toastText)
      .alert("Error", isPresented: errorPresented) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorText ?? "")
      }
    )
  }

  private var facilityPresentation: AnyView {
    AnyView(errorPresentation
    .sheet(item: $editingFacility) { draft in
      FacilityAdminEditorSheet(draft: draft) { saved in
        Task { await saveFacility(saved) }
      }
      .environmentObject(appState)
      #if os(macOS)
      .frame(minWidth: 560, minHeight: 560)
      #endif
    }
    .confirmationDialog(
      "Delete facility?",
      isPresented: facilityDeletionPresented,
      titleVisibility: .visible
    ) {
      if let facility = facilityPendingDeletion {
        Button("Delete \(facility.name)", role: .destructive) {
          facilityPendingDeletion = nil
          Task { await deleteFacility(facility) }
        }
      }
      Button("Cancel", role: .cancel) { facilityPendingDeletion = nil }
    } message: {
      if let facility = facilityPendingDeletion {
        Text("This permanently removes \(facility.name) and cannot be undone.")
      }
    }
    )
  }

  private var memberPresentation: AnyView {
    AnyView(facilityPresentation
    .sheet(isPresented: $isShowingCreateMember) {
      CreateOrgMemberSheet { draft in
        Task { await createMember(draft) }
      }
      #if os(macOS)
      .frame(minWidth: 560, minHeight: 520)
      #endif
    }
    .sheet(item: $editingMember) { draft in
      EditOrgMemberSheet(draft: draft) { saved in
        Task { await updateMember(saved) }
      }
      #if os(macOS)
      .frame(minWidth: 520, minHeight: 420)
      #endif
    }
    .sheet(isPresented: createPaymentRequestPresented) {
      PaymentRequestCreateSheet(
        organizationId: paymentRequestOrganizationId,
        supabase: appState.supabase,
        draft: $paymentRequestDraft,
        playerSearchText: $paymentRequestPlayerSearchText,
        isSubmitting: paymentRequestMutationId != nil,
        errorText: paymentRequestErrorText,
        onCreate: { eligiblePlayers in
          Task { await createPaymentRequest(eligiblePlayers: eligiblePlayers) }
        }
      )
      #if os(macOS)
      .frame(minWidth: 540, minHeight: 560)
      #endif
    }
    )
  }

  private var errorPresented: Binding<Bool> {
    Binding(
      get: { errorText != nil },
      set: { presented in
        if !presented { errorText = nil }
      }
    )
  }

  private var facilityDeletionPresented: Binding<Bool> {
    Binding(
      get: { facilityPendingDeletion != nil },
      set: { presented in
        if !presented { facilityPendingDeletion = nil }
      }
    )
  }

  private var header: some View {
    HPWorkspaceHeader(
      "Organization Admin Console",
      orgLabel: settings?.display_name ?? settings?.short_name ?? "Organization",
      context: activeOrgSubtitle,
      identity: organizationIdentity
    ) {
      HStack(spacing: HP.Space.xs) {
        if isLoading {
          ProgressView()
            .tint(HP.Color.accent)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Loading organization data")
        }
        if isSavingSettings {
          ProgressView()
            .tint(HP.Color.accent)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Saving organization settings")
        } else {
          HPStatusBadge(text: "Autosave on", kind: .success)
        }
      }
    }
  }

  private var organizationIdentity: HPIdentity {
    HPIdentity(
      name: settings?.display_name ?? settings?.short_name ?? "Organization",
      shortName: settings?.short_name ?? settings?.display_name ?? "Organization",
      primary: OrgColorCodec.color(from: primaryHex),
      secondary: OrgColorCodec.color(from: secondaryHex)
    )
  }

  private var supportOrganizationIdentity: HPIdentity {
    HPIdentity(
      name: platformSupportOrganization?.name ?? "Organization",
      shortName: platformSupportOrganization?.name ?? "Organization",
      primary: HP.Color.primary,
      secondary: HP.Color.bg
    )
  }

  private func dashboardCard(_ context: HPScreenLayoutContext) -> some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.md) {
          HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              Text(settings?.display_name ?? settings?.short_name ?? "Organization")
                .font(HP.Font.title)
                .foregroundStyle(HP.Color.text)
              Text("Admin dashboard")
                .font(HP.Font.callout)
                .foregroundStyle(HP.Color.textMuted)
            }
            Spacer()
            HPStatusBadge(text: "Live", kind: .success)
          }

          LazyVGrid(
            columns: context.gridColumns(compact: 2, regular: 3, wide: 4),
            spacing: HP.Space.sm
          ) {
            adminMetric("Members", value: adminMembers.count, symbol: "person.3.fill", color: HP.Color.accent)
            adminMetric("Players", value: playerCount, symbol: "figure.baseball", color: HP.Color.info)
            adminMetric("Coaches", value: coachCount, symbol: "person.2.fill", color: HP.Color.success)
            adminMetric("Pending bookings", value: pendingBookingCount, symbol: "clock.badge.exclamationmark", color: HP.Color.warning)
            adminMetric("Next 7 days", value: upcomingBookings.count, symbol: "calendar", color: HP.Color.info)
            adminMetric("Program plans", value: templateCount, symbol: "square.stack.3d.up.fill", color: HP.Color.success)
            adminMetric("Chat channels", value: channelCount, symbol: "bubble.left.and.bubble.right.fill", color: HP.Color.info)
            adminMetric("Active facilities", value: facilities.filter(\.is_active).count, symbol: "building.2.fill", color: HP.Color.success)
          }
        }
      }

      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Operations") {
            HPButton(
              title: "Refresh",
              systemImage: "arrow.clockwise",
              variant: .secondary,
              size: .sm
            ) {
              Task { await reload() }
            }
            .disabled(isLoading)
          }

          if upcomingBookings.isEmpty {
            HPEmptyState(
              title: "No upcoming bookings",
              message: "No facility bookings are scheduled in the next seven days.",
              systemImage: "calendar.badge.checkmark"
            )
          } else {
            let preview = Array(upcomingBookings.prefix(5))
            HPTable(
              columns: [
                HPColumn(title: "Booking"),
                HPColumn(title: "Starts"),
                HPColumn(title: "Status", alignment: .trailing),
              ],
              rows: preview.map { booking in
                HPTableRow(
                  id: booking.id,
                  cells: [
                    booking.title?.isEmpty == false ? booking.title! : booking.activity_type.capitalized,
                    booking.start_at.formatted(date: .abbreviated, time: .shortened),
                    "",
                  ],
                  badge: (booking.status.capitalized, bookingStatusKind(booking.status))
                )
              },
              layout: context.tableLayout
            )
          }
        }
      }

      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Quick management")
          Text("Manage the people, tools, and facility access for this organization.")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
          let actionLayout = context.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.sm))
          actionLayout {
            HPButton(
              title: "Members",
              systemImage: "person.2.badge.gearshape",
              variant: .secondary,
              fullWidth: context.isAccessibilitySize
            ) {
              selectedTab = .members
            }
            HPButton(
              title: "Features",
              systemImage: "switch.2",
              variant: .secondary,
              fullWidth: context.isAccessibilitySize
            ) {
              selectedTab = .features
            }
            HPButton(
              title: "Facilities",
              systemImage: "building.2",
              variant: .secondary,
              fullWidth: context.isAccessibilitySize
            ) {
              selectedTab = .facilities
            }
          }
        }
      }
    }
  }

  private func adminMetric(_ title: String, value: Int, symbol: String, color: Color) -> some View {
    HPCard(style: .flat) {
      VStack(alignment: .leading, spacing: HP.Space.xs) {
        Image(systemName: symbol)
          .foregroundStyle(color)
          .font(HP.Font.headline)
          .accessibilityHidden(true)
        Text("\(value)")
          .font(HP.Font.number())
          .foregroundStyle(HP.Color.text)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
        Text(title.uppercased())
          .font(HP.Font.eyebrow)
          .tracking(HP.Font.eyebrowTracking)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
  }

  private var playerCount: Int {
    adminMembers.filter { $0.role.lowercased() == "player" || $0.profile_role?.lowercased() == "player" }.count
  }

  private var coachCount: Int {
    adminMembers.filter { ["owner", "admin", "coach"].contains($0.role.lowercased()) }.count
  }

  private var pendingBookingCount: Int {
    upcomingBookings.filter { $0.status.lowercased() == "pending" }.count
  }

  private func bookingStatusKind(_ status: String) -> HPStatusKind {
    switch status.lowercased() {
    case "approved": return .success
    case "pending": return .warning
    case "denied", "cancelled": return .danger
    default: return .info
    }
  }

  private var activeOrgSubtitle: String {
    if let s = settings {
      return s.display_name ?? s.short_name ?? "Customize this organization"
    }
    if appState.activeOrgId != nil {
      return "Customize this organization"
    }
    return "No active organization found for this account."
  }

  private var brandingCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("Branding & Contact")

        VStack(alignment: .leading, spacing: HP.Space.sm) {
          Group {
            if let logoURL {
              AsyncImage(url: logoURL) { image in
                image.resizable().scaledToFill()
              } placeholder: {
                ProgressView()
              }
            } else {
              Image(systemName: "building.2.fill")
                .font(.title2)
                .foregroundStyle(HP.Color.accent)
            }
          }
          .frame(width: 64, height: 64)
          .background(HP.Color.surfaceRaised)
          .clipShape(RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
              .strokeBorder(HP.Color.border, lineWidth: 1)
              .allowsHitTesting(false)
          )

          VStack(alignment: .leading, spacing: 5) {
            PhotosPicker(selection: $logoPickerItem, matching: .images) {
              Label("Upload organization logo", systemImage: "photo.badge.plus")
            }
            .buttonStyle(HPButtonStyle(variant: .secondary, size: .md))
            .frame(minHeight: 44)
            .onChange(of: logoPickerItem) { _, item in
              guard let item else { return }
              Task { await loadLogoPickerItem(item) }
            }
            Text(pendingLogoJPEG == nil ? "Displays in branded organization surfaces." : "Logo selected and will save automatically.")
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.textMuted)
              .fixedSize(horizontal: false, vertical: true)
          }
        }

        HPFormField(label: "Display name", text: $displayName, placeholder: "Organization name")
        HPFormField(label: "Short name", text: $shortName, placeholder: "Short organization name")
        HPFormField(label: "Support email", text: $supportEmail, placeholder: "support@example.com")
        HPFormField(label: "Website host", text: $websiteHost, placeholder: "example.com")

        Text("Brand colors")
          .font(HP.Font.headline)
          .foregroundStyle(HP.Color.text)
          .padding(.top, HP.Space.xs)
        hexField("Primary", text: $primaryHex)
        hexField("Secondary", text: $secondaryHex)
        hexField("Accent", text: $accentHex)
      }
    }
  }

  private var featureFlagsCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Feature Flags")

        Toggle("Facilities / booking", isOn: $featureFacilities)
          .frame(minHeight: 44)
        Toggle("Chat", isOn: $featureChat)
          .frame(minHeight: 44)
        Toggle("Programs", isOn: $featurePrograms)
          .frame(minHeight: 44)
        Toggle("Testing", isOn: $featureTesting)
          .frame(minHeight: 44)
        Toggle("BP analysis", isOn: $featureBPAnalysis)
          .frame(minHeight: 44)
        Toggle("Parent portal", isOn: $featureParentPortal)
          .frame(minHeight: 44)
        Toggle("Billing/payment requests", isOn: $featureBilling)
          .frame(minHeight: 44)
        Divider().overlay(HP.Color.border)
        Text("Team permissions")
          .font(HP.Font.headline)
          .foregroundStyle(HP.Color.text)
        Toggle("Coaches can view all teams", isOn: $coachesCanViewAllTeams)
          .frame(minHeight: 44)
        Toggle("Limit coach assignments and evaluations to their own team", isOn: $restrictCoachActionsToTeam)
          .frame(minHeight: 44)
        Toggle("Allow coaches to manage team assignments", isOn: $coachesCanManageTeams)
          .frame(minHeight: 44)
        Text("Organization admins always manage all teams. Coaches can be granted team management separately.")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
      .font(HP.Font.callout)
      .foregroundStyle(HP.Color.text)
      .tint(HP.Color.accent)
    }
  }

  private func billingCard(_ context: HPScreenLayoutContext) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("Home Plate Subscription") {
          HPButton(
            title: "Refresh",
            systemImage: "arrow.clockwise",
            variant: .secondary,
            size: .sm
          ) {
            Task { await refreshBilling() }
          }
          .disabled(isBillingLoading || billingAction != nil)
        }

        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Home Plate Organization")
              .font(HP.Font.headline)
              .foregroundStyle(HP.Color.text)
            Text("$200/month")
              .font(HP.Font.number(.callout))
              .foregroundStyle(HP.Color.textMuted)
          }
          Spacer()
          if let subscription = organizationSubscription {
            HPStatusBadge(
              text: subscription.status.replacingOccurrences(of: "_", with: " ").capitalized,
              kind: billingStatusKind(subscription.status)
            )
          } else {
            HPStatusBadge(text: "No subscription", kind: .warning)
          }
        }

        if isBillingLoading {
          HPLoadingState(text: "Loading subscription status…")
        } else if let billingErrorText {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            Text(billingErrorText)
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.danger)
              .fixedSize(horizontal: false, vertical: true)
            HPButton(title: "Try Again", systemImage: "arrow.clockwise", variant: .secondary) {
              Task { await refreshBilling() }
            }
          }
        } else if let subscription = organizationSubscription {
          VStack(alignment: .leading, spacing: 6) {
            if let periodEnd = subscription.current_period_end {
              Text(subscription.cancel_at_period_end ? "Access ends" : "Next billing date")
                .font(HP.Font.caption)
                .foregroundStyle(HP.Color.textMuted)
              Text(displayBillingDate(periodEnd))
                .font(HP.Font.callout.weight(.semibold))
                .foregroundStyle(HP.Color.text)
            } else {
              Text("Stripe has not reported a billing period end yet.")
                .font(HP.Font.caption)
                .foregroundStyle(HP.Color.textMuted)
            }
            if subscription.cancel_at_period_end {
              Label("Cancellation is scheduled at the end of the current period.", systemImage: "calendar.badge.exclamationmark")
                .font(HP.Font.caption)
                .foregroundStyle(HP.Color.warning)
            }
          }
        } else {
          Text("No Stripe subscription has been synchronized for this organization yet.")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
        }

        let actionLayout = context.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
          : AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.sm))
        actionLayout {
          HPButton(
            title: billingAction == .checkout ? "Opening Checkout…" : "Subscribe — $200/month",
            systemImage: "creditcard",
            variant: .secondary,
            isLoading: billingAction == .checkout,
            fullWidth: context.isAccessibilitySize
          ) {
            Task { await beginCheckout() }
          }
          .disabled(isCurrentSubscription || billingAction != nil || isBillingLoading)

          HPButton(
            title: billingAction == .portal ? "Opening Portal…" : "Manage Billing",
            systemImage: "arrow.up.right.square",
            variant: .secondary,
            isLoading: billingAction == .portal,
            fullWidth: context.isAccessibilitySize
          ) {
            Task { await openBillingPortal() }
          }
          .disabled(billingAction != nil || isBillingLoading)
        }

        Text("Payment status is updated only after Stripe sends its webhook. Returning from the browser refreshes this screen but does not confirm payment by itself.")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func billingSection(_ context: HPScreenLayoutContext) -> some View {
    Group {
      if appState.canAdminActiveOrg {
        VStack(alignment: .leading, spacing: HP.Space.md) {
          customerPaymentsCard(context)
          billingCard(context)
        }
      } else {
        HPCard {
          HPEmptyState(
            title: "Billing access required",
            message: "Only an active organization owner or administrator can open these controls.",
            systemImage: "lock.shield"
          )
        }
      }
    }
  }

  private func customerPaymentsCard(_ context: HPScreenLayoutContext) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("Customer Payments") {
          HPButton(
            title: "Refresh Status",
            systemImage: "arrow.clockwise",
            variant: .secondary,
            size: .sm
          ) {
            Task { await refreshConnectStatus() }
          }
          .disabled(isConnectLoading || connectAction != nil)
        }

        let statusLayout = context.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
          : AnyLayout(HStackLayout(alignment: .top, spacing: HP.Space.sm))
        statusLayout {
          Image(systemName: connectStatusSymbol)
            .font(.title2)
            .foregroundStyle(connectStatusColor)
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 4) {
            Text(connectStatusTitle)
              .font(HP.Font.headline)
              .foregroundStyle(HP.Color.text)
            Text(connectStatusDetail)
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.textMuted)
              .fixedSize(horizontal: false, vertical: true)
          }
          if !context.isAccessibilitySize { Spacer(minLength: HP.Space.sm) }
          if let connectStatus {
            HPStatusBadge(
              text: connectStatus.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized,
              kind: connectStatusKind
            )
          }
        }

        if isConnectLoading {
          HPLoadingState(text: "Checking Stripe account status…")
        } else if let connectErrorText {
          Text(connectErrorText)
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.danger)
            .fixedSize(horizontal: false, vertical: true)
        }

        if connectStatus?.status != .ready {
          HPButton(
            title: connectAction == .onboarding ? "Opening Stripe…" : connectOnboardingButtonTitle,
            systemImage: "link",
            variant: .secondary,
            isLoading: connectAction == .onboarding,
            fullWidth: context.isAccessibilitySize
          ) {
            Task { await beginConnectOnboarding() }
          }
          .disabled(isConnectLoading || connectAction != nil)
        }

        Text("Stripe onboarding opens in your system browser. Home Plate confirms readiness only after refreshing Stripe's server status.")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)

        Divider().overlay(HP.Color.border)
        paymentRequestsSection(context)
      }
    }
  }

  @ViewBuilder
  private func paymentRequestsSection(_ context: HPScreenLayoutContext) -> some View {
    HPSectionHeader("Payment Requests") {
      HPButton(title: "Create Payment Request", systemImage: "plus", variant: .primary, size: .sm) {
        guard canManagePaymentRequests, paymentRequestMutationId == nil else {
          return
        }
        paymentRequestDraft = SDPaymentRequestCreateDraft()
        paymentRequestPlayerSearchText = ""
        paymentRequestErrorText = nil
        paymentRequestCreatePresentation.present()
      }
      .disabled(!canManagePaymentRequests || paymentRequestMutationId != nil)
    }

    #if DEBUG
    if let paymentRequestCreateDisabledReason {
      Text(paymentRequestCreateDisabledReason)
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
        .accessibilityIdentifier("payment-request-create-disabled-reason")
    }
    #endif

    Text("Create one-time internal requests now. Stripe Checkout is not enabled until the next phase.")
      .font(HP.Font.caption)
      .foregroundStyle(HP.Color.textMuted)
      .fixedSize(horizontal: false, vertical: true)

    if let paymentRequestRosterErrorText = paymentRequestRosterState.errorMessage {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        Text(paymentRequestRosterErrorText)
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.danger)
          .fixedSize(horizontal: false, vertical: true)
        HPButton(title: "Refresh Eligible Players", systemImage: "arrow.clockwise", variant: .secondary) {
          Task { await refreshEligiblePaymentRequestPlayers() }
        }
      }
    }

    if isPaymentRequestLoading {
      HPLoadingState(text: "Loading payment requests…")
    } else if let paymentRequestErrorText, !paymentRequestCreatePresentation.isPresented {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        Text(paymentRequestErrorText)
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.danger)
          .fixedSize(horizontal: false, vertical: true)
        HPButton(title: "Try Again", systemImage: "arrow.clockwise", variant: .secondary) {
          Task { await refreshPaymentRequests() }
        }
      }
    } else if paymentRequestState.requests.isEmpty {
      HPEmptyState(
        title: "No payment requests",
        message: activePlayerMembers.isEmpty
          ? (isPlatformSupportMode
            ? "No eligible active players are available in this organization."
            : "Add an active player before creating a payment request.")
          : "No payment requests yet.",
        systemImage: "creditcard"
      )
    } else {
      ForEach(paymentRequestState.requests) { request in
        let rowLayout = context.isExpanded
          ? AnyLayout(HStackLayout(alignment: .top, spacing: HP.Space.md))
          : AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
        rowLayout {
          VStack(alignment: .leading, spacing: 4) {
            Text(request.title)
              .font(HP.Font.headline)
              .foregroundStyle(HP.Color.text)
              .fixedSize(horizontal: false, vertical: true)
            Text(request.player_name ?? playerName(request.player_id))
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.textMuted)
            Text(request.money?.formatted() ?? "Amount unavailable")
              .font(HP.Font.number(.caption))
              .foregroundStyle(HP.Color.textMuted)
            if let dueDate = request.due_date {
              Text("Due \(displayPaymentRequestDate(dueDate))")
                .font(HP.Font.caption)
                .foregroundStyle(HP.Color.textMuted)
            }
          }
          if context.isExpanded { Spacer(minLength: HP.Space.sm) }
          VStack(alignment: context.isExpanded ? .trailing : .leading, spacing: HP.Space.xs) {
            HPStatusBadge(
              text: request.status.rawValue.capitalized,
              kind: paymentRequestStatusKind(request.status)
            )
            if request.status == .open {
              HPButton(title: "Cancel", variant: .destructive, size: .sm) {
                Task { await cancelPaymentRequest(request) }
              }
              .disabled(paymentRequestMutationId != nil || !canManagePaymentRequests)
            }
          }
        }
        .padding(.vertical, HP.Space.xs)
        Divider().overlay(HP.Color.border.opacity(0.5))
      }
    }
  }

  private var activePlayerMembers: [SDPaymentRequestEligiblePlayer] {
    paymentRequestRosterState.players(for: paymentRequestOrganizationId)
  }

  private var connectStatusTitle: String {
    switch connectStatus?.status {
    case .none, .notConnected: return "Stripe not connected"
    case .onboardingIncomplete: return "Finish Stripe setup"
    case .requirementsDue: return "Information required"
    case .ready: return "Stripe payments ready"
    case .restricted: return "Stripe account restricted"
    }
  }

  private var connectStatusDetail: String {
    switch connectStatus?.status {
    case .none, .notConnected:
      return "Connect your organization’s Stripe account before accepting customer payments."
    case .onboardingIncomplete:
      return "Continue Stripe's hosted setup to complete your organization account."
    case .requirementsDue:
      let count = (connectStatus?.currently_due.count ?? 0) + (connectStatus?.past_due.count ?? 0)
      return count == 1 ? "Stripe needs one more item from your organization." : "Stripe needs \(count) more items from your organization."
    case .ready:
      return "Charges and payouts are enabled, with no blocking past-due requirements."
    case .restricted:
      return "Stripe has restricted this account. Continue setup to review the required action."
    }
  }

  private var connectOnboardingButtonTitle: String {
    connectStatus?.status == .notConnected || connectStatus == nil
      ? "Connect with Stripe"
      : "Continue Stripe Setup"
  }

  private var connectStatusColor: Color {
    switch connectStatus?.status {
    case .ready: return HP.Color.success
    case .restricted: return HP.Color.danger
    case .requirementsDue, .onboardingIncomplete: return HP.Color.warning
    case .none, .notConnected: return HP.Color.accent
    }
  }

  private var connectStatusKind: HPStatusKind {
    switch connectStatus?.status {
    case .ready: return .success
    case .restricted: return .danger
    case .requirementsDue, .onboardingIncomplete: return .warning
    case .none, .notConnected: return .info
    }
  }

  private var connectStatusSymbol: String {
    switch connectStatus?.status {
    case .ready: return "checkmark.seal.fill"
    case .restricted: return "exclamationmark.octagon.fill"
    case .requirementsDue: return "person.text.rectangle"
    case .onboardingIncomplete: return "hourglass"
    case .none, .notConnected: return "link.badge.plus"
    }
  }

  private var isCurrentSubscription: Bool {
    guard let status = organizationSubscription?.status.lowercased() else { return false }
    return status == "active" || status == "trialing"
  }

  private func billingStatusKind(_ status: String) -> HPStatusKind {
    switch status.lowercased() {
    case "active": return .success
    case "trialing", "incomplete": return .warning
    case "past_due", "unpaid", "incomplete_expired", "canceled": return .danger
    default: return .info
    }
  }

  private func displayBillingDate(_ rawValue: String) -> String {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = iso.date(from: rawValue) {
      return date.formatted(date: .abbreviated, time: .shortened)
    }
    return rawValue
  }

  private var bookingPolicyCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("Booking Policy")

        HPFormField(
          label: "Default duration",
          text: $defaultDuration,
          placeholder: "60",
          helper: "Minutes"
        )
        HPFormField(
          label: "Minimum duration",
          text: $minDuration,
          placeholder: "30",
          helper: "Minutes"
        )
        HPFormField(
          label: "Maximum duration",
          text: $maxDuration,
          placeholder: "120",
          helper: "Minutes"
        )
        Toggle("Players can request bookings", isOn: $allowPlayerRequests)
          .frame(minHeight: 44)
        Toggle("Bookings require coach approval", isOn: $requireCoachApproval)
          .frame(minHeight: 44)
      }
      .font(HP.Font.callout)
      .foregroundStyle(HP.Color.text)
      .tint(HP.Color.accent)
    }
  }

  private func facilitiesCard(_ context: HPScreenLayoutContext) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("Facility Resources") {
          HPButton(title: "Add", systemImage: "plus", variant: .primary, size: .sm) {
            editingFacility = FacilityDraft.new(orgId: appState.activeOrgId)
          }
        }

        if facilities.isEmpty {
          HPEmptyState(
            title: "No facilities configured",
            message: "Add a resource to make it available for scheduling.",
            systemImage: "building.2"
          )
        } else {
          ForEach(facilities) { facility in
            let rowLayout = context.isExpanded
              ? AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.md))
              : AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
            rowLayout {
              HStack(alignment: .top, spacing: HP.Space.sm) {
                Circle()
                  .fill(colorFromHex(facility.color_hex) ?? HP.Color.accent)
                  .frame(width: 12, height: 12)
                  .padding(.top, 5)
                  .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                  Text(facility.name)
                    .font(HP.Font.headline)
                    .foregroundStyle(HP.Color.text)
                    .fixedSize(horizontal: false, vertical: true)
                  Text("\(facility.resource_type ?? "resource") • capacity \(facility.capacity ?? 1) • sort \(facility.sort_order)")
                    .font(HP.Font.caption)
                    .foregroundStyle(HP.Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                }
              }
              if context.isExpanded { Spacer(minLength: HP.Space.sm) }
              HPStatusBadge(text: facility.is_active ? "Active" : "Hidden", kind: facility.is_active ? .success : .warning)
              let actionLayout = context.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.xs))
                : AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.xs))
              actionLayout {
                HPButton(
                  title: "Edit",
                  variant: .secondary,
                  size: .sm,
                  fullWidth: context.isAccessibilitySize
                ) {
                  editingFacility = FacilityDraft(facility: facility, orgId: appState.activeOrgId)
                }
                HPButton(
                  title: "Delete",
                  systemImage: "trash",
                  variant: .destructive,
                  size: .sm,
                  fullWidth: context.isAccessibilitySize
                ) {
                  facilityPendingDeletion = facility
                }
                .help("Delete \(facility.name)")
              }
            }
            .padding(.vertical, HP.Space.xs)
            Divider().overlay(HP.Color.border.opacity(0.5))
          }
        }
      }
    }
  }

  private func membersCard(_ context: HPScreenLayoutContext) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("Users & Org Access") {
          let actionLayout = context.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.xs))
          actionLayout {
            HPButton(title: "Refresh", systemImage: "arrow.clockwise", variant: .secondary, size: .sm) {
              Task { await reload() }
            }
            HPButton(title: "Create User", systemImage: "person.badge.plus", variant: .primary, size: .sm) {
              isShowingCreateMember = true
            }
          }
        }

        Text("Create organization-specific accounts, assign roles, disable access, and update the username used by the org login screen.")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)

        if adminMembers.isEmpty {
          HPEmptyState(
            title: "No memberships visible",
            message: "Organization members will appear here after they are added.",
            systemImage: "person.2"
          )
        } else {
          ForEach(adminMembers) { member in
            let rowLayout = context.isExpanded
              ? AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.md))
              : AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
            rowLayout {
              VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName)
                  .font(HP.Font.headline)
                  .foregroundStyle(HP.Color.text)
                  .fixedSize(horizontal: false, vertical: true)
                Text(member.email ?? member.user_id.uuidString)
                  .font(HP.Font.caption)
                  .foregroundStyle(HP.Color.textMuted)
                  .fixedSize(horizontal: false, vertical: true)
                if let username = member.username {
                  Text("@\(username)")
                    .font(HP.Font.caption)
                    .foregroundStyle(HP.Color.textMuted)
                }
              }
              if context.isExpanded { Spacer(minLength: HP.Space.sm) }
              HStack(spacing: HP.Space.xs) {
                HPStatusBadge(text: member.status.capitalized, kind: member.status == "active" ? .success : .warning)
                HPStatusBadge(text: member.role.capitalized, kind: member.isAdmin ? .success : .info)
              }
              HPButton(
                title: "Edit",
                variant: .secondary,
                size: .sm,
                fullWidth: context.isAccessibilitySize
              ) {
                editingMember = MemberDraft(member: member)
              }
            }
            .padding(.vertical, HP.Space.xs)
            Divider().overlay(HP.Color.border.opacity(0.5))
          }
        }
      }
    }
  }

  private func hexField(_ label: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label.uppercased())
        .font(HP.Font.eyebrow)
        .tracking(HP.Font.eyebrowTracking)
        .foregroundStyle(HP.Color.textMuted)
      HStack(spacing: HP.Space.sm) {
        ColorPicker("\(label) color", selection: colorBinding(text))
          .labelsHidden()
          .frame(width: 44, height: 44)
        RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous)
          .fill(OrgColorCodec.color(from: text.wrappedValue))
          .overlay(
            RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous)
              .strokeBorder(HP.Color.borderStrong, lineWidth: 1)
              .allowsHitTesting(false)
          )
          .frame(width: 44, height: 44)
          .accessibilityHidden(true)
        TextField("#RRGGBB", text: text)
          .textFieldStyle(.plain)
          .font(HP.Font.body)
          .foregroundStyle(HP.Color.text)
          .padding(.horizontal, HP.Space.sm)
          .frame(minHeight: 44)
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
    }
  }

  private func reload() async {
    guard appState.canAdminActiveOrg else {
      clearAdministrativeData()
      return
    }
    guard let supabase = appState.supabase else { return }
    guard let orgId = appState.activeOrgId else {
      errorText = "No active organization found."
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      let loadedSettings = try await supabase.fetchOrgSettings(orgId: orgId)
      settings = loadedSettings
      facilities = try await supabase.listFacilities(orgId: orgId, includeInactive: true)
      adminMembers = try await supabase.adminListOrgMembers(orgId: orgId)
      let now = Date()
      let horizon = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
      upcomingBookings = (try? await supabase.listFacilityBookings(rangeStart: now, rangeEnd: horizon, orgId: orgId)) ?? []
      templateCount = (try? await supabase.listMyCoachTemplates().count) ?? 0
      channelCount = (try? await supabase.listChatChannels(organizationId: orgId).count) ?? 0

      applySettingsToFields(loadedSettings)
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func validateAuthorizationAndLoad(refreshAllData: Bool = true) async {
    let requestedOrgId = paymentRequestOrganizationId
    transitionPaymentRequestContext(to: requestedOrgId)
    isCheckingAuthorization = true
    authorizationValidatedOrgId = nil

    guard let requestedOrgId, hasSelectedActivePaymentRequestOrganization else {
      isCheckingAuthorization = false
      clearPaymentRequestData()
      return
    }

    authorizationValidatedOrgId = requestedOrgId
    isCheckingAuthorization = false
    let loadToken = beginCustomerPaymentsLoad(organizationId: requestedOrgId)
    async let customerPaymentsLoad: Void = loadCustomerPayments(
      organizationId: requestedOrgId,
      loadToken: loadToken
    )

    if isPlatformSupportMode {
      await customerPaymentsLoad
      return
    }

    await appState.refreshOrgContext()
    guard paymentRequestOrganizationId == requestedOrgId else {
      await customerPaymentsLoad
      return
    }
    guard appState.canAdminActiveOrg else {
      clearAdministrativeData(clearPaymentRequests: false)
      await customerPaymentsLoad
      return
    }

    if refreshAllData {
      await reload()
    }
    await refreshBilling()
    if refreshAllData || didOpenConnectOnboarding {
      didOpenConnectOnboarding = false
      await refreshConnectStatus()
    }
    await customerPaymentsLoad
  }

  private func beginCustomerPaymentsLoad(organizationId: UUID) -> UUID {
    let loadToken = UUID()
    paymentRequestLoadToken = loadToken
    paymentRequestState.clear()
    paymentRequestErrorText = nil
    isPaymentRequestLoading = false
    paymentRequestRosterState = .idle
    return loadToken
  }

  private func loadCustomerPayments(organizationId: UUID, loadToken: UUID) async {
    await SDPaymentRequestManagementLoadCoordinator.load(
      listManage: {
        await refreshPaymentRequests(
          orgId: organizationId,
          loadToken: loadToken
        )
      },
      listEligiblePlayers: {
        await refreshEligiblePaymentRequestPlayers(
          orgId: organizationId,
          loadToken: loadToken
        )
      }
    )
  }

  private func logPaymentRequestRosterResult(
    organizationId: UUID,
    displayedPlayerCount: Int,
    discardedAsStale: Bool
  ) {
    #if DEBUG
    print(
      "[PaymentRequestRoster] org_id=\(organizationId.uuidString) "
        + "final_displayed_player_count=\(displayedPlayerCount) "
        + "response_discarded_as_stale=\(discardedAsStale)"
    )
    #endif
  }

  private func clearAdministrativeData(clearPaymentRequests: Bool = true) {
    settingsSaveTask?.cancel()
    settings = nil
    facilities = []
    adminMembers = []
    if clearPaymentRequests {
      clearPaymentRequestData()
    }
    upcomingBookings = []
    templateCount = 0
    channelCount = 0
    organizationSubscription = nil
    connectStatus = nil
    billingErrorText = nil
    connectErrorText = nil
    editingFacility = nil
    editingMember = nil
    isShowingCreateMember = false
  }

  private func transitionPaymentRequestRoster(to organizationId: UUID?) {
    guard SDPaymentRequestPlayerRoster.organizationChanged(
      from: paymentRequestContextOrgId,
      to: organizationId
    ) else { return }
    paymentRequestContextOrgId = organizationId
    paymentRequestRosterState = .idle
    paymentRequestPlayerSearchText = ""
    paymentRequestDraft.selectedPlayerUserIds.removeAll()
  }

  private func transitionPaymentRequestContext(to organizationId: UUID?) {
    guard SDPaymentRequestPlayerRoster.organizationChanged(
      from: paymentRequestContextOrgId,
      to: organizationId
    ) else { return }
    transitionPaymentRequestRoster(to: organizationId)
    paymentRequestDraft = SDPaymentRequestCreateDraft()
    paymentRequestState.clear()
    paymentRequestLoadToken = nil
    paymentRequestErrorText = nil
    isPaymentRequestLoading = false
    paymentRequestCreatePresentation.dismiss()
    paymentRequestMutationId = nil
  }

  private func clearPaymentRequestData() {
    resetPaymentRequestRoster()
    paymentRequestState.clear()
    paymentRequestLoadToken = nil
    paymentRequestErrorText = nil
    isPaymentRequestLoading = false
    paymentRequestCreatePresentation.dismiss()
    paymentRequestMutationId = nil
  }

  private func resetPaymentRequestRoster() {
    paymentRequestRosterState = .idle
    paymentRequestContextOrgId = nil
    paymentRequestPlayerSearchText = ""
    paymentRequestDraft.selectedPlayerUserIds.removeAll()
  }

  private func refreshEligiblePaymentRequestPlayers(
    orgId requestedOrgId: UUID? = nil,
    loadToken requestedLoadToken: UUID? = nil
  ) async {
    guard let supabase = appState.supabase,
          let activeOrgId = paymentRequestOrganizationId else {
      resetPaymentRequestRoster()
      return
    }
    let orgId = requestedOrgId ?? activeOrgId
    guard orgId == activeOrgId,
          hasSelectedActivePaymentRequestOrganization else { return }
    transitionPaymentRequestContext(to: orgId)
    let rosterRequestId: UUID
    if let requestedLoadToken {
      guard paymentRequestLoadToken == requestedLoadToken else { return }
      rosterRequestId = requestedLoadToken
    } else {
      rosterRequestId = UUID()
    }
    paymentRequestRosterState.beginLoading(
      organizationId: orgId,
      requestId: rosterRequestId
    )
    defer {
      if paymentRequestContextOrgId == orgId {
        paymentRequestRosterState.finishLoadingIfNeeded(
          organizationId: orgId,
          requestId: rosterRequestId
        )
      }
    }
    do {
      let loaded = try await supabase.listEligiblePaymentRequestPlayers(orgId: orgId)
      guard SDPaymentRequestRosterResponseContext.matchesSelectedOrganization(
        responseOrganizationId: orgId,
        selectedOrganizationId: paymentRequestOrganizationId,
        rosterContextOrganizationId: paymentRequestContextOrgId
      ) else {
        logPaymentRequestRosterResult(
          organizationId: orgId,
          displayedPlayerCount: activePlayerMembers.count,
          discardedAsStale: true
        )
        return
      }
      let eligible = SDPaymentRequestPlayerRoster.eligiblePlayers(
        from: loaded,
        organizationId: orgId
      )
      guard paymentRequestRosterState.apply(
        eligible,
        organizationId: orgId,
        requestId: rosterRequestId
      ) else {
        logPaymentRequestRosterResult(
          organizationId: orgId,
          displayedPlayerCount: activePlayerMembers.count,
          discardedAsStale: true
        )
        return
      }
      paymentRequestDraft.selectedPlayerUserIds = SDPaymentRequestPlayerRoster.reconcile(
        selectedPlayerUserIds: paymentRequestDraft.selectedPlayerUserIds,
        eligiblePlayers: eligible
      )
      logPaymentRequestRosterResult(
        organizationId: orgId,
        displayedPlayerCount: activePlayerMembers.count,
        discardedAsStale: false
      )
    } catch {
      if error is CancellationError { return }
      guard SDPaymentRequestRosterResponseContext.matchesSelectedOrganization(
        responseOrganizationId: orgId,
        selectedOrganizationId: paymentRequestOrganizationId,
        rosterContextOrganizationId: paymentRequestContextOrgId
      ) else {
        logPaymentRequestRosterResult(
          organizationId: orgId,
          displayedPlayerCount: activePlayerMembers.count,
          discardedAsStale: true
        )
        return
      }
      let message = "Eligible players could not be loaded. \(error.localizedDescription)"
      guard paymentRequestRosterState.fail(
        message: message,
        organizationId: orgId,
        requestId: rosterRequestId
      ) else {
        logPaymentRequestRosterResult(
          organizationId: orgId,
          displayedPlayerCount: activePlayerMembers.count,
          discardedAsStale: true
        )
        return
      }
      paymentRequestDraft.selectedPlayerUserIds.removeAll()
    }
  }

  private func refreshBilling() async {
    guard appState.canAdminActiveOrg else {
      organizationSubscription = nil
      billingErrorText = nil
      return
    }
    guard let supabase = appState.supabase, let orgId = appState.activeOrgId else {
      organizationSubscription = nil
      billingErrorText = "No active organization is available for billing."
      return
    }
    isBillingLoading = true
    defer { isBillingLoading = false }
    do {
      organizationSubscription = try await supabase.fetchLatestOrgSubscription(orgId: orgId)
      billingErrorText = nil
    } catch {
      organizationSubscription = nil
      billingErrorText = "Subscription status could not be loaded. \(error.localizedDescription)"
    }
  }

  private func refreshConnectStatus() async {
    guard appState.canAdminActiveOrg else {
      connectStatus = nil
      connectErrorText = nil
      return
    }
    guard let supabase = appState.supabase, let orgId = appState.activeOrgId else {
      connectStatus = nil
      connectErrorText = "No active organization is available for customer payments."
      return
    }
    isConnectLoading = true
    connectAction = .refresh
    defer {
      isConnectLoading = false
      connectAction = nil
    }
    do {
      connectStatus = try await supabase.getStripeConnectAccountStatus(orgId: orgId)
      connectErrorText = nil
    } catch {
      connectErrorText = "Stripe account status could not be refreshed. \(error.localizedDescription)"
    }
  }

  private func refreshPaymentRequests(
    orgId requestedOrgId: UUID? = nil,
    loadToken requestedLoadToken: UUID? = nil
  ) async {
    guard let supabase = appState.supabase,
          let activeOrgId = paymentRequestOrganizationId else {
      paymentRequestState.clear()
      paymentRequestErrorText = nil
      return
    }
    let orgId = requestedOrgId ?? activeOrgId
    guard orgId == activeOrgId,
          hasSelectedActivePaymentRequestOrganization else { return }
    let loadToken: UUID
    if let requestedLoadToken {
      guard paymentRequestLoadToken == requestedLoadToken else { return }
      loadToken = requestedLoadToken
    } else if let currentLoadToken = paymentRequestLoadToken {
      loadToken = currentLoadToken
    } else {
      loadToken = UUID()
      paymentRequestLoadToken = loadToken
    }
    paymentRequestState.beginLoading(organizationId: orgId)
    isPaymentRequestLoading = true
    defer {
      if paymentRequestState.organizationId == orgId,
         paymentRequestLoadToken == loadToken {
        isPaymentRequestLoading = false
      }
    }
    do {
      let requests = try await supabase.listManagedPaymentRequests(orgId: orgId)
      guard paymentRequestOrganizationId == orgId,
            paymentRequestContextOrgId == orgId,
            paymentRequestLoadToken == loadToken else { return }
      paymentRequestState.apply(requests, organizationId: orgId)
      paymentRequestErrorText = nil
    } catch {
      guard paymentRequestState.organizationId == orgId,
            paymentRequestLoadToken == loadToken else { return }
      paymentRequestErrorText = "Payment requests could not be loaded. \(error.localizedDescription)"
    }
  }

  private func createPaymentRequest(eligiblePlayers: [SDPaymentRequestEligiblePlayer]) async {
    guard paymentRequestMutationId == nil else { return }
    guard canManagePaymentRequests,
          let supabase = appState.supabase,
          let orgId = paymentRequestOrganizationId else {
      paymentRequestErrorText = "An active organization owner, administrator, or verified platform-support session is required."
      return
    }
    paymentRequestDraft.selectedPlayerUserIds = Set(SDPaymentRequestPlayerRoster.payloadPlayerUserIds(
      selectedPlayerUserIds: paymentRequestDraft.selectedPlayerUserIds,
      eligiblePlayers: eligiblePlayers
    ))
    if let validationError = paymentRequestDraft.validationError {
      paymentRequestErrorText = validationError
      return
    }

    guard let payload = paymentRequestDraft.prepareCreatePayload(orgId: orgId) else {
      paymentRequestErrorText = paymentRequestDraft.validationError ?? "Payment request is invalid."
      return
    }
    #if DEBUG
    print(
      "[PaymentRequestCreate] org_id=\(orgId.uuidString) "
        + "selected_player_user_ids=\(payload.player_ids.map(\.uuidString).sorted()) "
        + "selected_player_count=\(payload.player_ids.count)"
    )
    #endif
    let operationId = payload.idempotency_key
    paymentRequestMutationId = operationId
    defer {
      if paymentRequestMutationId == operationId {
        paymentRequestMutationId = nil
      }
    }
    do {
      let response = try await supabase.createPaymentRequests(payload: payload)
      guard paymentRequestOrganizationId == orgId else { return }
      paymentRequestDraft.completeOperation(idempotencyKey: operationId)
      paymentRequestCreatePresentation.dismiss()
      paymentRequestErrorText = nil
      if response.reused {
        toastText = response.requests.count == 1
          ? "Existing payment request recovered."
          : "Existing payment requests recovered."
      } else {
        toastText = response.created_count == 1
          ? "Payment request created."
          : "\(response.created_count) payment requests created."
      }
      await refreshPaymentRequests()
    } catch {
      guard paymentRequestOrganizationId == orgId else { return }
      paymentRequestErrorText = "Payment request could not be created. \(error.localizedDescription)"
      if let functionError = error as? SDEdgeFunctionHTTPError,
         functionError.code == "active_player_membership_required" {
        await refreshEligiblePaymentRequestPlayers(orgId: orgId)
      }
    }
  }

  private func cancelPaymentRequest(_ request: SDPaymentRequest) async {
    guard paymentRequestMutationId == nil else { return }
    guard canManagePaymentRequests,
          let supabase = appState.supabase,
          let orgId = paymentRequestOrganizationId,
          request.org_id == orgId else {
      paymentRequestErrorText = "An active organization owner, administrator, or verified platform-support session is required."
      return
    }
    paymentRequestMutationId = request.id
    defer {
      if paymentRequestMutationId == request.id {
        paymentRequestMutationId = nil
      }
    }
    do {
      _ = try await supabase.cancelPaymentRequest(orgId: orgId, requestId: request.id)
      guard paymentRequestOrganizationId == orgId else { return }
      toastText = "Payment request canceled."
      await refreshPaymentRequests()
    } catch {
      guard paymentRequestOrganizationId == orgId else { return }
      paymentRequestErrorText = "Payment request could not be canceled. \(error.localizedDescription)"
    }
  }

  private func playerName(_ id: UUID) -> String {
    activePlayerMembers.first(where: { $0.userId == id })?.displayName ?? "Player"
  }

  private func paymentRequestStatusKind(_ status: SDPaymentRequestStatus) -> HPStatusKind {
    switch status {
    case .open: return .warning
    case .canceled: return .neutral
    case .paid: return .success
    }
  }

  private func displayPaymentRequestDate(_ value: String) -> String {
    let input = DateFormatter()
    input.locale = Locale(identifier: "en_US_POSIX")
    input.dateFormat = "yyyy-MM-dd"
    guard let date = input.date(from: value) else { return value }
    return date.formatted(date: .abbreviated, time: .omitted)
  }

  private func beginConnectOnboarding() async {
    guard appState.canAdminActiveOrg,
          let supabase = appState.supabase,
          let orgId = appState.activeOrgId else {
      connectErrorText = "Only an organization owner or administrator can connect Stripe."
      return
    }
    connectAction = .onboarding
    defer { connectAction = nil }
    do {
      let url = try await supabase.createStripeConnectOnboardingLink(orgId: orgId)
      didOpenConnectOnboarding = true
      openBillingURL(url)
      connectErrorText = nil
    } catch {
      connectErrorText = "Stripe setup could not be opened. \(error.localizedDescription)"
    }
  }

  private func beginCheckout() async {
    guard appState.canAdminActiveOrg,
          let supabase = appState.supabase,
          let orgId = appState.activeOrgId else {
      billingErrorText = "Only organization owners can start billing for the active organization."
      return
    }
    billingAction = .checkout
    defer { billingAction = nil }
    do {
      let url = try await supabase.createOrgSubscriptionCheckout(orgId: orgId)
      openBillingURL(url)
    } catch {
      billingErrorText = "Checkout could not be opened. \(error.localizedDescription)"
    }
  }

  private func openBillingPortal() async {
    guard appState.canAdminActiveOrg,
          let supabase = appState.supabase,
          let orgId = appState.activeOrgId else {
      billingErrorText = "Only organization owners can manage billing for the active organization."
      return
    }
    billingAction = .portal
    defer { billingAction = nil }
    do {
      let url = try await supabase.createOrgBillingPortal(orgId: orgId)
      openBillingURL(url)
    } catch {
      let description = error.localizedDescription
      if description.localizedCaseInsensitiveContains("organization_billing_customer_missing") {
        billingErrorText = "Billing has not been set up for this organization yet. Start a subscription first."
      } else {
        billingErrorText = "Billing Portal could not be opened. \(description)"
      }
    }
  }

  private func openBillingURL(_ url: URL) {
    #if os(iOS)
    UIApplication.shared.open(url)
    #elseif os(macOS)
    NSWorkspace.shared.open(url)
    #endif
  }

  private func applySettingsToFields(_ settings: SDOrgSettings?) {
    isApplyingSettings = true
    defer { isApplyingSettings = false }
    displayName = settings?.display_name ?? ""
    shortName = settings?.short_name ?? ""
    supportEmail = settings?.support_email ?? ""
    websiteHost = settings?.website_host ?? ""
    primaryHex = settings?.primary_color_hex ?? "#0D2445"
    secondaryHex = settings?.secondary_color_hex ?? "#0A3854"
    accentHex = settings?.accent_color_hex ?? "#4D9EF9"
    if let path = settings?.logo_path, let supabase = appState.supabase {
      logoURL = supabase.publicOrganizationLogoURL(path: path)
    } else {
      logoURL = nil
    }

    featureFacilities = settings?.feature("facilities") ?? true
    featureChat = settings?.feature("chat") ?? true
    featurePrograms = settings?.feature("programs") ?? true
    featureTesting = settings?.feature("testing") ?? true
    featureBPAnalysis = settings?.feature("bpAnalysis") ?? true
    featureParentPortal = settings?.feature("parentPortal") ?? true
    featureBilling = settings?.feature("billing") ?? true

    defaultDuration = String(settings?.bookingInt("defaultDurationMinutes", default: 60) ?? 60)
    minDuration = String(settings?.bookingInt("minDurationMinutes", default: 30) ?? 30)
    maxDuration = String(settings?.bookingInt("maxDurationMinutes", default: 120) ?? 120)
    allowPlayerRequests = settings?.booking_policy["allowPlayerRequests"]?.boolValue ?? true
    requireCoachApproval = settings?.booking_policy["requireCoachApproval"]?.boolValue ?? true
    coachesCanViewAllTeams = settings?.teamPolicy("coachesCanViewAllTeams", default: true) ?? true
    restrictCoachActionsToTeam = settings?.teamPolicy("restrictCoachActionsToTeam", default: true) ?? true
    coachesCanManageTeams = settings?.teamPolicy("coachesCanManageTeams", default: false) ?? false
  }

  private func scheduleSettingsAutosave() {
    guard !isApplyingSettings, settings != nil, appState.activeOrgId != nil else { return }
    settingsSaveTask?.cancel()
    settingsSaveTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(650))
      guard !Task.isCancelled else { return }
      await saveSettings(isAutomatic: true)
    }
  }

  private func saveSettings(isAutomatic: Bool = false) async {
    guard let supabase = appState.supabase else { return }
    guard let orgId = appState.activeOrgId else {
      errorText = "No active organization found."
      return
    }
    isSavingSettings = true
    defer { isSavingSettings = false }
    do {
      var logoPath = settings?.logo_path
      if let jpeg = pendingLogoJPEG {
        logoPath = try await supabase.uploadOrganizationLogoJPEG(orgId: orgId, jpegData: jpeg)
      }
      let payload = SupabaseService.SDOrgSettingsUpsert(
        org_id: orgId,
        display_name: clean(displayName),
        short_name: clean(shortName),
        support_email: clean(supportEmail),
        website_host: clean(websiteHost),
        primary_color_hex: normalizeHex(primaryHex, fallback: "#0D2445"),
        secondary_color_hex: normalizeHex(secondaryHex, fallback: "#0A3854"),
        accent_color_hex: normalizeHex(accentHex, fallback: "#4D9EF9"),
        logo_path: logoPath,
        terminology: settings?.terminology ?? [:],
        feature_flags: [
          "facilities": .bool(featureFacilities),
          "chat": .bool(featureChat),
          "programs": .bool(featurePrograms),
          "testing": .bool(featureTesting),
          "bpAnalysis": .bool(featureBPAnalysis),
          "parentPortal": .bool(featureParentPortal),
          "billing": .bool(featureBilling),
        ],
        booking_policy: [
          "defaultDurationMinutes": .int(Int(defaultDuration) ?? 60),
          "minDurationMinutes": .int(Int(minDuration) ?? 30),
          "maxDurationMinutes": .int(Int(maxDuration) ?? 120),
          "allowPlayerRequests": .bool(allowPlayerRequests),
          "requireCoachApproval": .bool(requireCoachApproval),
        ],
        dashboard_layout: settings?.dashboard_layout ?? [
          "showOperations": .bool(true),
          "showRosterBadges": .bool(true),
          "showFacilitySnapshot": .bool(true),
        ],
        team_policy: [
          "coachesCanViewAllTeams": .bool(coachesCanViewAllTeams),
          "restrictCoachActionsToTeam": .bool(restrictCoachActionsToTeam),
          "coachesCanManageTeams": .bool(coachesCanManageTeams),
        ]
      )
      settings = try await supabase.upsertOrgSettings(payload)
      pendingLogoJPEG = nil
      if let logoPath { logoURL = supabase.publicOrganizationLogoURL(path: logoPath) }
      await appState.refreshOrgContext()
      if !isAutomatic { toastText = "Organization settings saved." }
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func saveFacility(_ draft: FacilityDraft) async {
    guard let supabase = appState.supabase else { return }
    guard let orgId = appState.activeOrgId else {
      errorText = "No active organization found."
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      let payload = SupabaseService.SDFacilityUpsert(
        id: draft.id,
        org_id: orgId,
        name: nonEmpty(draft.name, fallback: "Resource"),
        is_active: draft.isActive,
        sort_order: Int(draft.sortOrder) ?? 0,
        resource_type: nonEmpty(draft.resourceType, fallback: "cage").lowercased(),
        color_hex: clean(normalizeHex(draft.colorHex, fallback: "")),
        capacity: max(1, Int(draft.capacity) ?? 1),
        metadata: [
          "fullResourceGroup": .string(draft.fullResourceGroup.trimmingCharacters(in: .whitespacesAndNewlines)),
          "notes": .string(draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]
      )
      if draft.id == nil {
        _ = try await supabase.createFacility(payload)
      } else {
        _ = try await supabase.updateFacility(payload)
      }
      editingFacility = nil
      toastText = "Facility saved."
      await reload()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func createMember(_ draft: CreateMemberDraft) async {
    guard let supabase = appState.supabase else { return }
    guard let orgId = appState.activeOrgId else {
      errorText = "No active organization found."
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      _ = try await supabase.adminCreateOrgUser(
        orgId: orgId,
        email: draft.email.trimmingCharacters(in: .whitespacesAndNewlines),
        username: draft.username.trimmingCharacters(in: .whitespacesAndNewlines),
        password: draft.password,
        fullName: clean(draft.fullName),
        role: draft.role
      )
      isShowingCreateMember = false
      toastText = "Org user created."
      await reload()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func updateMember(_ draft: MemberDraft) async {
    guard let supabase = appState.supabase else { return }
    guard let orgId = appState.activeOrgId else {
      errorText = "No active organization found."
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      try await supabase.adminUpdateOrgMember(
        orgId: orgId,
        userId: draft.userId,
        role: draft.role,
        status: draft.status
      )
      if !draft.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        try await supabase.adminSetOrgUsername(
          orgId: orgId,
          userId: draft.userId,
          username: draft.username.trimmingCharacters(in: .whitespacesAndNewlines)
        )
      }
      editingMember = nil
      toastText = "Member updated."
      await appState.refreshOrgContext()
      await reload()
    } catch {
      let description = error.localizedDescription
      if description.localizedCaseInsensitiveContains("last_active_owner_required") {
        errorText = "Add another active owner before removing, demoting, disabling, or suspending this owner."
      } else {
        errorText = description
      }
    }
  }

  private func clean(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func nonEmpty(_ value: String, fallback: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
  }

  private func normalizeHex(_ value: String, fallback: String) -> String {
    let raw = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    let withHash = raw.hasPrefix("#") ? raw : "#\(raw)"
    guard withHash.count == 7 else { return fallback }
    let allowed = CharacterSet(charactersIn: "#0123456789ABCDEF")
    guard withHash.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return fallback }
    return withHash
  }

  private func colorFromHex(_ value: String?) -> Color? {
    value.map(OrgColorCodec.color(from:))
  }

  private func colorBinding(_ text: Binding<String>) -> Binding<Color> {
    Binding(
      get: { OrgColorCodec.color(from: text.wrappedValue) },
      set: { text.wrappedValue = OrgColorCodec.hex(from: $0) }
    )
  }

  private func deleteFacility(_ facility: SDFacility) async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      try await supabase.deleteFacility(id: facility.id)
      toastText = "\(facility.name) deleted."
      await reload()
    } catch {
      errorText = "Could not delete \(facility.name). \(error.localizedDescription)"
    }
  }

  private func loadLogoPickerItem(_ item: PhotosPickerItem) async {
    do {
      guard let raw = try await item.loadTransferable(type: Data.self),
            let jpeg = AvatarImageProcessor.squareJPEG(from: raw, side: 512) else {
        errorText = "That image could not be prepared as an organization logo."
        return
      }
      pendingLogoJPEG = jpeg
      logoURL = AvatarImageProcessor.localPreviewURL(for: jpeg)
      scheduleSettingsAutosave()
    } catch {
      errorText = error.localizedDescription
    }
  }
}

private struct PaymentRequestCreateSheet: View {
  @Environment(\.dismiss) private var dismiss
  let organizationId: UUID?
  let supabase: SupabaseService?
  @Binding var draft: SDPaymentRequestCreateDraft
  @Binding var playerSearchText: String
  let isSubmitting: Bool
  let errorText: String?
  let onCreate: ([SDPaymentRequestEligiblePlayer]) -> Void

  @State private var eligiblePlayers: [SDPaymentRequestEligiblePlayer] = []
  @State private var rosterLoadState = SDPaymentRequestEligibleRosterState.idle
  @State private var rosterRequestID = UUID()
  @State private var decodedPlayerCount = 0
  @State private var isSheetPresented = false

  /// Search is presentation-only. The backend-authorized response array remains
  /// the authoritative roster and is never filtered by role, status, or membership here.
  private var displayedPlayers: [SDPaymentRequestEligiblePlayer] {
    SDPaymentRequestPlayerRoster.search(eligiblePlayers, text: playerSearchText)
  }

  private var eligibleSelectedPlayerIds: Set<UUID> {
    SDPaymentRequestPlayerRoster.reconcile(
      selectedPlayerUserIds: draft.selectedPlayerUserIds,
      eligiblePlayers: eligiblePlayers
    )
  }

  private var shortOrganizationID: String {
    organizationId.map { String($0.uuidString.prefix(8)) } ?? "none"
  }

  var body: some View {
    NavigationStack {
      HPFormScreenLayout { _ in
        HPWorkspaceHeader(
          "New Payment Request",
          context: "Internal request · Stripe Checkout is not enabled"
        )
      } sections: { context in
        VStack(alignment: .leading, spacing: HP.Space.md) {
          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.md) {
              HPSectionHeader("Players (\(eligibleSelectedPlayerIds.count) selected)")
              HPFormField(
                label: "Search players",
                text: $playerSearchText,
                placeholder: "Player name",
                isEnabled: !rosterLoadState.isLoading
              )

              let selectionLayout = context.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.xs))
                : AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.xs))
              selectionLayout {
                HPButton(
                  title: "Select All",
                  variant: .secondary,
                  fullWidth: context.isAccessibilitySize
                ) {
                  draft.selectedPlayerUserIds = SDPaymentRequestPlayerRoster.selectAll(eligiblePlayers)
                }
                .disabled(
                  eligiblePlayers.isEmpty
                    || eligibleSelectedPlayerIds.count == eligiblePlayers.count
                )
                HPButton(
                  title: "Clear",
                  variant: .tertiary,
                  fullWidth: context.isAccessibilitySize
                ) {
                  draft.selectedPlayerUserIds.removeAll()
                }
                .disabled(draft.selectedPlayerUserIds.isEmpty)
              }

              if rosterLoadState.isLoading {
                HPLoadingState(text: "Loading eligible players…")
              } else if let rosterErrorText = rosterLoadState.errorMessage {
                Text(rosterErrorText)
                  .font(HP.Font.caption)
                  .foregroundStyle(HP.Color.danger)
                  .fixedSize(horizontal: false, vertical: true)
              } else if case .empty = rosterLoadState {
                HPEmptyState(
                  title: "No active players",
                  message: "No active players were returned for this organization.",
                  systemImage: "person.slash"
                )
              }
              if rosterLoadState.shouldShowRetry {
                HPButton(title: "Retry", systemImage: "arrow.clockwise", variant: .secondary) {
                  Task { await loadEligiblePlayers() }
                }
              }

              ForEach(displayedPlayers) { player in
                Button {
                  if draft.selectedPlayerUserIds.contains(player.userId) {
                    draft.selectedPlayerUserIds.remove(player.userId)
                  } else {
                    draft.selectedPlayerUserIds.insert(player.userId)
                  }
                } label: {
                  HStack(spacing: HP.Space.sm) {
                    Text(player.displayName)
                      .font(HP.Font.callout)
                      .foregroundStyle(HP.Color.text)
                      .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: HP.Space.sm)
                    Image(systemName: draft.selectedPlayerUserIds.contains(player.userId)
                          ? "checkmark.circle.fill"
                          : "circle")
                      .foregroundStyle(draft.selectedPlayerUserIds.contains(player.userId)
                                        ? HP.Color.accent
                                        : HP.Color.textMuted)
                  }
                  .padding(.horizontal, HP.Space.sm)
                  .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                  .background(
                    RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
                      .fill(draft.selectedPlayerUserIds.contains(player.userId)
                            ? HP.Color.accent.opacity(0.12)
                            : HP.Color.surface)
                  )
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.displayName)
                .accessibilityValue(draft.selectedPlayerUserIds.contains(player.userId) ? "Selected" : "Not selected")
                .accessibilityAddTraits(draft.selectedPlayerUserIds.contains(player.userId) ? .isSelected : [])
              }
              #if DEBUG
              Text(
                "Debug: server=\(decodedPlayerCount), "
                  + "displayed=\(displayedPlayers.count), org=\(shortOrganizationID)"
              )
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.textMuted)
              #endif
            }
          }

          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.md) {
              HPSectionHeader("Request")
              HPFormField(label: "Title", text: $draft.title, placeholder: "Request title")
              HPFormField(
                label: "Description (optional)",
                text: $draft.description,
                kind: .multiline,
                placeholder: "What this request covers"
              )
              paymentAmountField
              Toggle("Set a due date", isOn: $draft.includesDueDate)
                .font(HP.Font.callout)
                .foregroundStyle(HP.Color.text)
                .tint(HP.Color.accent)
                .frame(minHeight: 44)
              if draft.includesDueDate {
                DatePicker("Due date", selection: $draft.dueDate, displayedComponents: .date)
                  .font(HP.Font.callout)
                  .foregroundStyle(HP.Color.text)
                  .tint(HP.Color.accent)
                  .frame(minHeight: 44)
              }
            }
          }

          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              Label(
                "This creates an internal request only. Stripe Checkout and payment processing are not enabled yet.",
                systemImage: "info.circle"
              )
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.textMuted)
              .fixedSize(horizontal: false, vertical: true)
              if let validationError = draft.validationError {
                Text(validationError)
                  .font(HP.Font.caption)
                  .foregroundStyle(HP.Color.warning)
                  .fixedSize(horizontal: false, vertical: true)
              }
              if let errorText {
                Text(errorText)
                  .font(HP.Font.caption)
                  .foregroundStyle(HP.Color.danger)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
          }
        }
      } primaryAction: { context in
        HPButton(
          title: isSubmitting
            ? "Creating…"
            : errorText != nil && draft.pendingIdempotencyKey != nil ? "Retry" : "Create",
          variant: .primary,
          size: .lg,
          isLoading: isSubmitting,
          fullWidth: context.isAccessibilitySize
        ) {
          onCreate(eligiblePlayers)
        }
        .disabled(!SDPaymentRequestAuthorization.canSubmitCreateRequest(
          draftIsValid: draft.isValid,
          eligibleSelectedPlayerCount: eligibleSelectedPlayerIds.count,
          isSubmitting: isSubmitting
        ))
      } secondaryAction: { _ in
        EmptyView()
      }
      .navigationTitle("New Payment Request")
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
    .onAppear { isSheetPresented = true }
    .onDisappear {
      isSheetPresented = false
      rosterRequestID = UUID()
    }
    .task(id: organizationId) {
      isSheetPresented = true
      await loadEligiblePlayers()
    }
    .onChange(of: eligiblePlayers.map(\.userId)) { _, _ in
      draft.selectedPlayerUserIds = SDPaymentRequestPlayerRoster.reconcile(
        selectedPlayerUserIds: draft.selectedPlayerUserIds,
        eligiblePlayers: eligiblePlayers
      )
    }
  }

  private var paymentAmountField: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Amount (USD)".uppercased())
        .font(HP.Font.eyebrow)
        .tracking(HP.Font.eyebrowTracking)
        .foregroundStyle(HP.Color.textMuted)
      TextField("0.00", text: $draft.amountDollars)
        .textFieldStyle(.plain)
        .font(HP.Font.number(.body))
        .foregroundStyle(HP.Color.text)
        #if os(iOS)
        .keyboardType(.decimalPad)
        #endif
        .padding(.horizontal, HP.Space.sm)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .background(
          RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
            .fill(HP.Color.input)
        )
        .overlay(
          RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
            .strokeBorder(HP.Color.border, lineWidth: 1)
            .allowsHitTesting(false)
        )
      Text("Entered as dollars and converted to authoritative integer cents when the request is prepared.")
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  @MainActor
  private func loadEligiblePlayers() async {
    guard let requestedOrganizationID = organizationId else {
      eligiblePlayers = []
      decodedPlayerCount = 0
      rosterLoadState = .failed(
        organizationId: UUID(),
        message: "No active organization is selected."
      )
      return
    }

    let requestID = UUID()
    rosterRequestID = requestID
    rosterLoadState.beginLoading(
      organizationId: requestedOrganizationID,
      requestId: requestID
    )
    eligiblePlayers = []
    decodedPlayerCount = 0
    draft.selectedPlayerUserIds.removeAll()

    #if DEBUG
    print(
      "payment_request_sheet_roster_started "
        + "org_id=\(requestedOrganizationID.uuidString)"
    )
    #endif

    defer {
      rosterLoadState.finishLoadingIfNeeded(
        organizationId: requestedOrganizationID,
        requestId: requestID
      )
    }

    guard let supabase else {
      _ = rosterLoadState.fail(
        message: "Eligible players could not be loaded because the signed-in service is unavailable.",
        organizationId: requestedOrganizationID,
        requestId: requestID
      )
      #if DEBUG
      print(
        "payment_request_sheet_roster_http=failure "
          + "org_id=\(requestedOrganizationID.uuidString) reason=service_unavailable"
      )
      #endif
      return
    }

    do {
      guard let response = try await SDPaymentRequestSheetRosterLoadCoordinator.loadResponse(
        organizationId: requestedOrganizationID,
        listEligiblePlayers: { organizationID in
          try await supabase.listEligiblePaymentRequestPlayersResponse(orgId: organizationID)
        }
      ) else { return }

      #if DEBUG
      print(
        "payment_request_sheet_roster_http=success "
          + "org_id=\(requestedOrganizationID.uuidString)"
      )
      #endif

      if let discardReason = SDPaymentRequestSheetRosterResponseContext.discardReason(
        sheetIsPresented: isSheetPresented,
        requestedOrganizationId: requestedOrganizationID,
        selectedOrganizationId: organizationId,
        responseRequestId: requestID,
        currentRequestId: rosterRequestID
      ) {
        #if DEBUG
        print(
          "payment_request_sheet_roster_response_discarded=true "
            + "org_id=\(requestedOrganizationID.uuidString) "
            + "reason=\(discardReason.rawValue)"
        )
        #endif
        return
      }

      guard rosterLoadState.apply(
        response.players,
        organizationId: requestedOrganizationID,
        requestId: requestID
      ) else {
        #if DEBUG
        print(
          "payment_request_sheet_roster_response_discarded=true "
            + "org_id=\(requestedOrganizationID.uuidString) reason=request_superseded"
        )
        #endif
        return
      }

      decodedPlayerCount = response.players.count
      eligiblePlayers = response.players
      draft.selectedPlayerUserIds = SDPaymentRequestPlayerRoster.reconcile(
        selectedPlayerUserIds: draft.selectedPlayerUserIds,
        eligiblePlayers: eligiblePlayers
      )

      #if DEBUG
      print(
        "payment_request_sheet_roster_decoded_count=\(response.players.count) "
          + "local_eligible_count=\(eligiblePlayers.count) "
          + "displayed_picker_count=\(displayedPlayers.count) "
          + "org_id=\(requestedOrganizationID.uuidString) "
          + "response_discarded=false"
      )
      #endif
    } catch {
      #if DEBUG
      print(
        "payment_request_sheet_roster_http=failure "
          + "org_id=\(requestedOrganizationID.uuidString)"
      )
      #endif

      if let discardReason = SDPaymentRequestSheetRosterResponseContext.discardReason(
        sheetIsPresented: isSheetPresented,
        requestedOrganizationId: requestedOrganizationID,
        selectedOrganizationId: organizationId,
        responseRequestId: requestID,
        currentRequestId: rosterRequestID
      ) {
        #if DEBUG
        print(
          "payment_request_sheet_roster_response_discarded=true "
            + "org_id=\(requestedOrganizationID.uuidString) "
            + "reason=\(discardReason.rawValue)"
        )
        #endif
        return
      }

      eligiblePlayers = []
      decodedPlayerCount = 0
      draft.selectedPlayerUserIds.removeAll()
      _ = rosterLoadState.fail(
        message: "Eligible players could not be loaded. \(error.localizedDescription)",
        organizationId: requestedOrganizationID,
        requestId: requestID
      )
    }
  }
}

private enum OrgColorCodec {
  static func color(from rawValue: String) -> Color {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
    guard hex.count == 6, let rgb = UInt64(hex, radix: 16) else { return HP.Color.accent }
    return Color(
      red: Double((rgb & 0xFF0000) >> 16) / 255,
      green: Double((rgb & 0x00FF00) >> 8) / 255,
      blue: Double(rgb & 0x0000FF) / 255
    )
  }

  static func hex(from color: Color) -> String {
#if canImport(UIKit)
    let native = UIColor(color)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    native.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
#elseif canImport(AppKit)
    let native = NSColor(color).usingColorSpace(.deviceRGB) ?? .black
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    native.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
#else
    let red: CGFloat = 0.30
    let green: CGFloat = 0.62
    let blue: CGFloat = 0.98
#endif
    return String(
      format: "#%02X%02X%02X",
      Int((red * 255).rounded()),
      Int((green * 255).rounded()),
      Int((blue * 255).rounded())
    )
  }
}

struct FacilityDraft: Identifiable, Equatable {
  var id: UUID?
  var orgId: UUID?
  var name: String
  var isActive: Bool
  var sortOrder: String
  var resourceType: String
  var colorHex: String
  var capacity: String
  var fullResourceGroup: String
  var notes: String

  static func new(orgId: UUID?) -> FacilityDraft {
    FacilityDraft(
      id: nil,
      orgId: orgId,
      name: "",
      isActive: true,
      sortOrder: "0",
      resourceType: "cage",
      colorHex: "#4D9EF9",
      capacity: "1",
      fullResourceGroup: "",
      notes: ""
    )
  }

  init(facility: SDFacility, orgId: UUID?) {
    self.id = facility.id
    self.orgId = facility.org_id ?? orgId
    self.name = facility.name
    self.isActive = facility.is_active
    self.sortOrder = String(facility.sort_order)
    self.resourceType = facility.resource_type ?? "cage"
    self.colorHex = facility.color_hex ?? "#4D9EF9"
    self.capacity = String(facility.capacity ?? 1)
    self.fullResourceGroup = ""
    self.notes = ""
  }

  private init(id: UUID?, orgId: UUID?, name: String, isActive: Bool, sortOrder: String, resourceType: String, colorHex: String, capacity: String, fullResourceGroup: String, notes: String) {
    self.id = id
    self.orgId = orgId
    self.name = name
    self.isActive = isActive
    self.sortOrder = sortOrder
    self.resourceType = resourceType
    self.colorHex = colorHex
    self.capacity = capacity
    self.fullResourceGroup = fullResourceGroup
    self.notes = notes
  }
}

private struct FacilityAdminEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State var draft: FacilityDraft
  let onSave: (FacilityDraft) -> Void

  var body: some View {
    NavigationStack {
      HPFormScreenLayout { _ in
        HPWorkspaceHeader(draft.id == nil ? "New Facility" : "Edit Facility")
      } sections: { _ in
        VStack(alignment: .leading, spacing: HP.Space.md) {
          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.md) {
              HPSectionHeader("Resource")
              HPFormField(label: "Name", text: $draft.name, placeholder: "Facility name")
              HPFormField(label: "Type", text: $draft.resourceType, placeholder: "cage")
              Toggle("Active / visible", isOn: $draft.isActive)
                .font(HP.Font.callout)
                .foregroundStyle(HP.Color.text)
                .tint(HP.Color.accent)
                .frame(minHeight: 44)
            }
          }

          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.md) {
              HPSectionHeader("Display")
              HPFormField(label: "Sort order", text: $draft.sortOrder, placeholder: "0")
              HPFormField(label: "Color hex", text: $draft.colorHex, placeholder: "#4D9EF9")
              ColorPicker(
                "Color wheel",
                selection: Binding(
                  get: { OrgColorCodec.color(from: draft.colorHex) },
                  set: { draft.colorHex = OrgColorCodec.hex(from: $0) }
                )
              )
              .font(HP.Font.callout)
              .foregroundStyle(HP.Color.text)
              .frame(minHeight: 44)
              HPFormField(label: "Capacity", text: $draft.capacity, placeholder: "1")
            }
          }

          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.md) {
              HPSectionHeader("Advanced")
              HPFormField(
                label: "Full-resource group (optional)",
                text: $draft.fullResourceGroup,
                placeholder: "Group name"
              )
              HPFormField(label: "Notes", text: $draft.notes, kind: .multiline, placeholder: "Resource notes")
            }
          }
        }
      } primaryAction: { context in
        HPButton(
          title: "Save",
          variant: .primary,
          size: .lg,
          fullWidth: context.isAccessibilitySize
        ) {
          onSave(draft)
        }
        .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      } secondaryAction: { _ in
        EmptyView()
      }
      .navigationTitle(draft.id == nil ? "New Facility" : "Edit Facility")
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

private let orgRoleOptions = ["owner", "admin", "coach", "player", "parent"]
private let orgStatusOptions = ["active", "invited", "disabled", "suspended"]

struct CreateMemberDraft: Equatable {
  var fullName = ""
  var email = ""
  var username = ""
  var password = ""
  var role = "player"

  var isValid: Bool {
    email.contains("@")
    && username.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    && password.count >= 8
  }
}

struct MemberDraft: Identifiable, Equatable {
  var id: UUID { userId }
  let userId: UUID
  var displayName: String
  var email: String
  var username: String
  var role: String
  var status: String

  init(member: SDOrgAdminMember) {
    self.userId = member.user_id
    self.displayName = member.displayName
    self.email = member.email ?? ""
    self.username = member.username ?? ""
    self.role = member.role
    self.status = member.status
  }
}

private struct CreateOrgMemberSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var draft = CreateMemberDraft()
  let onCreate: (CreateMemberDraft) -> Void

  var body: some View {
    NavigationStack {
      HPFormScreenLayout { _ in
        HPWorkspaceHeader("Create Org User", context: "Organization-specific access")
      } sections: { _ in
        VStack(alignment: .leading, spacing: HP.Space.md) {
          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.md) {
              HPSectionHeader("Identity")
              HPFormField(label: "Full name", text: $draft.fullName, placeholder: "Full name")
              emailField
              usernameField
              HPFormField(
                label: "Temporary password",
                text: $draft.password,
                kind: .secure,
                placeholder: "At least 8 characters"
              )
            }
          }

          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              HPSectionHeader("Access")
              Picker("Role", selection: $draft.role) {
                ForEach(orgRoleOptions, id: \.self) { role in
                  Text(role.capitalized).tag(role)
                }
              }
              .pickerStyle(.menu)
              .font(HP.Font.callout)
              .foregroundStyle(HP.Color.text)
              .tint(HP.Color.accent)
              .frame(minHeight: 44)
              Text("Active owners and administrators can administer this organization. Coaches, players, and parents do not receive organization-admin authority.")
                .font(HP.Font.caption)
                .foregroundStyle(HP.Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      } primaryAction: { context in
        HPButton(
          title: "Create",
          variant: .primary,
          size: .lg,
          fullWidth: context.isAccessibilitySize
        ) {
          onCreate(draft)
        }
        .disabled(!draft.isValid)
      } secondaryAction: { _ in
        EmptyView()
      }
      .navigationTitle("Create Org User")
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

  private var emailField: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Email".uppercased())
        .font(HP.Font.eyebrow)
        .tracking(HP.Font.eyebrowTracking)
        .foregroundStyle(HP.Color.textMuted)
      TextField("name@example.com", text: $draft.email)
        #if os(iOS)
        .textInputAutocapitalization(.never)
        .keyboardType(.emailAddress)
        #endif
        .modifier(AdminInputChrome())
    }
  }

  private var usernameField: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Org username".uppercased())
        .font(HP.Font.eyebrow)
        .tracking(HP.Font.eyebrowTracking)
        .foregroundStyle(HP.Color.textMuted)
      TextField("username", text: $draft.username)
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .modifier(AdminInputChrome())
    }
  }
}

private struct EditOrgMemberSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State var draft: MemberDraft
  let onSave: (MemberDraft) -> Void

  var body: some View {
    NavigationStack {
      HPFormScreenLayout { _ in
        HPWorkspaceHeader("Edit Member", context: draft.displayName)
      } sections: { _ in
        VStack(alignment: .leading, spacing: HP.Space.md) {
          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.xs) {
              HPSectionHeader("Member")
              Text(draft.displayName)
                .font(HP.Font.headline)
                .foregroundStyle(HP.Color.text)
              if !draft.email.isEmpty {
                Text(draft.email)
                  .font(HP.Font.callout)
                  .foregroundStyle(HP.Color.textMuted)
              }
              Text(draft.userId.uuidString)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(HP.Color.textMuted)
                .textSelection(.enabled)
            }
          }

          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              HPSectionHeader("Org Login")
              usernameField
              Text("Usernames are unique inside this organization only.")
                .font(HP.Font.caption)
                .foregroundStyle(HP.Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            }
          }

          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              HPSectionHeader("Access")
              Picker("Role", selection: $draft.role) {
                ForEach(orgRoleOptions, id: \.self) { role in
                  Text(role.capitalized).tag(role)
                }
              }
              .pickerStyle(.menu)
              .frame(minHeight: 44)
              Picker("Status", selection: $draft.status) {
                ForEach(orgStatusOptions, id: \.self) { status in
                  Text(status.capitalized).tag(status)
                }
              }
              .pickerStyle(.menu)
              .frame(minHeight: 44)
            }
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.text)
            .tint(HP.Color.accent)
          }
        }
      } primaryAction: { context in
        HPButton(
          title: "Save",
          variant: .primary,
          size: .lg,
          fullWidth: context.isAccessibilitySize
        ) {
          onSave(draft)
        }
        .disabled(draft.username.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
      } secondaryAction: { _ in
        EmptyView()
      }
      .navigationTitle("Edit Member")
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

  private var usernameField: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Username".uppercased())
        .font(HP.Font.eyebrow)
        .tracking(HP.Font.eyebrowTracking)
        .foregroundStyle(HP.Color.textMuted)
      TextField("Username", text: $draft.username)
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .modifier(AdminInputChrome())
    }
  }
}

private struct AdminInputChrome: ViewModifier {
  func body(content: Content) -> some View {
    content
      .textFieldStyle(.plain)
      .font(HP.Font.body)
      .foregroundStyle(HP.Color.text)
      .padding(.horizontal, HP.Space.sm)
      .padding(.vertical, 10)
      .frame(minHeight: 44)
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
}

private struct OrganizationOperationsAdminView: View {
  enum Section { case communication, registration, analytics }

  let section: Section
  let organizationId: UUID
  @EnvironmentObject private var appState: AppState
  @State private var announcements: [SDCommunicationAnnouncementRecipient] = []
  @State private var deliveries: [SDNotificationDeliveryStatus] = []
  @State private var offerings: [SDRegistrationOffering] = []
  @State private var applications: [SDRegistrationApplication] = []
  @State private var analytics: SDOrganizationAnalytics?
  @State private var definitions: [SDMetricDefinition] = []
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var statusText: String?

  var body: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: HP.Space.xs) {
          Text(title).font(HP.Font.title)
          Text(subtitle).font(HP.Font.callout).foregroundStyle(HP.Color.textMuted)
        }
        Spacer()
        Button {
          Task { await load() }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .disabled(isLoading)
      }

      if let errorText {
        HPCard {
          Label(errorText, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(HP.Color.danger)
            .accessibilityLabel("Error: \(errorText)")
        }
      }
      if let statusText {
        HPCard { Label(statusText, systemImage: "checkmark.circle") }
      }
      if isLoading && isEmpty {
        ProgressView("Loading \(title.lowercased())")
          .frame(maxWidth: .infinity, minHeight: 160)
      } else {
        switch section {
        case .communication: communicationContent
        case .registration: registrationContent
        case .analytics: analyticsContent
        }
      }
    }
    .task(id: "\(organizationId)-\(title)") { await load() }
  }

  private var title: String {
    switch section {
    case .communication: "Communication Operations"
    case .registration: "Registration & Seasons"
    case .analytics: "Organization Analytics"
    }
  }

  private var subtitle: String {
    switch section {
    case .communication: "Announcements, acknowledgments, and delivery attention"
    case .registration: "Offerings, capacity, requirements, and applicant review"
    case .analytics: "Explainable business, registration, operations, and communication metrics"
    }
  }

  private var isEmpty: Bool {
    announcements.isEmpty && deliveries.isEmpty && offerings.isEmpty && applications.isEmpty && analytics == nil
  }

  @ViewBuilder private var communicationContent: some View {
    let failed = deliveries.filter { $0.delivery_state == "failed" }
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: HP.Space.sm)], spacing: HP.Space.sm) {
      metricCard("Published", value: "\(announcements.count)", systemImage: "megaphone")
      metricCard("Failed delivery", value: "\(failed.count)", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
      metricCard("Unacknowledged", value: "\(announcements.filter { $0.announcement.acknowledgment_required && $0.acknowledged_at == nil }.count)", systemImage: "checkmark.message")
    }
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HStack {
          Text("Delivery review").font(HP.Font.headline)
          Spacer()
          Button("Dry-run pending intents") {
            Task { await dryRunIntents() }
          }
          .disabled(isLoading)
        }
        if deliveries.isEmpty {
          HPEmptyState(title: "No delivery attention", message: "Delivery receipts will appear after operational intents are consumed.", systemImage: "bell.badge")
        } else {
          ForEach(deliveries.prefix(20)) { delivery in
            HStack {
              Image(systemName: delivery.delivery_state == "failed" ? "exclamationmark.triangle.fill" : "checkmark.circle")
              VStack(alignment: .leading) {
                Text(delivery.category.replacingOccurrences(of: "_", with: " ").capitalized)
                Text(delivery.preference_decision).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
              }
              Spacer()
              Text(delivery.delivery_state.capitalized).font(HP.Font.caption.weight(.semibold))
            }
            .accessibilityElement(children: .combine)
          }
        }
      }
    }
  }

  @ViewBuilder private var registrationContent: some View {
    let waitlisted = applications.filter { $0.state == "waitlisted" }.count
    let reviewCount = applications.filter { ["submitted", "under_review", "action_required"].contains($0.state) }.count
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: HP.Space.sm)], spacing: HP.Space.sm) {
      metricCard("Offerings", value: "\(offerings.count)", systemImage: "list.bullet.clipboard")
      metricCard("Needs review", value: "\(reviewCount)", systemImage: "person.crop.circle.badge.questionmark")
      metricCard("Waitlisted", value: "\(waitlisted)", systemImage: "clock.badge")
    }
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        Text("Registration attention").font(HP.Font.headline)
        if offerings.isEmpty && applications.isEmpty {
          HPEmptyState(title: "No registration activity", message: "Create and activate an offering to begin accepting registrations.", systemImage: "person.crop.circle.badge.plus")
        } else {
          ForEach(applications.prefix(30)) { application in
            HStack {
              VStack(alignment: .leading) {
                Text(application.state.replacingOccurrences(of: "_", with: " ").capitalized)
                  .font(HP.Font.body.weight(.semibold))
                Text("Application \(application.id.uuidString.prefix(8))")
                  .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
              }
              Spacer()
              if let balance = application.balance_cents, balance > 0 {
                Text(SDMoney(minorUnits: balance, currency: "usd").formatted())
                  .font(HP.Font.callout.monospacedDigit())
                  .accessibilityLabel("Balance \(SDMoney(minorUnits: balance, currency: "usd").formatted())")
              }
              if ["submitted", "under_review", "action_required", "waitlisted"].contains(application.state) {
                Menu {
                  Button("Approve") { Task { await review(application, action: "approve") } }
                  Button("Waitlist") { Task { await review(application, action: "waitlist") } }
                  Button("Request action") { Task { await review(application, action: "request_action") } }
                  Button("Decline", role: .destructive) { Task { await review(application, action: "decline") } }
                } label: {
                  Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Review application")
                .disabled(isLoading)
              }
            }
          }
        }
      }
    }
  }

  @ViewBuilder private var analyticsContent: some View {
    if let analytics {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: HP.Space.sm)], spacing: HP.Space.sm) {
        metricCard("Collected", value: SDMoney(minorUnits: analytics.financial.collected_cents, currency: "usd").formatted(), systemImage: "dollarsign.circle")
        metricCard("Receivables", value: SDMoney(minorUnits: analytics.financial.outstanding_cents, currency: "usd").formatted(), systemImage: "clock.badge.exclamationmark")
        metricCard("Net result", value: SDMoney(minorUnits: analytics.financial.net_operating_result_cents, currency: "usd").formatted(), systemImage: "chart.line.uptrend.xyaxis")
      }
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          Text("Operational summary").font(HP.Font.headline)
          analyticsRow("Registrations", "\(analytics.registration.total)")
          analyticsRow("Outstanding registration balance", SDMoney(minorUnits: analytics.registration.balance, currency: "usd").formatted())
          analyticsRow("Events completed", "\(analytics.operations.completed) of \(analytics.operations.events)")
          analyticsRow("Attendance completion", percent(analytics.operations.attendance_rate))
          analyticsRow("Availability response", percent(analytics.operations.availability_response_rate))
          analyticsRow("Announcement read rate", percent(analytics.communication.read_rate))
          Text("As of \(analytics.as_of)").font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        }
      }
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          Text("Metric definitions").font(HP.Font.headline)
          ForEach(definitions) { definition in
            DisclosureGroup(definition.name) {
              Text(definition.definition).font(HP.Font.callout)
              Text("Includes: \(definition.inclusion_rules)").font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
              Text("Excludes: \(definition.exclusion_rules)").font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            }
          }
        }
      }
    } else {
      HPCard { HPEmptyState(title: "No analytics yet", message: "Metrics appear once authoritative organization activity exists.", systemImage: "chart.bar") }
    }
  }

  private func metricCard(_ label: String, value: String, systemImage: String) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.xs) {
        Label(label, systemImage: systemImage).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        Text(value).font(HP.Font.number(.title3)).minimumScaleFactor(0.75)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
    }
  }

  private func analyticsRow(_ label: String, _ value: String) -> some View {
    HStack { Text(label); Spacer(); Text(value).fontWeight(.semibold) }
      .accessibilityElement(children: .combine)
  }

  private func percent(_ value: Decimal?) -> String {
    guard let value else { return "No data" }
    return Double(truncating: NSDecimalNumber(decimal: value))
      .formatted(.percent.precision(.fractionLength(0)))
  }

  @MainActor private func load() async {
    guard let service = appState.supabase else {
      errorText = "Connect to Home Plate to load organization operations."
      return
    }
    isLoading = true; errorText = nil; statusText = nil
    do {
      switch section {
      case .communication:
        async let announcementResponse = service.communicationAnnouncements(organizationId: organizationId)
        async let deliveryResponse = service.communicationDeliveryStatus(organizationId: organizationId)
        let loaded = try await (announcementResponse, deliveryResponse)
        announcements = loaded.0.announcements; deliveries = loaded.1.deliveries
      case .registration:
        async let offeringResponse = service.registrationOfferings(organizationId: organizationId)
        async let applicationResponse = service.registrationApplications(organizationId: organizationId)
        let loaded = try await (offeringResponse, applicationResponse)
        offerings = loaded.0.offerings; applications = loaded.1.applications
      case .analytics:
        let response = try await service.organizationAnalytics(organizationId: organizationId)
        analytics = response.analytics; definitions = response.definitions
      }
    } catch { errorText = error.localizedDescription }
    isLoading = false
  }

  @MainActor private func dryRunIntents() async {
    guard let service = appState.supabase else { return }
    isLoading = true; errorText = nil
    do {
      try await service.dryRunOperationalNotificationIntents(organizationId: organizationId)
      statusText = "Dry run completed. No notifications were sent or queued."
    } catch { errorText = error.localizedDescription }
    isLoading = false
  }

  @MainActor private func review(
    _ application: SDRegistrationApplication,
    action: String
  ) async {
    guard let service = appState.supabase else { return }
    isLoading = true; errorText = nil
    do {
      let updated = try await service.reviewRegistration(
        organizationId: organizationId,
        application: application,
        action: action,
        notes: "Updated from Registration Operations"
      )
      if let index = applications.firstIndex(where: { $0.id == updated.id }) {
        applications[index] = updated
      }
      statusText = "Application updated to \(updated.state.replacingOccurrences(of: "_", with: " "))."
    } catch { errorText = error.localizedDescription }
    isLoading = false
  }
}
