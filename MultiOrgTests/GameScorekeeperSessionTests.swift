import Foundation
import Testing
@testable import MultiOrg

struct GameScorekeeperSessionTests {
  @Test func activeLeaseMutates() {
    let state = SDScorekeeperLeasePolicy.state(
      afterReconnectAt: Date(), leaseExpiration: Date().addingTimeInterval(30)
    )
    #expect(state.canMutate)
  }

  @Test func expiredLeaseReturnsViewer() {
    let state = SDScorekeeperLeasePolicy.state(
      afterReconnectAt: Date(), leaseExpiration: Date().addingTimeInterval(-1)
    )
    #expect(state == .viewer)
    #expect(!state.canMutate)
  }

  @Test func disconnectedNeverMutates() {
    #expect(!SDScorekeeperControlState.disconnected.canMutate)
    #expect(!SDScorekeeperControlState.requesting.canMutate)
  }

  @Test func leaseRenewsBeforeExpiry() {
    let now = Date()
    #expect(SDScorekeeperLeasePolicy.shouldRenew(
      now: now, leaseExpiration: now.addingTimeInterval(20)
    ))
    #expect(!SDScorekeeperLeasePolicy.shouldRenew(
      now: now, leaseExpiration: now.addingTimeInterval(40)
    ))
  }
}
