import Foundation
import StoreKit

struct PlayerSubscriptionFailure: Error, Equatable, Sendable, LocalizedError {
  let code: String
  let message: String

  var errorDescription: String? { message }

  static let operationInProgress = PlayerSubscriptionFailure(
    code: "subscription_operation_in_progress",
    message: "Another subscription action is already in progress. Please wait a moment."
  )
  static let productUnavailable = PlayerSubscriptionFailure(
    code: "apple_product_unavailable",
    message: "Apple subscription information is unavailable right now. Please try again."
  )
  static let transactionUnverified = PlayerSubscriptionFailure(
    code: "apple_transaction_unverified",
    message: "Apple could not verify this transaction. No access was granted."
  )
  static let tokenMismatch = PlayerSubscriptionFailure(
    code: "app_account_token_mismatch",
    message: "This purchase belongs to a different player, organization, or paying account. Contact support before trying again."
  )
  static let productMismatch = PlayerSubscriptionFailure(
    code: "apple_product_id_mismatch",
    message: "The recovered purchase is not the Home Plate monthly player subscription."
  )
  static let noPendingTransaction = PlayerSubscriptionFailure(
    code: "no_pending_transaction_available",
    message: "No matching Apple purchase is available to verify. Try Restore Purchases or contact support."
  )
  static let backendSynchronizationFailed = PlayerSubscriptionFailure(
    code: "backend_subscription_sync_failed",
    message: "Your Apple purchase was found, but Home Plate could not update access. The purchase remains recoverable."
  )
  static let backendAccessInactive = PlayerSubscriptionFailure(
    code: "backend_access_not_active",
    message: "The purchase was recorded, but this player does not currently have active access. Contact your organization for help."
  )
  static let purchaseFailed = PlayerSubscriptionFailure(
    code: "apple_purchase_failed",
    message: "Apple could not complete this purchase. Please try again."
  )
  static let restoreFailed = PlayerSubscriptionFailure(
    code: "apple_restore_failed",
    message: "Purchases could not be restored. Please try again."
  )
}

enum PlayerSubscriptionVerificationDisposition: Equatable, Sendable {
  case verified
  case unverified
}

enum PlayerSubscriptionFlowPolicy {
  static func validate(
    disposition: PlayerSubscriptionVerificationDisposition,
    productID: String,
    appAccountToken: UUID?,
    context: ApplePlayerPurchaseContext
  ) throws {
    guard disposition == .verified else {
      throw PlayerSubscriptionFailure.transactionUnverified
    }
    guard productID == context.productId,
          productID == ApplePlayerPurchaseContext.monthlyProductID else {
      throw PlayerSubscriptionFailure.productMismatch
    }
    guard appAccountToken == context.appAccountToken else {
      throw PlayerSubscriptionFailure.tokenMismatch
    }
  }

  static func mayFinishTransaction(
    backendPersisted: Bool,
    entitlementSynchronized: Bool
  ) -> Bool {
    backendPersisted && entitlementSynchronized
  }

  static func mayDismissPaywall(accessIsActive: Bool) -> Bool {
    accessIsActive
  }
}

@MainActor
final class PlayerSubscriptionStore: ObservableObject {
  static let monthlyProductID = ApplePlayerPurchaseContext.monthlyProductID

  enum State: Equatable {
    case idle
    case loadingProduct
    case ready
    case purchasing
    case pending
    case recovering
    case synchronizing
    case active
    case canceled
    case failed(PlayerSubscriptionFailure)
  }

  struct VerifiedPurchase: Identifiable, Equatable, Sendable {
    let id: UInt64
    let originalTransactionID: UInt64
    let productID: String
    let appAccountToken: UUID
    let purchaseDate: Date
    let expirationDate: Date?
    let revocationDate: Date?
    let environment: String
  }

  @Published private(set) var state: State = .idle
  @Published private(set) var product: Product?
  @Published private(set) var pendingPurchase: VerifiedPurchase?

  private enum Operation {
    case preparing
    case purchasing
    case restoring
    case retrying
    case recovering
  }

  private enum CandidateOutcome {
    case accepted(VerifiedPurchase)
    case ignored
    case contextMismatch
    case unverified
  }

  private enum TransactionSource: Equatable {
    case purchase
    case update
    case unfinished
    case currentEntitlement

    var diagnosticName: String {
      switch self {
      case .purchase: return "purchase"
      case .update: return "update"
      case .unfinished: return "unfinished"
      case .currentEntitlement: return "current_entitlement"
      }
    }
  }

  private var updateTask: Task<Void, Never>?
  private var activeContext: ApplePlayerPurchaseContext?
  private var activeOperation: Operation?
  private var pendingTransactions: [UInt64: Transaction] = [:]
  private var synchronizationTransactionIDs = Set<UInt64>()
  private var finishedTransactionIDs = Set<UInt64>()

  init() {
    updateTask = Task { [weak self] in
      for await result in Transaction.updates {
        guard let self, let context = self.activeContext else { continue }
        _ = self.capture(result, context: context, source: .update)
      }
    }
  }

  deinit {
    updateTask?.cancel()
  }

  var isBusy: Bool {
    activeOperation != nil || !synchronizationTransactionIDs.isEmpty
  }

  @discardableResult
  func prepare(context: ApplePlayerPurchaseContext) async -> VerifiedPurchase? {
    guard begin(.preparing) else { return pendingPurchase }
    defer { endOperation() }
    activate(context)
    await loadProductIfNeeded()
    guard product != nil else { return nil }
    state = .recovering
    let recovered = await scanTransactions(
      context: context,
      includeCurrentEntitlements: true,
      missingIsFailure: false
    )
    if recovered == nil, !isFailureState {
      state = .ready
    }
    return recovered
  }

  func purchase(context: ApplePlayerPurchaseContext) async -> VerifiedPurchase? {
    guard begin(.purchasing) else { return nil }
    defer { endOperation() }
    activate(context)
    await loadProductIfNeeded()
    guard let product else {
      fail(.productUnavailable)
      return nil
    }

    state = .purchasing
    do {
      switch try await product.purchase(options: [.appAccountToken(context.appAccountToken)]) {
      case .success(let result):
        switch capture(result, context: context, source: .purchase) {
        case .accepted(let purchase): return purchase
        case .contextMismatch: fail(.tokenMismatch)
        case .unverified: fail(.transactionUnverified)
        case .ignored: fail(.productMismatch)
        }
      case .pending:
        state = .pending
      case .userCancelled:
        state = .canceled
      @unknown default:
        fail(.purchaseFailed)
      }
    } catch {
      fail(.purchaseFailed)
    }
    return nil
  }

  func restorePurchases(context: ApplePlayerPurchaseContext) async -> VerifiedPurchase? {
    guard begin(.restoring) else { return nil }
    defer { endOperation() }
    activate(context)
    state = .recovering
    do {
      try await AppStore.sync()
      return await scanTransactions(
        context: context,
        includeCurrentEntitlements: true,
        missingIsFailure: true
      )
    } catch {
      fail(.restoreFailed)
      return nil
    }
  }

  func retryVerification(context: ApplePlayerPurchaseContext) async -> VerifiedPurchase? {
    diagnostic("retry_started")
    guard begin(.retrying) else { return nil }
    defer { endOperation() }
    activate(context)

    if let pendingPurchase {
      state = .pending
      return pendingPurchase
    }

    state = .recovering
    let recovered = await scanTransactions(
      context: context,
      includeCurrentEntitlements: true,
      missingIsFailure: true
    )
    if recovered == nil {
      diagnostic("retry_no_pending_transaction")
    }
    return recovered
  }

  func recoverForForeground(context: ApplePlayerPurchaseContext) async -> VerifiedPurchase? {
    guard begin(.recovering) else { return nil }
    defer { endOperation() }
    activate(context)
    state = .recovering
    let recovered = await scanTransactions(
      context: context,
      includeCurrentEntitlements: true,
      missingIsFailure: false
    )
    if recovered == nil, !isFailureState {
      state = product == nil ? .idle : .ready
    }
    return recovered
  }

  /// Returns true exactly once for a pending transaction until the matching
  /// backend request completes or fails.
  func beginSynchronization(transactionID: UInt64) -> Bool {
    guard pendingPurchase?.id == transactionID,
          !synchronizationTransactionIDs.contains(transactionID) else {
      return false
    }
    synchronizationTransactionIDs.insert(transactionID)
    state = .synchronizing
    return true
  }

  func synchronizationFailed(
    transactionID: UInt64,
    failure: PlayerSubscriptionFailure
  ) {
    synchronizationTransactionIDs.remove(transactionID)
    fail(failure)
  }

  /// StoreKit is finished only after the backend confirms both persistence and
  /// entitlement synchronization. Active access is a separate backend result.
  func completeSynchronization(
    transactionID: UInt64,
    backendPersisted: Bool,
    entitlementSynchronized: Bool,
    accessIsActive: Bool
  ) async {
    synchronizationTransactionIDs.remove(transactionID)
    guard PlayerSubscriptionFlowPolicy.mayFinishTransaction(
      backendPersisted: backendPersisted,
      entitlementSynchronized: entitlementSynchronized
    ) else {
      fail(.backendSynchronizationFailed)
      return
    }

    if !finishedTransactionIDs.contains(transactionID),
       let transaction = pendingTransactions.removeValue(forKey: transactionID) {
      await transaction.finish()
      finishedTransactionIDs.insert(transactionID)
    }
    if pendingPurchase?.id == transactionID {
      pendingPurchase = nil
    }

    if PlayerSubscriptionFlowPolicy.mayDismissPaywall(accessIsActive: accessIsActive) {
      state = .active
    } else {
      fail(.backendAccessInactive)
    }
  }

  private func loadProductIfNeeded() async {
    guard product == nil else { return }
    state = .loadingProduct
    do {
      let products = try await Product.products(for: [Self.monthlyProductID])
      product = products.first { $0.id == Self.monthlyProductID }
      if product == nil { fail(.productUnavailable) }
    } catch {
      product = nil
      fail(.productUnavailable)
    }
  }

  private func scanTransactions(
    context: ApplePlayerPurchaseContext,
    includeCurrentEntitlements: Bool,
    missingIsFailure: Bool
  ) async -> VerifiedPurchase? {
    var foundContextMismatch = false
    var foundUnverified = false

    for await result in Transaction.unfinished {
      let outcome = capture(result, context: context, source: .unfinished)
      switch outcome {
      case .accepted(let purchase): return purchase
      case .contextMismatch: foundContextMismatch = true
      case .unverified: foundUnverified = true
      case .ignored: break
      }
    }

    if includeCurrentEntitlements {
      for await result in Transaction.currentEntitlements {
        let outcome = capture(result, context: context, source: .currentEntitlement)
        switch outcome {
        case .accepted(let purchase): return purchase
        case .contextMismatch: foundContextMismatch = true
        case .unverified: foundUnverified = true
        case .ignored: break
        }
      }
    }

    if foundContextMismatch {
      fail(.tokenMismatch)
    } else if foundUnverified {
      fail(.transactionUnverified)
    } else if missingIsFailure {
      fail(.noPendingTransaction)
    }
    return nil
  }

  private func capture(
    _ result: VerificationResult<Transaction>,
    context: ApplePlayerPurchaseContext,
    source: TransactionSource
  ) -> CandidateOutcome {
    switch result {
    case .verified(let transaction):
      guard transaction.productID == Self.monthlyProductID else {
        return .ignored
      }
      if source == .unfinished {
        diagnostic("unfinished_transaction_found")
      }
      do {
        try PlayerSubscriptionFlowPolicy.validate(
          disposition: .verified,
          productID: transaction.productID,
          appAccountToken: transaction.appAccountToken,
          context: context
        )
      } catch let failure as PlayerSubscriptionFailure {
        if failure == .tokenMismatch {
          if source == .unfinished {
            diagnostic("unfinished_transaction_context_mismatch")
          }
          return .contextMismatch
        }
        return .ignored
      } catch {
        return .ignored
      }

      diagnostic("transaction_context source=\(source.diagnosticName) token_match=true")

      if source == .unfinished {
        diagnostic("unfinished_transaction_context_match")
      }
      if let existing = pendingPurchase, existing.id == transaction.id {
        return .accepted(existing)
      }

      guard let appAccountToken = transaction.appAccountToken else {
        return .contextMismatch
      }
      let purchase = VerifiedPurchase(
        id: transaction.id,
        originalTransactionID: transaction.originalID,
        productID: transaction.productID,
        appAccountToken: appAccountToken,
        purchaseDate: transaction.purchaseDate,
        expirationDate: transaction.expirationDate,
        revocationDate: transaction.revocationDate,
        environment: transaction.environment.rawValue
      )
      pendingTransactions[transaction.id] = transaction
      pendingPurchase = purchase
      state = .pending
      return .accepted(purchase)

    case .unverified(let transaction, _):
      guard transaction.productID == Self.monthlyProductID else {
        return .ignored
      }
      return .unverified
    }
  }

  private func activate(_ context: ApplePlayerPurchaseContext) {
    guard activeContext != context else { return }
    activeContext = context
    pendingPurchase = nil
    pendingTransactions.removeAll()
    synchronizationTransactionIDs.removeAll()
    state = product == nil ? .idle : .ready
  }

  private func begin(_ operation: Operation) -> Bool {
    guard activeOperation == nil,
          synchronizationTransactionIDs.isEmpty else {
      diagnostic("duplicate_operation_blocked")
      return false
    }
    activeOperation = operation
    return true
  }

  private func endOperation() {
    activeOperation = nil
  }

  private var isFailureState: Bool {
    if case .failed = state { return true }
    return false
  }

  private func fail(_ failure: PlayerSubscriptionFailure) {
    state = .failed(failure)
    diagnostic("failure_\(failure.code)")
  }

  private func diagnostic(_ event: String) {
    print("apple_subscription \(event)")
  }
}
