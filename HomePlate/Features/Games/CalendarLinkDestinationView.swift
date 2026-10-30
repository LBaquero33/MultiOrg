import SwiftUI

struct CalendarLinkDestinationView: View {
  @EnvironmentObject private var appState: AppState
  let route: HPCalendarLinkRoute

  var body: some View {
    Group {
      switch route.source {
      case .event:
        GameDetailView(eventId: route.sourceId)
      case .booking:
        FacilityBookingLinkView(route: route)
      }
    }
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Done") { appState.clearRequestedCalendarDestination() }
      }
    }
  }
}

private struct FacilityBookingLinkView: View {
  @EnvironmentObject private var appState: AppState
  let route: HPCalendarLinkRoute

  @State private var booking: SDFacilityBooking?
  @State private var facilityName: String?
  @State private var unavailable = false

  var body: some View {
    Group {
      if let booking {
        Form {
          LabeledContent("Status", value: booking.status.capitalized)
          LabeledContent("Activity", value: booking.title?.isEmpty == false
            ? booking.title! : booking.activity_type.capitalized)
          LabeledContent("Facility", value: facilityName ?? "Facility")
          LabeledContent("Starts", value: booking.start_at.formatted(date: .complete, time: .shortened))
          LabeledContent("Ends", value: booking.end_at.formatted(date: .complete, time: .shortened))
          if let notes = booking.notes, !notes.isEmpty {
            Section("Notes") { Text(notes) }
          }
        }
        .navigationTitle("Facility Booking")
      } else if unavailable {
        ContentUnavailableView("Booking unavailable", systemImage: "calendar.badge.exclamationmark",
          description: Text("This booking was removed or is no longer available to this organization."))
      } else {
        ProgressView("Loading booking…")
      }
    }
    .task(id: route.id) { await load() }
  }

  @MainActor
  private func load() async {
    guard appState.activeOrgId == route.organizationId,
          appState.activeOrgMembership?.isActive == true,
          let service = appState.supabase else {
      unavailable = true
      return
    }
    do {
      let value = try await service.fetchFacilityBooking(id: route.sourceId, orgId: route.organizationId)
      guard value.org_id == route.organizationId else { throw HPCalendarLinkError.unavailable }
      booking = value
      facilityName = try await service.listFacilities(orgId: route.organizationId)
        .first(where: { $0.id == value.facility_id })?.name
    } catch {
      unavailable = true
    }
  }
}
