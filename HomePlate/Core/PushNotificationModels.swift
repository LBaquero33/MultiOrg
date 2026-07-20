import Foundation

enum PushPlatform: String, Codable, Sendable {
  case ios
  case macos

  static var current: PushPlatform {
    #if os(macOS)
    .macos
    #else
    .ios
    #endif
  }
}

enum PushEnvironment: String, Codable, Sendable {
  case sandbox
  case production

  static func fromBuildValue(_ value: String?) -> PushEnvironment? {
    switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "development", "sandbox": .sandbox
    case "production": .production
    default: nil
    }
  }
}

struct PushDevice: Decodable, Equatable, Sendable {
  let id: UUID
  let platform: PushPlatform
  let environment: PushEnvironment
  let appBundleId: String
  let notificationsAuthorized: Bool
  let lastRegisteredAt: String
  let disabledAt: String?

  private enum CodingKeys: String, CodingKey {
    case id, platform, environment
    case appBundleId = "app_bundle_id"
    case notificationsAuthorized = "notifications_authorized"
    case lastRegisteredAt = "last_registered_at"
    case disabledAt = "disabled_at"
  }
}

struct PushDeviceResponse: Decodable, Equatable, Sendable { let device: PushDevice }
struct PushDeviceUnregisterResponse: Decodable, Equatable, Sendable { let unregistered: Bool }

struct PushDeviceRegisterRequest: Encodable, Equatable, Sendable {
  let action = "register"
  let device_token: String
  let platform: PushPlatform
  let environment: PushEnvironment
  let app_bundle_id: String
  let app_version: String?
  let os_version: String?
  let notifications_authorized: Bool
}

struct PushDeviceUnregisterRequest: Encodable, Equatable, Sendable {
  let action = "unregister"
  let device_token: String
  let platform: PushPlatform
  let environment: PushEnvironment
  let app_bundle_id: String
}

struct RemoteNotificationReference: Equatable, Sendable {
  let notificationId: UUID

  init?(userInfo: [AnyHashable: Any]) {
    guard let homePlate = userInfo["home_plate"] as? [String: Any],
          homePlate["schema_version"] as? String == "notification_v1",
          let raw = homePlate["notification_id"] as? String,
          let notificationId = UUID(uuidString: raw) else { return nil }
    self.notificationId = notificationId
  }
}

extension Data {
  var apnsTokenHex: String { map { String(format: "%02x", $0) }.joined() }
}
