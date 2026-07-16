import SwiftUI

struct PlayerHomeView: View {
  @EnvironmentObject private var appState: AppState
  @State private var showAccount = false
  @State private var showDevelopment = false
#if os(iOS)
  @State private var selection = Destination.today

  private enum Destination: Hashable {
    case today, calendar, chat, facilities, trends, testing, analysis, development, account
  }
#endif

  var body: some View {
#if os(macOS)
    VStack(spacing: 14) {
      Image(systemName: "desktopcomputer")
        .font(.system(size: 38, weight: .semibold))
        .foregroundStyle(.secondary)
      Text("Player features coming soon on macOS")
        .font(.title3.weight(.semibold))
      Text("This macOS app is focused on coach workflows. Please use the iOS app for player logging for now.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)

      Button {
        showDevelopment = true
      } label: {
        Text("Open Development AI")
          .frame(maxWidth: 240)
      }
      .buttonStyle(.borderedProminent)

      Button {
        showAccount = true
      } label: {
        Text("Open Account")
          .frame(maxWidth: 240)
      }
      .buttonStyle(.borderedProminent)

      Button(role: .destructive) {
        Task { await appState.signOut() }
      } label: {
        Text("Sign Out")
          .frame(maxWidth: 240)
      }
      .buttonStyle(.borderedProminent)
      .tint(.red)
      .padding(.top, 6)
    }
    .padding()
    .sheet(isPresented: $showAccount) {
      AccountView()
        .environmentObject(appState)
        .frame(minWidth: 640, minHeight: 640)
    }
    .sheet(isPresented: $showDevelopment) {
      NavigationStack { playerDevelopmentDestination }
        .environmentObject(appState)
        .frame(minWidth: 720, minHeight: 680)
    }
#else
    TabView(selection: $selection) {
      SDPlayerTodayView()
        .tabItem { Label("Today", systemImage: "sun.max") }
        .tag(Destination.today)
      SDPlayerCalendarView()
        .tabItem { Label("Calendar", systemImage: "calendar") }
        .tag(Destination.calendar)
      if feature("chat") {
        ChatChannelListView()
          .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
          .tag(Destination.chat)
      }
      if feature("facilities") {
        SDPlayerFacilitiesView()
          .tabItem { Label(term("facilities", fallback: "Facilities"), systemImage: "building.2") }
          .tag(Destination.facilities)
      }
      SDPlayerTrendsView()
        .tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }
        .tag(Destination.trends)
      if feature("testing") {
        SDPlayerTestingView()
          .tabItem { Label(term("testing", fallback: "Testing"), systemImage: "tablecells") }
          .tag(Destination.testing)
      }
      if feature("bpAnalysis") {
        SDPlayerAnalysisView()
          .tabItem { Label("Analysis", systemImage: "chart.xyaxis.line") }
          .tag(Destination.analysis)
      }
      NavigationStack { playerDevelopmentDestination }
        .tabItem { Label("Development", systemImage: "sparkles.rectangle.stack") }
        .tag(Destination.development)
      NavigationStack { AccountView() }
        .tabItem { Label("Account", systemImage: "gearshape") }
        .tag(Destination.account)
    }
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
