import CryptoKit
import Foundation
import StoreKit

struct PlayerSubscriptionContext: Sendable, Equatable {
  let orgId: UUID
  let playerId: UUID
  let billingUserId: UUID
  let appAccountToken: UUID

  static func make(orgId: UUID, playerId: UUID, billingUserId: UUID) -> PlayerSubscriptionContext? {
    let seed = "\(orgId.uuidString.lowercased())|\(playerId.uuidString.lowercased())|\(billingUserId.uuidString.lowercased())"
    var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
    guard bytes.count == 16 else { return nil }
    bytes[6] = (bytes[6] & 0x0F) | 0x50
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    let hex = bytes.map { String(format: "%02x", $0) }.joined()
    guard let token = UUID(uuidString: "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))") else { return nil }
    return PlayerSubscriptionContext(orgId: orgId, playerId: playerId, billingUserId: billingUserId, appAccountToken: token)
  }
}

@MainActor
final class PlayerSubscriptionStore: ObservableObject {
  static let monthlyProductID = "com.homeplate.player.monthly"

  enum State: Equatable {
    case idle, loading, loaded, unavailable, purchasing, pending, purchased, canceled, restored, failed(String)
  }

  struct VerifiedPurchase: Identifiable, Equatable {
    let id: UInt64
    let originalTransactionID: UInt64
    let signedTransaction: String
    let productID: String
    let appAccountToken: UUID?
  }

  @Published private(set) var state: State = .idle
  @Published private(set) var product: Product?
  @Published private(set) var pendingPurchase: VerifiedPurchase?

  private var updateTask: Task<Void, Never>?
  private var pendingTransactions: [UInt64: Transaction] = [:]
  private var processedTransactionIDs = Set<UInt64>()

  init() {
    updateTask = Task { [weak self] in
      for await result in Transaction.updates {
        _ = await self?.capture(result, restored: false)
      }
    }
  }

  deinit { updateTask?.cancel() }

  func loadProduct() async {
    state = .loading
    do {
      let products = try await Product.products(for: [Self.monthlyProductID])
      product = products.first(where: { $0.id == Self.monthlyProductID })
      state = product == nil ? .unavailable : .loaded
    } catch {
      product = nil
      state = .failed("Apple subscription information is unavailable. Please try again.")
    }
  }

  func purchase(context: PlayerSubscriptionContext) async -> VerifiedPurchase? {
    guard let product else { state = .unavailable; return nil }
    state = .purchasing
    do {
      switch try await product.purchase(options: [.appAccountToken(context.appAccountToken)]) {
      case .success(let verification): return await capture(verification, restored: false)
      case .pending: state = .pending
      case .userCancelled: state = .canceled
      @unknown default: state = .failed("The purchase did not complete. Please try again.")
      }
    } catch {
      state = .failed("Apple could not complete this purchase. Please try again.")
    }
    return nil
  }

  func restorePurchases() async -> VerifiedPurchase? {
    state = .loading
    do {
      try await AppStore.sync()
      let restoredPurchase = await refreshCurrentEntitlements(restored: true)
      if pendingPurchase == nil, state == .loading { state = .restored }
      return restoredPurchase
    } catch {
      state = .failed("Purchases could not be restored. Please try again.")
      return nil
    }
  }

  func refreshCurrentEntitlements(restored: Bool = false) async -> VerifiedPurchase? {
    var capturedPurchase: VerifiedPurchase?
    for await result in Transaction.currentEntitlements {
      capturedPurchase = await capture(result, restored: restored) ?? capturedPurchase
    }
    if pendingPurchase == nil, state == .loading { state = product == nil ? .unavailable : .loaded }
    return capturedPurchase ?? pendingPurchase
  }

  func finishPendingTransaction(id: UInt64) async {
    guard let transaction = pendingTransactions.removeValue(forKey: id) else { return }
    await transaction.finish()
    pendingPurchase = nil
    state = .purchased
  }

  private func capture(_ result: VerificationResult<Transaction>, restored: Bool) async -> VerifiedPurchase? {
    switch result {
    case .verified(let transaction):
      guard transaction.productID == Self.monthlyProductID else { return nil }
      if processedTransactionIDs.contains(transaction.id) {
        return pendingPurchase?.id == transaction.id ? pendingPurchase : nil
      }
      processedTransactionIDs.insert(transaction.id)
      pendingTransactions[transaction.id] = transaction
      let purchase = VerifiedPurchase(
        id: transaction.id,
        originalTransactionID: transaction.originalID,
        signedTransaction: result.jwsRepresentation,
        productID: transaction.productID,
        appAccountToken: transaction.appAccountToken
      )
      pendingPurchase = purchase
      state = restored ? .restored : .purchased
      return purchase
    case .unverified:
      state = .failed("Apple could not verify this transaction.")
      return nil
    }
  }
}
