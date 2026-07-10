import SwiftUI
import UserNotifications

final class DHDNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound]
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    guard let raw = response.notification.request.content.userInfo["channel_id"] as? String,
          let channelId = UUID(uuidString: raw) else { return }
    NotificationCenter.default.post(name: .dhdOpenChatChannel, object: channelId)
  }
}

enum DHDNotificationCategories {
  static func register() {
    let chat = UNNotificationCategory(identifier: "chat_message", actions: [], intentIdentifiers: [], options: [])
    let booking = UNNotificationCategory(identifier: "facility_booking_request", actions: [], intentIdentifiers: [], options: [])
    UNUserNotificationCenter.current().setNotificationCategories([chat, booking])
  }
}

extension Notification.Name {
  static let dhdOpenChatChannel = Notification.Name("dhdOpenChatChannel")
}

@main
struct MultiOrgApp: App {
  @StateObject private var appState = AppState()
  private let notificationDelegate = DHDNotificationDelegate()

  init() {
    DHDNotificationCategories.register()
    UNUserNotificationCenter.current().delegate = notificationDelegate
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(appState)
        #if os(macOS)
        .preferredColorScheme(.dark)
        #endif
        .task { await appState.bootstrap() }
    }
    #if os(macOS)
    .defaultSize(width: 1220, height: 820)
    #endif
  }
}
