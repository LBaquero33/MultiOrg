import Foundation
import Testing
@testable import HomePlate

struct TrainingCatalogTests {
  @Test func offeringDraftPreservesOverrides() throws {
    let service = HPTrainingWorkspace.Service(id: UUID(), name: "Hitting")
    let location = UUID(), resource = UUID()
    var offering = HPTrainingWorkspace.Offering(service_id: service.id, trainer_directory_id: UUID(), active: true)
    offering.public_price_cents = 9000; offering.member_price_cents = 7500
    offering.duration_minutes_override = 45; offering.capacity_override = 2
    offering.location_ids = [location]; offering.resource_ids = [resource]
    offering.public_visible = true; offering.booking_mode_override = "paid"
    let draft = HPTrainingOfferingDraft(service: service, existing: offering)
    #expect(draft.isValid)
    #expect(draft.payload["public_price_cents"] == .int(9000))
    #expect(draft.payload["member_price_cents"] == .int(7500))
    #expect(draft.payload["resource_ids"] == .array([.string(resource.uuidString)]))
    #expect(draft.payload["location_ids"] == .array([.string(location.uuidString)]))
    #expect(draft.payload["booking_mode_override"] == .string("paid"))
  }
  @Test func offeringValidationRejectsFractionalAndNegativeOverrides() {
    var draft = HPTrainingOfferingDraft(service: .init(id: UUID(), name: "Pitching"), existing: nil)
    #expect(draft.isValid)
    draft.publicPrice = "-1"; #expect(!draft.isValid)
    draft.publicPrice = "1.5"; #expect(!draft.isValid)
    draft.publicPrice = "0"; draft.duration = "481"; #expect(!draft.isValid)
    draft.duration = "45"; draft.capacity = "0"; #expect(!draft.isValid)
    draft.capacity = "2"; #expect(draft.isValid)
    #expect(draft.payload["member_price_cents"] == .null)
    #expect(draft.payload["public_visible"] == .bool(false))
  }
}
