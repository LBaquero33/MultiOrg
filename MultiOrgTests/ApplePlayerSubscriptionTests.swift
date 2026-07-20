import Foundation
import Testing
@testable import HomePlate

private struct PurchaseContextFixture: Decodable {
  let organizationId: UUID
  let playerId: UUID
  let billingUserId: UUID
  let canonicalInput: String
  let expectedAppAccountToken: UUID

  enum CodingKeys: String, CodingKey {
    case organizationId = "organization_id"
    case playerId = "player_id"
    case billingUserId = "billing_user_id"
    case canonicalInput = "canonical_input"
    case expectedAppAccountToken = "app_account_token"
  }
}

private enum FixtureLoader {
  static func purchaseContexts() throws -> [PurchaseContextFixture] {
    let bundle = Bundle(for: BundleMarker.self)
    let url = try #require(
      bundle.url(
        forResource: "apple_player_purchase_context_vectors",
        withExtension: "json"
      )
    )
    return try JSONDecoder().decode([PurchaseContextFixture].self, from: Data(contentsOf: url))
  }
}

private final class BundleMarker {}

@Suite("Apple player purchase context")
struct ApplePlayerPurchaseContextTests {
  @Test("Swift matches every shared token vector")
  func sharedVectors() throws {
    for fixture in try FixtureLoader.purchaseContexts() {
      let context = try #require(
        ApplePlayerPurchaseContext.make(
          organizationId: fixture.organizationId,
          playerId: fixture.playerId,
          billingUserId: fixture.billingUserId
        )
      )
      #expect(context.canonicalInput == fixture.canonicalInput)
      #expect(context.appAccountToken == fixture.expectedAppAccountToken)
    }
  }

  @Test("Every purchase-context identity contributes to the token")
  func tokenChangesWithContext() throws {
    let fixture = try #require(try FixtureLoader.purchaseContexts().first)
    let baseline = try #require(
      ApplePlayerPurchaseContext.make(
        organizationId: fixture.organizationId,
        playerId: fixture.playerId,
        billingUserId: fixture.billingUserId
      )
    )
    let changedOrg = try #require(
      ApplePlayerPurchaseContext.make(
        organizationId: UUID(),
        playerId: fixture.playerId,
        billingUserId: fixture.billingUserId
      )
    )
    let changedPlayer = try #require(
      ApplePlayerPurchaseContext.make(
        organizationId: fixture.organizationId,
        playerId: UUID(),
        billingUserId: fixture.billingUserId
      )
    )
    let changedBillingUser = try #require(
      ApplePlayerPurchaseContext.make(
        organizationId: fixture.organizationId,
        playerId: fixture.playerId,
        billingUserId: UUID()
      )
    )
    #expect(changedOrg.appAccountToken != baseline.appAccountToken)
    #expect(changedPlayer.appAccountToken != baseline.appAccountToken)
    #expect(changedBillingUser.appAccountToken != baseline.appAccountToken)
  }
}

@Suite("Apple subscription trust policy")
struct AppleSubscriptionFlowPolicyTests {
  private func context() throws -> ApplePlayerPurchaseContext {
    let fixture = try #require(try FixtureLoader.purchaseContexts().first)
    return try #require(
      ApplePlayerPurchaseContext.make(
        organizationId: fixture.organizationId,
        playerId: fixture.playerId,
        billingUserId: fixture.billingUserId
      )
    )
  }

  @Test("Only a verified matching StoreKit transaction is accepted")
  func verifiedMatchingTransaction() throws {
    let context = try context()
    try PlayerSubscriptionFlowPolicy.validate(
      disposition: .verified,
      productID: ApplePlayerPurchaseContext.monthlyProductID,
      appAccountToken: context.appAccountToken,
      context: context
    )
  }

  @Test("Unverified StoreKit transactions are rejected")
  func unverifiedTransaction() throws {
    let context = try context()
    #expect(throws: PlayerSubscriptionFailure.transactionUnverified) {
      try PlayerSubscriptionFlowPolicy.validate(
        disposition: .unverified,
        productID: context.productId,
        appAccountToken: context.appAccountToken,
        context: context
      )
    }
  }

  @Test("Product and app-account-token mismatches are rejected")
  func contextMismatches() throws {
    let context = try context()
    #expect(throws: PlayerSubscriptionFailure.productMismatch) {
      try PlayerSubscriptionFlowPolicy.validate(
        disposition: .verified,
        productID: "wrong.product",
        appAccountToken: context.appAccountToken,
        context: context
      )
    }
    #expect(throws: PlayerSubscriptionFailure.tokenMismatch) {
      try PlayerSubscriptionFlowPolicy.validate(
        disposition: .verified,
        productID: context.productId,
        appAccountToken: UUID(),
        context: context
      )
    }
  }

  @Test("StoreKit finish and paywall dismissal require separate backend facts")
  func completionGates() {
    #expect(!PlayerSubscriptionFlowPolicy.mayFinishTransaction(
      backendPersisted: false,
      entitlementSynchronized: true
    ))
    #expect(!PlayerSubscriptionFlowPolicy.mayFinishTransaction(
      backendPersisted: true,
      entitlementSynchronized: false
    ))
    #expect(PlayerSubscriptionFlowPolicy.mayFinishTransaction(
      backendPersisted: true,
      entitlementSynchronized: true
    ))
    #expect(!PlayerSubscriptionFlowPolicy.mayDismissPaywall(accessIsActive: false))
    #expect(PlayerSubscriptionFlowPolicy.mayDismissPaywall(accessIsActive: true))
  }
}
