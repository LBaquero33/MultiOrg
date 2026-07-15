import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
final class DHDApplicationDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    NotificationCenter.default.post(name: .dhdRemoteDeviceToken, object: deviceToken)
  }

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NotificationCenter.default.post(name: .dhdRemoteRegistrationFailed, object: nil)
  }
}
#elseif canImport(AppKit)
final class DHDApplicationDelegate: NSObject, NSApplicationDelegate {
  func application(
    _ application: NSApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    NotificationCenter.default.post(name: .dhdRemoteDeviceToken, object: deviceToken)
  }

  func application(
    _ application: NSApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NotificationCenter.default.post(name: .dhdRemoteRegistrationFailed, object: nil)
  }
}
#endif

final class DHDNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    if RemoteNotificationReference(userInfo: notification.request.content.userInfo) != nil {
      NotificationCenter.default.post(name: .dhdRemoteNotificationReceived, object: nil)
    }
    return [.banner, .list, .sound]
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    if let reference = RemoteNotificationReference(
      userInfo: response.notification.request.content.userInfo
    ) {
      NotificationCenter.default.post(name: .dhdOpenRemoteNotification, object: reference.notificationId)
      return
    }
    guard let raw = response.notification.request.content.userInfo["channel_id"] as? String,
          let channelId = UUID(uuidString: raw) else { return }
    NotificationCenter.default.post(name: .dhdOpenChatChannel, object: channelId)
  }
}

enum DHDNotificationCategories {
  static func register() {
    let chat = UNNotificationCategory(identifier: "chat_message", actions: [], intentIdentifiers: [], options: [])
    let booking = UNNotificationCategory(identifier: "facility_booking_request", actions: [], intentIdentifiers: [], options: [])
    let homePlate = UNNotificationCategory(identifier: "HOME_PLATE_NOTIFICATION", actions: [], intentIdentifiers: [], options: [])
    UNUserNotificationCenter.current().setNotificationCategories([chat, booking, homePlate])
  }
}

extension Notification.Name {
  static let dhdOpenChatChannel = Notification.Name("dhdOpenChatChannel")
  static let dhdRemoteDeviceToken = Notification.Name("dhdRemoteDeviceToken")
  static let dhdRemoteRegistrationFailed = Notification.Name("dhdRemoteRegistrationFailed")
  static let dhdRemoteNotificationReceived = Notification.Name("dhdRemoteNotificationReceived")
  static let dhdOpenRemoteNotification = Notification.Name("dhdOpenRemoteNotification")
}

@main
struct MultiOrgApp: App {
  #if canImport(UIKit)
  @UIApplicationDelegateAdaptor(DHDApplicationDelegate.self) private var applicationDelegate
  #elseif canImport(AppKit)
  @NSApplicationDelegateAdaptor(DHDApplicationDelegate.self) private var applicationDelegate
  #endif
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
