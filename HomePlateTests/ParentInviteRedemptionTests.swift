import Foundation
import Testing
@testable import HomePlate

@Suite("One-time parent invitation redemption")
struct ParentInviteRedemptionTests {
  @Test("Parent email links bind a UUID invite to one hexadecimal token")
  func validParentInviteLink() {
    let route = SDParentInviteRedemption(url: URL(string:
      "homeplate://parent-invite/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa?token=0123456789abcdef0123456789abcdef"
    )!)
    #expect(route?.inviteId == UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"))
    #expect(route?.token == "0123456789abcdef0123456789abcdef")
  }

  @Test("Malformed, duplicate, empty, and non-hex tokens are rejected")
  func invalidParentInviteLinks() {
    let invalid = [
      "homeplate://parent-invite/not-a-uuid?token=0123456789abcdef0123456789abcdef",
      "homeplate://parent-invite/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      "homeplate://parent-invite/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa?token=0123456789abcdef0123456789abcdeg",
      "homeplate://parent-invite/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa?token=&token=0123456789abcdef0123456789abcdef",
      "https://parent-invite/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa?token=0123456789abcdef0123456789abcdef",
    ]
    for value in invalid {
      #expect(SDParentInviteRedemption(url: URL(string: value)!) == nil)
    }
  }

  @Test("Native parent acceptance uses the server redemption function, never a direct invite update")
  func directUpdateRemoved() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let service = try String(contentsOf: root.appendingPathComponent("HomePlate/Core/SupabaseService.swift"), encoding: .utf8)
    let home = try String(contentsOf: root.appendingPathComponent("HomePlate/Features/Home/ParentHomeView.swift"), encoding: .utf8)
    #expect(service.contains("invokeAuthenticatedFunction(\"parent-invites\""))
    #expect(service.contains("action = \"accept\""))
    #expect(service.contains("let action = \"list\"; let org_id: UUID"))
    #expect(!service.contains(".from(\"sd_parent_invites\")"))
    #expect(!home.contains("listMyParentInvites"))
    #expect(!home.contains("acceptParentInvite(inviteId:"))
  }
}
