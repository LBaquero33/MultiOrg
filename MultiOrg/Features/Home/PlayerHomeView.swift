import SwiftUI

struct PlayerHomeView: View {
  @EnvironmentObject private var appState: AppState
  @State private var showAccount = false
  @State private var showDevelopment = false
#if os(iOS)
  @State private var selection = HPAppNavigationDestination.playerToday
#elseif os(macOS)
  @State private var macSelection = HPAppNavigationDestination.playerToday
#endif

  var body: some View {
#if os(macOS)
    HPRegularApplicationShell(
      role: .player,
      inventory: .playerMacPlaceholder(),
      selection: $macSelection
    ) { _ in
      playerMacPlaceholder
    }
    .sheet(isPresented: $showAccount) {
      NavigationStack {
        AccountView()
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Close") { showAccount = false }
                .keyboardShortcut(.cancelAction)
            }
          }
      }
      .environmentObject(appState)
        .frame(minWidth: 640, minHeight: 640)
    }
    .sheet(isPresented: $showDevelopment) {
      NavigationStack {
        playerDevelopmentDestination
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Close") { showDevelopment = false }
                .keyboardShortcut(.cancelAction)
            }
          }
      }
        .environmentObject(appState)
        .frame(minWidth: 720, minHeight: 680)
    }
#else
    playerApplicationShell
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onChange(of: appState.requestedChatChannelId) { _, channelId in
      guard channelId != nil, feature("chat") else { return }
      selection = .chat
    }
    .task(id: appState.requestedChatChannelId) {
      guard appState.requestedChatChannelId != nil, feature("chat") else { return }
      selection = .chat
    }
#endif
  }

#if os(macOS)
  private var playerMacPlaceholder: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPWorkspaceHeader(
          "Player",
          context: "Player features coming soon on macOS"
        )

        DHDCard {
          VStack(spacing: HP.Space.sm) {
            Image(systemName: "desktopcomputer")
              .font(.system(size: 38, weight: .semibold))
              .foregroundStyle(DHDTheme.accent)
              .accessibilityHidden(true)
            Text("Player features coming soon on macOS")
              .font(HP.Font.headline)
              .foregroundStyle(DHDTheme.textPrimary)
              .multilineTextAlignment(.center)
            Text("This macOS app is focused on coach workflows. Please use the iOS app for player logging for now.")
              .font(HP.Font.body)
              .foregroundStyle(DHDTheme.textSecondary)
              .multilineTextAlignment(.center)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: 420)
          }
          .padding(.vertical, HP.Space.md)
          .frame(maxWidth: .infinity)
        }

        DHDCard {
          VStack(spacing: HP.Space.sm) {
            DHDButton(
              "Open Development AI",
              systemImage: "sparkles.rectangle.stack",
              expands: true
            ) {
              showDevelopment = true
            }
            DHDButton(
              "Open Account",
              systemImage: "gearshape",
              variant: .secondary,
              expands: true
            ) {
              showAccount = true
            }
          }
        }

        DHDCard {
          DHDButton(
            "Sign Out",
            systemImage: "rectangle.portrait.and.arrow.right",
            variant: .destructive,
            expands: true
          ) {
            Task { await appState.signOut() }
          }
        }
      }
      .padding(DHDTheme.pagePadding)
      .frame(maxWidth: 720)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .dhdPageBackground()
  }
#endif

#if os(iOS)
  private var navigationInventory: HPAppNavigationInventory {
    .player(
      chatEnabled: feature("chat"),
      facilitiesEnabled: feature("facilities"),
      testingEnabled: feature("testing"),
      analysisEnabled: feature("bpAnalysis"),
      facilitiesTitle: term("facilities", fallback: "Facilities"),
      testingTitle: term("testing", fallback: "Testing")
    )
  }

  @ViewBuilder
  private var playerApplicationShell: some View {
    let inventory = navigationInventory

    HPAdaptiveApplicationShell(
      role: .player,
      roleSubtitle: "Player workspace",
      inventory: inventory,
      selection: $selection
    ) { destination in
      playerDestination(destination)
    }
  }

  @ViewBuilder
  private func playerDestination(_ destination: HPAppNavigationDestination) -> some View {
    switch destination {
    case .playerToday:
      SDPlayerTodayView()
    case .playerCalendar:
      SDPlayerCalendarView()
    case .chat:
      ChatChannelListView()
    case .playerFacilities:
      SDPlayerFacilitiesView()
    case .playerTrends:
      SDPlayerTrendsView()
    case .playerTesting:
      SDPlayerTestingView()
    case .playerAnalysis:
      SDPlayerAnalysisView()
    case .playerDevelopment:
      NavigationStack { playerDevelopmentDestination }
    case .account:
      NavigationStack { AccountView() }
    default:
      SDPlayerTodayView()
    }
  }
#endif

  private func term(_ key: String, fallback: String) -> String {
    appState.activeOrgSettings?.term(key, fallback: fallback) ?? fallback
  }

  private func feature(_ key: String) -> Bool {
    appState.activeOrgSettings?.feature(key) ?? true
  }

  @ViewBuilder
  private var playerDevelopmentDestination: some View {
    if let player = appState.myProfile {
      PlayerDevelopmentPlayerWorkspaceView(player: player)
    } else {
      ProgressView("Loading player profile…")
    }
  }
}
