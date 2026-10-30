import Foundation

/// A clock sample is process-local. Never reuse monotonic anchors after restart.
public struct GameVideoClockAnchor: Sendable {
  public let serverDate: Date
  public let monotonicSeconds: Double
  public let uncertaintySeconds: Double
  public init(serverDate: Date, sent: Double, received: Double) throws {
    guard sent.isFinite, received.isFinite, received >= sent else { throw GameVideoTimingError.invalidClock }
    let latency = (received - sent) / 2
    self.serverDate = serverDate.addingTimeInterval(latency)
    monotonicSeconds = received
    uncertaintySeconds = latency
  }
  public func timestamp(at monotonic: Double) throws -> GameVideoTimestamp {
    guard monotonic.isFinite, monotonic >= monotonicSeconds else { throw GameVideoTimingError.invalidClock }
    let elapsed = monotonic - monotonicSeconds
    return .init(enteredAt: serverDate.addingTimeInterval(elapsed), uncertaintyMilliseconds: (uncertaintySeconds + elapsed * 0.0001) * 1000)
  }
}
public enum GameVideoTimingError: Error { case invalidClock }
public struct GameVideoTimestamp: Codable, Sendable {
  public let enteredAt: Date
  public let uncertaintyMilliseconds: Double?
  public init(enteredAt: Date, uncertaintyMilliseconds: Double?) {
    self.enteredAt = enteredAt; self.uncertaintyMilliseconds = uncertaintyMilliseconds
  }
}
public struct GameVideoCaptureMarker: Codable, Sendable {
  public let eventID: UUID
  public let playID: UUID
  public let timestamp: GameVideoTimestamp
  public let completedPlay: Bool
  public static func make(play: ScoringPlay, timestamp: GameVideoTimestamp) -> Self? {
    var first: ScoringEvent?
    var completed = false
    for event in play.events {
      switch event.payload {
      case .pitch: if first == nil { first = event }
      case .plateAppearance, .runner: if first == nil { first = event }; completed = true
      default: break
      }
    }
    guard let first else { return nil }
    return .init(eventID: first.id, playID: play.id, timestamp: timestamp, completedPlay: completed)
  }
}
