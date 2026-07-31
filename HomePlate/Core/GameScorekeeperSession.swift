import Foundation

enum SDLiveDeviceState: String, Codable, Sendable {
  case liveScorekeeper, liveViewer, requestingControl, disconnected
}

struct SDScorekeeperLease: Codable, Equatable, Sendable {
  let state: SDLiveDeviceState
  let control_token: String?
  let lease_expires_at: Date?
  let game_version: Int
}

struct SDControlRequest: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let org_id: UUID
  let game_id: UUID
  let requesting_user_id: UUID
  let requesting_device_id: UUID
  let status: String
  let requested_at: Date
}

struct SDControlRequestLease: Codable, Equatable, Sendable {
  let request_id: UUID
  let state: SDLiveDeviceState
  let control_token: String
}

enum SDScorekeeperControlState: Equatable, Sendable {
  case viewer
  case requesting
  case scorekeeper(expiresAt: Date?)
  case disconnected

  var canMutate: Bool {
    if case .scorekeeper = self { return true }
    return false
  }
}

enum SDScorekeeperLeasePolicy {
  static let duration: TimeInterval = 45
  static let heartbeatInterval: TimeInterval = 15

  static func state(afterReconnectAt now: Date, leaseExpiration: Date?) -> SDScorekeeperControlState {
    guard let leaseExpiration, leaseExpiration > now else { return .viewer }
    return .scorekeeper(expiresAt: leaseExpiration)
  }

  static func shouldRenew(now: Date, leaseExpiration: Date?) -> Bool {
    guard let leaseExpiration else { return false }
    return leaseExpiration.timeIntervalSince(now) <= heartbeatInterval * 2
  }
}
