import Foundation

enum SDLiveDeviceState: String, Codable, Sendable {
  case liveScorekeeper, liveViewer, requestingControl, disconnected, reconciliationRequired
}

struct SDScorekeeperLease: Codable, Equatable, Sendable {
  let state: SDLiveDeviceState
  let control_token: String?
  let lease_expires_at: Date?
  let game_version: Int
  let authority_epoch: Int?
  let active_user_id: UUID?
  let active_device_id: UUID?
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
  case reconciliationRequired

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

enum SDScoringSessionIdentifierError: Error {
  case missingJWTSessionIdentifier
}

enum SDScorekeepingFailureDisposition {
  case retryTransport
  case freezeForReview

  static func classify(_ error: Error, depth: Int = 0) -> Self {
    guard depth < 8 else { return .freezeForReview }
    if error is CancellationError { return .retryTransport }
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
      switch nsError.code {
      case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
           NSURLErrorTimedOut, NSURLErrorCannotConnectToHost,
           NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed,
           NSURLErrorInternationalRoamingOff, NSURLErrorDataNotAllowed,
           NSURLErrorResourceUnavailable:
        return .retryTransport
      default:
        return .freezeForReview
      }
    }
    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
      return classify(underlying, depth: depth + 1)
    }
    if let underlyingErrors = nsError.userInfo["NSMultipleUnderlyingErrors"] as? [Error],
       underlyingErrors.contains(where: { classify($0, depth: depth + 1) == .retryTransport }) {
      return .retryTransport
    }
    return .freezeForReview
  }
}

extension SDScorekeepingFailureDisposition: Equatable {}

enum SDLegacyScoringCommandPolicy {
  static func canSendOnlineOnly(eventCount: Int) -> Bool { eventCount == 1 }
}
