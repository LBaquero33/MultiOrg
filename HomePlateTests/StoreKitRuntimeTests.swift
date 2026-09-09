import XCTest
import StoreKit
import StoreKitTest
@testable import HomePlate

/// Local Apple StoreKit runtime, not a mocked transaction or production receipt.
/// No transaction from this configuration is submitted to the live backend.
@MainActor final class StoreKitRuntimeTests: XCTestCase {
  func testProductPurchaseAndRestoreEnumeration() async throws {
    guard ProcessInfo.processInfo.environment["HOMEPLATE_STOREKIT_TESTS"] == "1" else {
      throw XCTSkip("Run using HomePlateStoreKitAudit; production schemes must not enable local commerce.")
    }
    let session = try SKTestSession(configurationFileNamed: "HomePlatePlayerAccess")
    session.disableDialogs = true
    session.clearTransactions()
    defer { session.clearTransactions() }
    let products = try await Product.products(for: [ApplePlayerPurchaseContext.monthlyProductID])
    let product = try XCTUnwrap(products.first)
    XCTAssertEqual(product.type, .autoRenewable)
    let token = UUID()
    let purchased = try await session.buyProduct(identifier: product.id, options: [.appAccountToken(token)])
    XCTAssertEqual(purchased.productID, product.id)
    XCTAssertEqual(purchased.appAccountToken, token)
    await purchased.finish()
    // A previously finished purchase must remain discoverable by Restore.
    let restored = await Transaction.latest(for: product.id)
    guard case .verified(let transaction) = restored else { return XCTFail("Finished subscription missing from restore enumeration") }
    XCTAssertEqual(transaction.originalID, purchased.originalID)
    XCTAssertEqual(transaction.appAccountToken, token)
  }
}
