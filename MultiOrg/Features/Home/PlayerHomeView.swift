import SwiftUI

struct PlayerHomeView: View {
  @EnvironmentObject private var appState: AppState
  @State private var showAccount = false

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
#else
    TabView {
      SDPlayerTodayView()
        .tabItem { Label("Today", systemImage: "sun.max") }
      SDPlayerCalendarView()
        .tabItem { Label("Calendar", systemImage: "calendar") }
      if feature("chat") {
        ChatChannelListView()
          .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
      }
      if feature("facilities") {
        SDPlayerFacilitiesView()
          .tabItem { Label(term("facilities", fallback: "Facilities"), systemImage: "building.2") }
      }
      SDPlayerTrendsView()
        .tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }
      if feature("testing") {
        SDPlayerTestingView()
          .tabItem { Label(term("testing", fallback: "Testing"), systemImage: "tablecells") }
      }
      if feature("bpAnalysis") {
        SDPlayerAnalysisView()
          .tabItem { Label("Analysis", systemImage: "chart.xyaxis.line") }
      }
      NavigationStack { AccountView() }
        .tabItem { Label("Account", systemImage: "gearshape") }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
#endif
  }

  private func term(_ key: String, fallback: String) -> String {
    appState.activeOrgSettings?.term(key, fallback: fallback) ?? fallback
  }

  private func feature(_ key: String) -> Bool {
    appState.activeOrgSettings?.feature(key) ?? true
  }
}
