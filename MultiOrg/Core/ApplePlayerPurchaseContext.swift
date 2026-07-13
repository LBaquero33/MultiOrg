import CryptoKit
import Foundation

/// The only context allowed to associate an Apple player subscription with a
/// Home Plate account. Keep this algorithm in lockstep with the backend test
/// vectors in `SharedFixtures/apple_player_purchase_context_vectors.json`.
struct ApplePlayerPurchaseContext: Sendable, Equatable {
  static let monthlyProductID = "com.homeplate.player.monthly"

  let organizationId: UUID
  let playerId: UUID
  let billingUserId: UUID
  let productId: String
  let appAccountToken: UUID

  static func make(
    organizationId: UUID,
    playerId: UUID,
    billingUserId: UUID,
    productId: String = monthlyProductID
  ) -> ApplePlayerPurchaseContext? {
    guard productId == monthlyProductID else { return nil }
    let token = CanonicalApplePurchaseToken.make(
      organizationId: organizationId,
      playerId: playerId,
      billingUserId: billingUserId
    )
    return ApplePlayerPurchaseContext(
      organizationId: organizationId,
      playerId: playerId,
      billingUserId: billingUserId,
      productId: productId,
      appAccountToken: token
    )
  }

  var canonicalInput: String {
    CanonicalApplePurchaseToken.seed(
      organizationId: organizationId,
      playerId: playerId,
      billingUserId: billingUserId
    )
  }
}

enum CanonicalApplePurchaseToken {
  static func seed(
    organizationId: UUID,
    playerId: UUID,
    billingUserId: UUID
  ) -> String {
    [organizationId, playerId, billingUserId]
      .map { $0.uuidString.lowercased() }
      .joined(separator: "|")
  }

  static func make(
    organizationId: UUID,
    playerId: UUID,
    billingUserId: UUID
  ) -> UUID {
    let canonicalSeed = seed(
      organizationId: organizationId,
      playerId: playerId,
      billingUserId: billingUserId
    )
    var bytes = Array(SHA256.hash(data: Data(canonicalSeed.utf8)).prefix(16))
    precondition(bytes.count == 16)

    // RFC 4122 version 5 and variant bits. SHA-256 supplies the digest while
    // the UUID bits make StoreKit's appAccountToken representation canonical.
    bytes[6] = (bytes[6] & 0x0f) | 0x50
    bytes[8] = (bytes[8] & 0x3f) | 0x80

    let hex = bytes.map { String(format: "%02x", $0) }.joined()
    let value = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))"
    guard let uuid = UUID(uuidString: value) else {
      preconditionFailure("Canonical Apple purchase token must be a UUID")
    }
    return uuid
  }
}
