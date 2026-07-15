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
    case facilities = "Facilities"
    case members = "Members"
    var id: String { rawValue }
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
        ProgressView("Checking organization access…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(DHDTheme.pageBackground)
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
    ContentUnavailableView(
      isPlatformSupportMode ? "Platform Support Access Required" : "Organization Admin Access Required",
      systemImage: "lock.shield",
      description: Text(isPlatformSupportMode
        ? "Only a verified platform administrator can manage payment requests in support mode."
        : "Only an active owner or administrator for the selected organization can open these controls.")
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DHDTheme.pageBackground)
    .navigationTitle("Org Admin")
  }

  private var platformSupportPresentation: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        DHDCard {
          Label(
            "Platform Support — acting on behalf of \(platformSupportOrganization?.name ?? "Organization")",
            systemImage: "person.badge.shield.checkmark"
          )
          .font(.headline)
          Text("This does not make you an organization owner or member.")
            .font(.footnote)
            .foregroundStyle(DHDTheme.textSecondary)
        }
        DHDCard {
          VStack(alignment: .leading, spacing: 14) {
            paymentRequestsSection
          }
        }
      }
      .padding(DHDTheme.pagePadding)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(DHDTheme.pageBackground)
    .navigationTitle("Payment Support")
    .dhdToast($toastText)
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
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        header

        Picker("Admin section", selection: $selectedTab) {
          ForEach(visibleTabs) { tab in
            Text(tab.rawValue).tag(tab)
          }
        }
        #if os(macOS)
        .pickerStyle(.segmented)
        #else
        .pickerStyle(.menu)
        #endif

        Group {
          switch selectedTab {
          case .dashboard:
            dashboardCard
          case .branding:
            brandingCard
            bookingPolicyCard
          case .features:
            featureFlagsCard
          case .billing:
            if appState.canAdminActiveOrg {
              billingSection
            } else {
              DHDCard {
                Text("Billing controls are available to active organization owners and administrators only.")
                  .foregroundStyle(DHDTheme.textSecondary)
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
              DHDCard {
                Text("Finance data is available to active organization owners and administrators only.")
                  .foregroundStyle(DHDTheme.textSecondary)
              }
            }
          case .facilities:
            facilitiesCard
          case .members:
            membersCard
          }
        }
      }
      .padding(DHDTheme.pagePadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(maxHeight: .infinity, alignment: .topLeading)
    }
    .background(DHDTheme.pageBackground)
    .navigationTitle("Org Admin")
  }

  private var visibleTabs: [Tab] {
    Tab.allCases.filter {
      ($0 != .billing && $0 != .finance) || appState.canAdminActiveOrg
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
      .dhdToast($toastText)
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
          Task { await deleteFacility(facility) }
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This permanently removes \(facilityPendingDeletion?.name ?? "this facility") and cannot be undone.")
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
    DHDHeaderCard {
      HStack(alignment: .center, spacing: 12) {
        if let logoURL {
          AsyncImage(url: logoURL) { image in
            image.resizable().scaledToFill()
          } placeholder: {
            ProgressView().tint(.white)
          }
          .frame(width: 40, height: 40)
          .background(Color.white.opacity(0.12))
          .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        VStack(alignment: .leading, spacing: 4) {
          Text("Organization Admin Console")
            .font(.title3.weight(.semibold))
          Text(activeOrgSubtitle)
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.84))
        }
        Spacer()
        if isLoading {
          ProgressView().tint(.white)
        }
        if isSavingSettings {
          ProgressView().tint(.white)
        }
        Label("Changes save automatically", systemImage: "checkmark.circle")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white.opacity(0.86))
      }
      .foregroundStyle(.white)
    }
  }

  private var dashboardCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      DHDCard {
        VStack(alignment: .leading, spacing: 14) {
          HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              Text(settings?.display_name ?? settings?.short_name ?? "Organization")
                .font(.title2.weight(.bold))
              Text("Admin dashboard")
                .font(.subheadline)
                .foregroundStyle(DHDTheme.textSecondary)
            }
            Spacer()
            DHDStatusBadge(text: "Live", color: .green)
          }

          LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 10)], spacing: 10) {
            adminMetric("Members", value: adminMembers.count, symbol: "person.3.fill", color: DHDTheme.accent)
            adminMetric("Players", value: playerCount, symbol: "figure.baseball", color: .blue)
            adminMetric("Coaches", value: coachCount, symbol: "person.2.fill", color: .green)
            adminMetric("Pending bookings", value: pendingBookingCount, symbol: "clock.badge.exclamationmark", color: .orange)
            adminMetric("Next 7 days", value: upcomingBookings.count, symbol: "calendar", color: .purple)
            adminMetric("Program plans", value: templateCount, symbol: "square.stack.3d.up.fill", color: .teal)
            adminMetric("Chat channels", value: channelCount, symbol: "bubble.left.and.bubble.right.fill", color: .indigo)
            adminMetric("Active facilities", value: facilities.filter(\.is_active).count, symbol: "building.2.fill", color: .mint)
          }
        }
      }

      DHDCard {
        VStack(alignment: .leading, spacing: 12) {
          DHDSectionHeader("Operations") {
            Button {
              Task { await reload() }
            } label: {
              Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)
          }

          if upcomingBookings.isEmpty {
            Text("No facility bookings are scheduled in the next seven days.")
              .foregroundStyle(DHDTheme.textSecondary)
          } else {
            let preview = Array(upcomingBookings.prefix(5))
            ForEach(Array(preview.enumerated()), id: \.element.id) { index, booking in
              HStack(spacing: 10) {
                Image(systemName: booking.is_block ? "nosign" : "calendar.badge.clock")
                  .foregroundStyle(booking.is_block ? .orange : DHDTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                  Text(booking.title?.isEmpty == false ? booking.title! : booking.activity_type.capitalized)
                    .font(.subheadline.weight(.semibold))
                  Text(booking.start_at.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(DHDTheme.textSecondary)
                }
                Spacer()
                DHDStatusBadge(text: booking.status.capitalized, color: bookingStatusColor(booking.status))
              }
              if index < preview.count - 1 {
                Divider().overlay(DHDTheme.separator.opacity(0.3))
              }
            }
          }
        }
      }

      DHDCard {
        VStack(alignment: .leading, spacing: 10) {
          DHDSectionHeader("Quick management") { EmptyView() }
          Text("Manage the people, tools, and facility access for this organization.")
            .font(.footnote)
            .foregroundStyle(DHDTheme.textSecondary)
          HStack(spacing: 10) {
            Button { selectedTab = .members } label: {
              Label("Members", systemImage: "person.2.badge.gearshape")
            }
            Button { selectedTab = .features } label: {
              Label("Features", systemImage: "switch.2")
            }
            Button { selectedTab = .facilities } label: {
              Label("Facilities", systemImage: "building.2")
            }
          }
          .buttonStyle(.bordered)
        }
      }
    }
  }

  private func adminMetric(_ title: String, value: Int, symbol: String, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Image(systemName: symbol)
        .foregroundStyle(color)
        .font(.headline)
      Text("\(value)")
        .font(.title2.weight(.bold))
      Text(title)
        .font(.caption)
        .foregroundStyle(DHDTheme.textSecondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(DHDTheme.surfaceElevated.opacity(0.7))
    .clipShape(RoundedRectangle(cornerRadius: 8))
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

  private func bookingStatusColor(_ status: String) -> Color {
    switch status.lowercased() {
    case "approved": return .green
    case "pending": return .orange
    case "denied", "cancelled": return .red
    default: return DHDTheme.accent
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
    DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        DHDSectionHeader("Branding & Contact") { EmptyView() }

        HStack(spacing: 12) {
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
                .foregroundStyle(DHDTheme.accent)
            }
          }
          .frame(width: 58, height: 58)
          .background(DHDTheme.surfaceElevated)
          .clipShape(RoundedRectangle(cornerRadius: 8))

          VStack(alignment: .leading, spacing: 5) {
            PhotosPicker(selection: $logoPickerItem, matching: .images) {
              Label("Upload organization logo", systemImage: "photo.badge.plus")
            }
            .onChange(of: logoPickerItem) { _, item in
              guard let item else { return }
              Task { await loadLogoPickerItem(item) }
            }
            Text(pendingLogoJPEG == nil ? "Displays in branded organization surfaces." : "Logo selected and will save automatically.")
              .font(.footnote)
              .foregroundStyle(DHDTheme.textSecondary)
          }
          Spacer()
        }

        TextField("Display name", text: $displayName)
          .textFieldStyle(.roundedBorder)
        TextField("Short name", text: $shortName)
          .textFieldStyle(.roundedBorder)

        HStack(spacing: 10) {
          TextField("Support email", text: $supportEmail)
            .textFieldStyle(.roundedBorder)
          TextField("Website host", text: $websiteHost)
            .textFieldStyle(.roundedBorder)
        }

        Text("Brand colors")
          .font(.headline)
          .padding(.top, 4)
        HStack(spacing: 10) {
          hexField("Primary", text: $primaryHex)
          hexField("Secondary", text: $secondaryHex)
          hexField("Accent", text: $accentHex)
        }
      }
    }
  }

  private var featureFlagsCard: some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        DHDSectionHeader("Feature Flags") { EmptyView() }

        Toggle("Facilities / booking", isOn: $featureFacilities)
        Toggle("Chat", isOn: $featureChat)
        Toggle("Programs", isOn: $featurePrograms)
        Toggle("Testing", isOn: $featureTesting)
        Toggle("BP analysis", isOn: $featureBPAnalysis)
        Toggle("Parent portal", isOn: $featureParentPortal)
        Toggle("Billing/payment requests", isOn: $featureBilling)
        Divider()
        Text("Team permissions")
          .font(.headline)
        Toggle("Coaches can view all teams", isOn: $coachesCanViewAllTeams)
        Toggle("Limit coach assignments and evaluations to their own team", isOn: $restrictCoachActionsToTeam)
        Toggle("Allow coaches to manage team assignments", isOn: $coachesCanManageTeams)
        Text("Organization admins always manage all teams. Coaches can be granted team management separately.")
          .font(.footnote)
          .foregroundStyle(DHDTheme.textSecondary)
      }
    }
  }

  private var billingCard: some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 14) {
        DHDSectionHeader("Home Plate Subscription") {
          Button {
            Task { await refreshBilling() }
          } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
          }
          .disabled(isBillingLoading || billingAction != nil)
        }

        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Home Plate Organization")
              .font(.headline)
            Text("$200/month")
              .font(.subheadline)
              .foregroundStyle(DHDTheme.textSecondary)
          }
          Spacer()
          if let subscription = organizationSubscription {
            DHDStatusBadge(
              text: subscription.status.replacingOccurrences(of: "_", with: " ").capitalized,
              color: billingStatusColor(subscription.status)
            )
          } else {
            DHDStatusBadge(text: "No subscription", color: .orange)
          }
        }

        if isBillingLoading {
          HStack(spacing: 8) {
            ProgressView()
            Text("Loading subscription status…")
              .foregroundStyle(DHDTheme.textSecondary)
          }
        } else if let billingErrorText {
          VStack(alignment: .leading, spacing: 8) {
            Text(billingErrorText)
              .font(.footnote)
              .foregroundStyle(.red)
            Button("Try Again") {
              Task { await refreshBilling() }
            }
            .buttonStyle(.bordered)
          }
        } else if let subscription = organizationSubscription {
          VStack(alignment: .leading, spacing: 6) {
            if let periodEnd = subscription.current_period_end {
              Text(subscription.cancel_at_period_end ? "Access ends" : "Next billing date")
                .font(.caption)
                .foregroundStyle(DHDTheme.textSecondary)
              Text(displayBillingDate(periodEnd))
                .font(.subheadline.weight(.semibold))
            } else {
              Text("Stripe has not reported a billing period end yet.")
                .font(.footnote)
                .foregroundStyle(DHDTheme.textSecondary)
            }
            if subscription.cancel_at_period_end {
              Label("Cancellation is scheduled at the end of the current period.", systemImage: "calendar.badge.exclamationmark")
                .font(.footnote)
                .foregroundStyle(.orange)
            }
          }
        } else {
          Text("No Stripe subscription has been synchronized for this organization yet.")
            .font(.footnote)
            .foregroundStyle(DHDTheme.textSecondary)
        }

        HStack(spacing: 10) {
          Button {
            Task { await beginCheckout() }
          } label: {
            Label(
              billingAction == .checkout ? "Opening Checkout…" : "Subscribe — $200/month",
              systemImage: "creditcard"
            )
          }
          .buttonStyle(.borderedProminent)
          .disabled(isCurrentSubscription || billingAction != nil || isBillingLoading)

          Button {
            Task { await openBillingPortal() }
          } label: {
            Label(
              billingAction == .portal ? "Opening Portal…" : "Manage Billing",
              systemImage: "arrow.up.right.square"
            )
          }
          .buttonStyle(.bordered)
          .disabled(billingAction != nil || isBillingLoading)
        }

        Text("Payment status is updated only after Stripe sends its webhook. Returning from the browser refreshes this screen but does not confirm payment by itself.")
          .font(.footnote)
          .foregroundStyle(DHDTheme.textSecondary)
      }
    }
  }

  private var billingSection: some View {
    Group {
      if appState.canAdminActiveOrg {
        VStack(alignment: .leading, spacing: 14) {
          customerPaymentsCard
          billingCard
        }
      } else {
        accessDeniedSurface
      }
    }
  }

  private var customerPaymentsCard: some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 14) {
        DHDSectionHeader("Customer Payments") {
          Button {
            Task { await refreshConnectStatus() }
          } label: {
            Label("Refresh Status", systemImage: "arrow.clockwise")
          }
          .disabled(isConnectLoading || connectAction != nil)
        }

        HStack(alignment: .top, spacing: 12) {
          Image(systemName: connectStatusSymbol)
            .font(.title2)
            .foregroundStyle(connectStatusColor)
            .frame(width: 34)
          VStack(alignment: .leading, spacing: 4) {
            Text(connectStatusTitle)
              .font(.headline)
            Text(connectStatusDetail)
              .font(.footnote)
              .foregroundStyle(DHDTheme.textSecondary)
          }
          Spacer()
          if let connectStatus {
            DHDStatusBadge(
              text: connectStatus.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized,
              color: connectStatusColor
            )
          }
        }

        if isConnectLoading {
          HStack(spacing: 8) {
            ProgressView()
            Text("Checking Stripe account status…")
              .foregroundStyle(DHDTheme.textSecondary)
          }
        } else if let connectErrorText {
          Text(connectErrorText)
            .font(.footnote)
            .foregroundStyle(.red)
        }

        if connectStatus?.status != .ready {
          Button {
            Task { await beginConnectOnboarding() }
          } label: {
            Label(
              connectAction == .onboarding ? "Opening Stripe…" : connectOnboardingButtonTitle,
              systemImage: "link"
            )
          }
          .buttonStyle(.borderedProminent)
          .disabled(isConnectLoading || connectAction != nil)
        }

        Text("Stripe onboarding opens in your system browser. Home Plate confirms readiness only after refreshing Stripe's server status.")
          .font(.footnote)
          .foregroundStyle(DHDTheme.textSecondary)

        Divider().overlay(DHDTheme.separator.opacity(0.35))
        paymentRequestsSection
      }
    }
  }

  @ViewBuilder
  private var paymentRequestsSection: some View {
    DHDSectionHeader("Payment Requests") {
      Button {
        guard canManagePaymentRequests, paymentRequestMutationId == nil else {
          return
        }
        paymentRequestDraft = SDPaymentRequestCreateDraft()
        paymentRequestPlayerSearchText = ""
        paymentRequestErrorText = nil
        paymentRequestCreatePresentation.present()
      } label: {
        Label("Create Payment Request", systemImage: "plus")
      }
      .buttonStyle(.borderedProminent)
      .disabled(!canManagePaymentRequests || paymentRequestMutationId != nil)
    }

    #if DEBUG
    if let paymentRequestCreateDisabledReason {
      Text(paymentRequestCreateDisabledReason)
        .font(.caption2)
        .foregroundStyle(DHDTheme.textSecondary)
        .accessibilityIdentifier("payment-request-create-disabled-reason")
    }
    #endif

    Text("Create one-time internal requests now. Stripe Checkout is not enabled until the next phase.")
      .font(.footnote)
      .foregroundStyle(DHDTheme.textSecondary)

    if let paymentRequestRosterErrorText = paymentRequestRosterState.errorMessage {
      VStack(alignment: .leading, spacing: 8) {
        Text(paymentRequestRosterErrorText).font(.footnote).foregroundStyle(.red)
        Button("Refresh Eligible Players") {
          Task { await refreshEligiblePaymentRequestPlayers() }
        }
        .buttonStyle(.bordered)
      }
    }

    if isPaymentRequestLoading {
      HStack(spacing: 8) {
        ProgressView()
        Text("Loading payment requests…")
          .foregroundStyle(DHDTheme.textSecondary)
      }
    } else if let paymentRequestErrorText, !paymentRequestCreatePresentation.isPresented {
      VStack(alignment: .leading, spacing: 8) {
        Text(paymentRequestErrorText).font(.footnote).foregroundStyle(.red)
        Button("Try Again") { Task { await refreshPaymentRequests() } }
          .buttonStyle(.bordered)
      }
    } else if paymentRequestState.requests.isEmpty {
      Text(activePlayerMembers.isEmpty
        ? (isPlatformSupportMode
          ? "No eligible active players are available in this organization."
          : "Add an active player before creating a payment request.")
        : "No payment requests yet.")
        .foregroundStyle(DHDTheme.textSecondary)
    } else {
      ForEach(paymentRequestState.requests) { request in
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Text(request.title).font(.headline)
            Text(request.player_name ?? playerName(request.player_id))
              .font(.caption)
              .foregroundStyle(DHDTheme.textSecondary)
            HStack(spacing: 8) {
              Text(request.money?.formatted() ?? "Amount unavailable")
              if let dueDate = request.due_date {
                Text("Due \(displayPaymentRequestDate(dueDate))")
              }
            }
            .font(.caption)
            .foregroundStyle(DHDTheme.textSecondary)
          }
          Spacer()
          VStack(alignment: .trailing, spacing: 7) {
            DHDStatusBadge(
              text: request.status.rawValue.capitalized,
              color: paymentRequestStatusColor(request.status)
            )
            if request.status == .open {
              Button("Cancel", role: .destructive) {
                Task { await cancelPaymentRequest(request) }
              }
              .buttonStyle(.bordered)
              .disabled(paymentRequestMutationId != nil || !canManagePaymentRequests)
            }
          }
        }
        .padding(.vertical, 4)
        Divider().overlay(DHDTheme.separator.opacity(0.25))
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
    case .ready: return .green
    case .restricted: return .red
    case .requirementsDue, .onboardingIncomplete: return .orange
    case .none, .notConnected: return DHDTheme.accent
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

  private func billingStatusColor(_ status: String) -> Color {
    switch status.lowercased() {
    case "active": return .green
    case "trialing", "incomplete": return .orange
    case "past_due", "unpaid", "incomplete_expired", "canceled": return .red
    default: return DHDTheme.accent
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
    DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        DHDSectionHeader("Booking Policy") { EmptyView() }

        HStack(spacing: 10) {
          TextField("Default duration", text: $defaultDuration)
            .textFieldStyle(.roundedBorder)
          TextField("Minimum duration", text: $minDuration)
            .textFieldStyle(.roundedBorder)
          TextField("Maximum duration", text: $maxDuration)
            .textFieldStyle(.roundedBorder)
        }
        Toggle("Players can request bookings", isOn: $allowPlayerRequests)
        Toggle("Bookings require coach approval", isOn: $requireCoachApproval)
      }
    }
  }

  private var facilitiesCard: some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        DHDSectionHeader("Facility Resources") {
          Button {
            editingFacility = FacilityDraft.new(orgId: appState.activeOrgId)
          } label: {
            Label("Add", systemImage: "plus")
          }
        }

        if facilities.isEmpty {
          Text("No facilities configured yet.")
            .foregroundStyle(DHDTheme.textSecondary)
        } else {
          ForEach(facilities) { facility in
            HStack(spacing: 12) {
              Circle()
                .fill(colorFromHex(facility.color_hex) ?? DHDTheme.accent)
                .frame(width: 12, height: 12)
              VStack(alignment: .leading, spacing: 2) {
                Text(facility.name)
                  .font(.headline)
                Text("\(facility.resource_type ?? "resource") • capacity \(facility.capacity ?? 1) • sort \(facility.sort_order)")
                  .font(.caption)
                  .foregroundStyle(DHDTheme.textSecondary)
              }
              Spacer()
              DHDStatusBadge(text: facility.is_active ? "Active" : "Hidden", color: facility.is_active ? .green : .orange)
              Button("Edit") {
                editingFacility = FacilityDraft(facility: facility, orgId: appState.activeOrgId)
              }
              Button(role: .destructive) {
                facilityPendingDeletion = facility
              } label: {
                Image(systemName: "trash")
              }
              .help("Delete \(facility.name)")
            }
            Divider().overlay(DHDTheme.separator.opacity(0.25))
          }
        }
      }
    }
  }

  private var membersCard: some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        DHDSectionHeader("Users & Org Access") {
          HStack {
            Button("Refresh") { Task { await reload() } }
            Button {
              isShowingCreateMember = true
            } label: {
              Label("Create User", systemImage: "person.badge.plus")
            }
          }
        }

        Text("Create organization-specific accounts, assign roles, disable access, and update the username used by the org login screen.")
          .font(.footnote)
          .foregroundStyle(DHDTheme.textSecondary)

        if adminMembers.isEmpty {
          Text("No memberships visible.")
            .foregroundStyle(DHDTheme.textSecondary)
        } else {
          ForEach(adminMembers) { member in
            HStack(spacing: 12) {
              VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName)
                  .font(.headline)
                Text(member.email ?? member.user_id.uuidString)
                  .font(.caption)
                  .foregroundStyle(DHDTheme.textSecondary)
                if let username = member.username {
                  Text("@\(username)")
                    .font(.caption)
                    .foregroundStyle(DHDTheme.textSecondary)
                }
              }
              Spacer()
              DHDStatusBadge(text: member.status.capitalized, color: member.status == "active" ? .green : .orange)
              DHDStatusBadge(text: member.role.capitalized, color: member.isAdmin ? .green : DHDTheme.accent)
              Button("Edit") {
                editingMember = MemberDraft(member: member)
              }
            }
            Divider().overlay(DHDTheme.separator.opacity(0.25))
          }
        }
      }
    }
  }

  private func hexField(_ label: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(label)
        .font(.caption)
        .foregroundStyle(DHDTheme.textSecondary)
      HStack {
        ColorPicker("\(label) color", selection: colorBinding(text))
          .labelsHidden()
          .frame(width: 28)
        RoundedRectangle(cornerRadius: 6)
          .fill(OrgColorCodec.color(from: text.wrappedValue))
          .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DHDTheme.separator, lineWidth: 1))
          .frame(width: 26, height: 26)
        TextField("#RRGGBB", text: text)
          .textFieldStyle(.roundedBorder)
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
      channelCount = (try? await supabase.listChatChannels().count) ?? 0

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

  private func paymentRequestStatusColor(_ status: SDPaymentRequestStatus) -> Color {
    switch status {
    case .open: return .orange
    case .canceled: return .secondary
    case .paid: return .green
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
      Form {
        Section {
          TextField("Search players", text: $playerSearchText)
            .disabled(rosterLoadState.isLoading)
          HStack {
            Button("Select All") {
              draft.selectedPlayerUserIds = SDPaymentRequestPlayerRoster.selectAll(eligiblePlayers)
            }
            .disabled(
              eligiblePlayers.isEmpty
                || eligibleSelectedPlayerIds.count == eligiblePlayers.count
            )
            Spacer()
            Button("Clear") {
              draft.selectedPlayerUserIds.removeAll()
            }
            .disabled(draft.selectedPlayerUserIds.isEmpty)
          }
          if rosterLoadState.isLoading {
            HStack(spacing: 8) {
              ProgressView()
              Text("Loading eligible players…")
            }
            .foregroundStyle(DHDTheme.textSecondary)
          } else if let rosterErrorText = rosterLoadState.errorMessage {
            Text(rosterErrorText).font(.footnote).foregroundStyle(.red)
          } else if case .empty = rosterLoadState {
            Text("No active players were returned for this organization.")
              .foregroundStyle(DHDTheme.textSecondary)
          }
          if rosterLoadState.shouldShowRetry {
            Button("Retry") {
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
              HStack {
                Text(player.displayName)
                  .foregroundStyle(DHDTheme.textPrimary)
                Spacer()
                Image(systemName: draft.selectedPlayerUserIds.contains(player.userId)
                      ? "checkmark.circle.fill"
                      : "circle")
                  .foregroundStyle(draft.selectedPlayerUserIds.contains(player.userId)
                                    ? DHDTheme.accent
                                    : DHDTheme.textSecondary)
              }
            }
            .buttonStyle(.plain)
          }
          #if DEBUG
          Text(
            "Debug: server=\(decodedPlayerCount), "
              + "displayed=\(displayedPlayers.count), org=\(shortOrganizationID)"
          )
          .font(.caption2)
          .foregroundStyle(DHDTheme.textSecondary)
          #endif
        } header: {
          Text("Players (\(eligibleSelectedPlayerIds.count) selected)")
        }

        Section("Request") {
          TextField("Title", text: $draft.title)
          TextField("Description (optional)", text: $draft.description, axis: .vertical)
            .lineLimit(3...6)
          TextField("Amount (USD)", text: $draft.amountDollars)
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
          Toggle("Set a due date", isOn: $draft.includesDueDate)
          if draft.includesDueDate {
            DatePicker("Due date", selection: $draft.dueDate, displayedComponents: .date)
          }
        }

        Section {
          Text("This creates an internal request only. Stripe Checkout and payment processing are not enabled yet.")
            .font(.footnote)
            .foregroundStyle(DHDTheme.textSecondary)
          if let validationError = draft.validationError {
            Text(validationError).font(.footnote).foregroundStyle(.orange)
          }
          if let errorText {
            Text(errorText).font(.footnote).foregroundStyle(.red)
          }
        }
      }
      .navigationTitle("New Payment Request")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .disabled(isSubmitting)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(
            isSubmitting
              ? "Creating…"
              : errorText != nil && draft.pendingIdempotencyKey != nil ? "Retry" : "Create"
          ) { onCreate(eligiblePlayers) }
            .disabled(!SDPaymentRequestAuthorization.canSubmitCreateRequest(
              draftIsValid: draft.isValid,
              eligibleSelectedPlayerCount: eligibleSelectedPlayerIds.count,
              isSubmitting: isSubmitting
            ))
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
    guard hex.count == 6, let rgb = UInt64(hex, radix: 16) else { return DHDTheme.accent }
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
      Form {
        Section("Resource") {
          TextField("Name", text: $draft.name)
          TextField("Type", text: $draft.resourceType)
          Toggle("Active / visible", isOn: $draft.isActive)
        }

        Section("Display") {
          TextField("Sort order", text: $draft.sortOrder)
          TextField("Color hex", text: $draft.colorHex)
          ColorPicker(
            "Color wheel",
            selection: Binding(
              get: { OrgColorCodec.color(from: draft.colorHex) },
              set: { draft.colorHex = OrgColorCodec.hex(from: $0) }
            )
          )
          TextField("Capacity", text: $draft.capacity)
        }

        Section("Advanced") {
          TextField("Full-resource group (optional)", text: $draft.fullResourceGroup)
          TextField("Notes", text: $draft.notes, axis: .vertical)
        }
      }
      .navigationTitle(draft.id == nil ? "New Facility" : "Edit Facility")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            onSave(draft)
          }
          .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
      Form {
        Section("Identity") {
          TextField("Full name", text: $draft.fullName)
          TextField("Email", text: $draft.email)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)
            #endif
          TextField("Org username", text: $draft.username)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
          SecureField("Temporary password", text: $draft.password)
        }

        Section("Access") {
          Picker("Role", selection: $draft.role) {
            ForEach(orgRoleOptions, id: \.self) { role in
              Text(role.capitalized).tag(role)
            }
          }
          Text("Active owners and administrators can administer this organization. Coaches, players, and parents do not receive organization-admin authority.")
            .font(.footnote)
            .foregroundStyle(DHDTheme.textSecondary)
        }
      }
      .navigationTitle("Create Org User")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create") {
            onCreate(draft)
          }
          .disabled(!draft.isValid)
        }
      }
    }
  }
}

private struct EditOrgMemberSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State var draft: MemberDraft
  let onSave: (MemberDraft) -> Void

  var body: some View {
    NavigationStack {
      Form {
        Section("Member") {
          Text(draft.displayName)
          if !draft.email.isEmpty {
            Text(draft.email)
              .foregroundStyle(DHDTheme.textSecondary)
          }
          Text(draft.userId.uuidString)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(DHDTheme.textSecondary)
        }

        Section("Org Login") {
          TextField("Username", text: $draft.username)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
          Text("Usernames are unique inside this organization only.")
            .font(.footnote)
            .foregroundStyle(DHDTheme.textSecondary)
        }

        Section("Access") {
          Picker("Role", selection: $draft.role) {
            ForEach(orgRoleOptions, id: \.self) { role in
              Text(role.capitalized).tag(role)
            }
          }
          Picker("Status", selection: $draft.status) {
            ForEach(orgStatusOptions, id: \.self) { status in
              Text(status.capitalized).tag(status)
            }
          }
        }
      }
      .navigationTitle("Edit Member")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            onSave(draft)
          }
          .disabled(draft.username.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
        }
      }
    }
  }
}
