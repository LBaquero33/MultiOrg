import SwiftUI

/// Role- and capability-aware staff shell. The destination views, feature
/// gates, deep-link handlers, and authorization checks are the same routes that
/// predate the Home Plate navigation presentation.
struct CoachRootView: View {
  @EnvironmentObject private var appState: AppState

#if os(macOS)
  @State private var selection: HPAppNavigationDestination = .coachToday
#else
  @State private var mobileSelection: HPAppNavigationDestination = .coachToday
#endif

  var body: some View {
#if os(macOS)
    HPRegularApplicationShell(
      role: sidebarRole,
      inventory: navigationInventory,
      selection: $selection
    ) { destination in
      destinationView(destination)
    }
    .onChange(of: appState.activeOrgAuthorizationKey) { _, _ in
      let normalized = navigationInventory.normalizedRegularSelection(selection)
      if normalized != selection {
        selection = normalized
      }
    }
    .onChange(of: appState.requestedChatChannelId) { _, channelId in
      guard channelId != nil, feature("chat") else { return }
      selection = .chat
    }
    .task(id: appState.requestedChatChannelId) {
      guard appState.requestedChatChannelId != nil, feature("chat") else { return }
      selection = .chat
    }
    .task(id: appState.activeOrgAuthorizationKey) {
      await appState.refreshTeamOperationsContext()
    }
#else
    HPAdaptiveApplicationShell(
      role: sidebarRole,
      roleSubtitle: roleSubtitle,
      inventory: navigationInventory,
      selection: $mobileSelection
    ) { destination in
      destinationView(destination)
    }
    .onChange(of: appState.requestedChatChannelId) { _, channelId in
      guard channelId != nil, feature("chat") else { return }
      mobileSelection = .chat
    }
    .task(id: appState.requestedChatChannelId) {
      guard appState.requestedChatChannelId != nil, feature("chat") else { return }
      mobileSelection = .chat
    }
    .task(id: appState.activeOrgAuthorizationKey) {
      await appState.refreshTeamOperationsContext()
    }
#endif
  }

  private var navigationInventory: HPAppNavigationInventory {
    if appState.canAdminActiveOrg {
      return HPAppNavigationInventory.owner(
        facilitiesTitle: term("facilities", fallback: "Facilities"),
        programsTitle: "\(term("program", fallback: "Program")) Templates",
        facilitiesEnabled: feature("facilities"),
        chatEnabled: feature("chat"),
        programsEnabled: feature("programs"),
        isPlatformAdmin: appState.isPlatformAdmin
      )
    }
    return HPAppNavigationInventory.staff(
      playersTitle: term("players", fallback: "Players"),
      facilitiesTitle: term("facilities", fallback: "Facilities"),
      programsTitle: "\(term("program", fallback: "Program")) Templates",
      facilitiesEnabled: feature("facilities"),
      chatEnabled: feature("chat"),
      programsEnabled: feature("programs"),
      canAdministerOrganization: false,
      isPlatformAdmin: appState.isPlatformAdmin
    )
  }

  private var sidebarRole: HPRole {
    switch appState.activeOrgMembership?.normalizedRole {
    case "owner", "admin": .owner
    default: .coach
    }
  }

  private var roleSubtitle: String {
    switch appState.activeOrgMembership?.normalizedRole {
    case "owner": "Owner workspace"
    case "admin": "Organization admin workspace"
    default: "Coach workspace"
    }
  }

  @ViewBuilder
  private func destinationView(_ destination: HPAppNavigationDestination) -> some View {
    switch destination {
    case .coachToday:
      CoachTodayFoundationView()
    case .coachTeam:
      CoachTeamCommandCenterView()
    case .coachSchedule:
      CoachScheduleFoundationView()
    case .coachPlayers:
      CoachHomeView()
    case .coachFacilities:
      if feature("facilities") {
        CoachFacilitiesView()
      } else {
        disabledFeatureView("Facilities")
      }
    case .coachTeams:
      if appState.canAdminActiveOrg {
#if os(macOS)
        OrgTeamOperationsAdminView()
#else
        NavigationStack { OrgTeamOperationsAdminView() }
#endif
      } else {
        disabledFeatureView("Team Administration")
      }
    case .coachPrograms:
      if feature("programs") {
        CoachProgramsView()
      } else {
        disabledFeatureView("Programs")
      }
    case .chat:
      if feature("chat") {
        ChatChannelListView()
      } else {
        disabledFeatureView("Chat")
      }
    case .finance:
      if appState.canAdminActiveOrg, let organizationId = appState.activeOrgId {
#if os(macOS)
        financeView(organizationId: organizationId)
#else
        NavigationStack { financeView(organizationId: organizationId) }
#endif
      } else {
        disabledFeatureView("Finance")
      }
    case .organizationAdmin:
#if os(macOS)
      OrgAdminConsoleView()
#else
      NavigationStack { OrgAdminConsoleView() }
#endif
    case .platformAdmin:
#if os(macOS)
      PlatformAdminDashboardView()
#else
      NavigationStack { PlatformAdminDashboardView() }
#endif
    case .account:
#if os(macOS)
      AccountView()
#else
      NavigationStack { AccountView() }
#endif
    default:
      disabledFeatureView("Workspace")
    }
  }

  private func financeView(organizationId: UUID) -> some View {
    FinanceDashboardView(
      organizationId: organizationId,
      organizationName: financeOrganizationName,
      platformSupportMode: false
    )
  }

  private var financeOrganizationName: String {
    appState.availableOrganizations.first(where: { $0.id == appState.activeOrgId })?.name
      ?? appState.activeOrgSettings?.display_name
      ?? appState.activeOrgSettings?.short_name
      ?? "Home Plate"
  }

  private func term(_ key: String, fallback: String) -> String {
    appState.activeOrgSettings?.term(key, fallback: fallback) ?? fallback
  }

  private func feature(_ key: String) -> Bool {
    appState.activeOrgSettings?.feature(key) ?? true
  }

  private func disabledFeatureView(_ name: String) -> some View {
    HPStateScreenLayout { _ in
      HPCard {
        HPEmptyState(
          title: "\(name) is disabled",
          message: "Turn it back on in Org Admin → Features.",
          systemImage: "switch.2"
        )
      }
    }
  }
}
