import Combine
import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
protocol PushDeviceRegistrationServicing: AnyObject {
  func registerPushDevice(_ request: PushDeviceRegisterRequest) async throws -> PushDevice
  func unregisterPushDevice(_ request: PushDeviceUnregisterRequest) async throws
}

extension SupabaseService: PushDeviceRegistrationServicing {}

@MainActor
protocol PushNotificationSystem: AnyObject {
  func authorizationStatus() async -> UNAuthorizationStatus
  func requestAuthorization() async throws -> Bool
  func registerForRemoteNotifications()
  func openSystemSettings()
}

@MainActor
final class ApplePushNotificationSystem: PushNotificationSystem {
  func authorizationStatus() async -> UNAuthorizationStatus {
    await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
  }

  func requestAuthorization() async throws -> Bool {
    try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
  }

  func registerForRemoteNotifications() {
    #if canImport(UIKit)
    UIApplication.shared.registerForRemoteNotifications()
    #elseif canImport(AppKit)
    NSApplication.shared.registerForRemoteNotifications()
    #endif
  }

  func openSystemSettings() {
    #if canImport(UIKit)
    guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
    UIApplication.shared.open(url)
    #elseif canImport(AppKit)
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
      NSWorkspace.shared.open(url)
    }
    #endif
  }
}

@MainActor
final class PushNotificationManager: ObservableObject {
  enum RegistrationState: Equatable {
    case idle, waitingForToken, registering, registered, failed(String)
  }

  @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
  @Published private(set) var registrationState: RegistrationState = .idle

  private let system: any PushNotificationSystem
  private let defaults: UserDefaults
  private let registrationFacts: () -> (PushEnvironment, String, PushPlatform)?
  private let tokenKey = "homePlate.apnsDeviceToken"
  private var actorId: UUID?
  private weak var service: (any PushDeviceRegistrationServicing)?

  init(
    system: any PushNotificationSystem = ApplePushNotificationSystem(),
    defaults: UserDefaults = .standard,
    registrationFacts: @escaping () -> (PushEnvironment, String, PushPlatform)? = {
      guard let environment = PushNotificationManager.environment,
            let bundleId = Bundle.main.bundleIdentifier else { return nil }
      return (environment, bundleId, .current)
    }
  ) {
    self.system = system
    self.defaults = defaults
    self.registrationFacts = registrationFacts
  }

  var isRegistered: Bool { registrationState == .registered }
  var canRequestPermission: Bool { authorizationStatus == .notDetermined }

  func configure(actorId: UUID?, service: (any PushDeviceRegistrationServicing)?) async {
    self.actorId = actorId
    self.service = service
    authorizationStatus = await system.authorizationStatus()
    guard actorId != nil, service != nil else {
      registrationState = .idle
      return
    }
    if authorizationStatus == .denied {
      if let token = defaults.string(forKey: tokenKey), let request = unregisterRequest(token: token) {
        try? await service?.unregisterPushDevice(request)
      }
      registrationState = .idle
      return
    }
    guard Self.allowsRemoteRegistration(authorizationStatus) else {
      registrationState = .idle
      return
    }
    system.registerForRemoteNotifications()
    if let token = defaults.string(forKey: tokenKey) {
      await register(token: token)
    } else {
      registrationState = .waitingForToken
    }
  }

  func requestPermission() async {
    do {
      _ = try await system.requestAuthorization()
      await configure(actorId: actorId, service: service)
    } catch {
      authorizationStatus = await system.authorizationStatus()
      registrationState = .failed("Notification permission could not be requested.")
    }
  }

  func receiveDeviceToken(_ data: Data) async {
    let token = data.apnsTokenHex
    guard !token.isEmpty else { return }
    defaults.set(token, forKey: tokenKey)
    #if DEBUG
    print("APNs token received suffix=\(token.suffix(6)) environment=\(Self.environment?.rawValue ?? "unknown")")
    #endif
    await register(token: token)
  }

  func receiveRegistrationFailure() {
    registrationState = .failed("Apple push registration did not complete. Try again later.")
  }

  func detachBeforeSignOut() async {
    guard let token = defaults.string(forKey: tokenKey), let service,
          let request = unregisterRequest(token: token) else {
      actorId = nil
      service = nil
      registrationState = .idle
      return
    }
    do { try await service.unregisterPushDevice(request) } catch {
      // The next authenticated registration transfers a shared device token
      // atomically, preventing cross-account delivery even after an offline sign-out.
    }
    actorId = nil
    self.service = nil
    registrationState = .idle
  }

  func refresh() async { await configure(actorId: actorId, service: service) }
  func openSystemSettings() { system.openSystemSettings() }

  private func register(token: String) async {
    guard actorId != nil, let service, let request = registerRequest(token: token) else { return }
    registrationState = .registering
    do {
      _ = try await service.registerPushDevice(request)
      registrationState = .registered
    } catch {
      registrationState = .failed(error.localizedDescription)
    }
  }

  static var environment: PushEnvironment? {
    PushEnvironment.fromBuildValue(Bundle.main.object(forInfoDictionaryKey: "DHD_APNS_ENVIRONMENT") as? String)
  }

  static func allowsRemoteRegistration(_ status: UNAuthorizationStatus) -> Bool {
    #if os(iOS)
    status == .authorized || status == .provisional || status == .ephemeral
    #else
    status == .authorized || status == .provisional
    #endif
  }

  private func registerRequest(token: String) -> PushDeviceRegisterRequest? {
    guard let (environment, bundleId, platform) = registrationFacts() else { return nil }
    return PushDeviceRegisterRequest(
      device_token: token.lowercased(),
      platform: platform,
      environment: environment,
      app_bundle_id: bundleId,
      app_version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
      os_version: ProcessInfo.processInfo.operatingSystemVersionString,
      notifications_authorized: true
    )
  }

  private func unregisterRequest(token: String) -> PushDeviceUnregisterRequest? {
    guard let (environment, bundleId, platform) = registrationFacts() else { return nil }
    return PushDeviceUnregisterRequest(
      device_token: token.lowercased(), platform: platform,
      environment: environment, app_bundle_id: bundleId
    )
  }
}
