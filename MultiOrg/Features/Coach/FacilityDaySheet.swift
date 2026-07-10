import SwiftUI

struct FacilityDaySheet: View {
  @EnvironmentObject private var appState: AppState

  let title: String
  let date: Date
  let facilities: [SDFacility]
  let bookings: [SDFacilityBooking]
  let userNameById: [UUID: String]
  let isLoading: Bool

  let onClose: () -> Void
  @Binding var createSeed: NewFacilityBookingSheet.Seed?
  /// When non-nil, the coach is in "tap-to-move" mode for this booking.
  @Binding var movingBooking: SDFacilityBooking?
  let playerOptions: [Profile]
  let onCreated: () -> Void
  let onEdit: (SDFacilityBooking) -> Void
  let onApprove: (SDFacilityBooking) -> Void
  let onDeny: (SDFacilityBooking) -> Void
  let onMove: (SDFacilityBooking, UUID, Date, Date) -> Void
  let onResizeSpan: (SDFacilityBooking, UUID?) -> Void

  @State private var isRearrangeMode = false

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text(DateUtils.toISODate(date))
              .font(.title3.weight(.semibold))
              .foregroundStyle(DHDTheme.textPrimary)
            Text("Tap a time slot to add a booking/block. Tap a booking to edit. Use Rearrange to drag-move.")
              .font(.subheadline)
              .foregroundStyle(DHDTheme.textSecondary)
          }
          Spacer()
          if isLoading { ProgressView() }
        }

        if movingBooking != nil {
          DHDCard(style: .flat) {
            HStack(spacing: 10) {
              Image(systemName: "hand.tap")
                .foregroundStyle(DHDTheme.accent)
              Text("Move mode: tap a destination time slot to move this booking.")
                .font(.subheadline)
                .foregroundStyle(DHDTheme.textPrimary)
              Spacer()
              Button("Cancel") { movingBooking = nil }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 2)
          }
        } else if isRearrangeMode {
          DHDCard(style: .flat) {
            HStack(spacing: 10) {
              Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .foregroundStyle(DHDTheme.accent)
              Text("Rearrange mode: drag bookings to move. Tap Done when finished.")
                .font(.subheadline)
                .foregroundStyle(DHDTheme.textPrimary)
              Spacer()
            }
            .padding(.vertical, 2)
          }
        }

        DHDCard(style: .flat) {
          FacilitiesDayTimelineView(
            mode: .coach,
            date: date,
            facilities: facilities,
            bookings: bookings,
            userNameById: userNameById,
            allowDragToMove: isRearrangeMode,
            onApprove: onApprove,
            onDeny: onDeny,
            onMove: onMove,
            onResizeSpan: onResizeSpan,
            onCancelOwnPending: nil,
            onEdit: onEdit,
            onCreateAt: { facilityId, startAt in
              if let moving = movingBooking {
                let dur = moving.end_at.timeIntervalSince(moving.start_at)
                onMove(moving, facilityId, startAt, startAt.addingTimeInterval(dur))
                movingBooking = nil
                return
              }
              createSeed = .init(facilityId: facilityId, startAt: startAt, durationMin: 60)
            }
          )
        }
      }
      .padding(DHDTheme.pagePadding)
      .background(DHDTheme.pageBackground)
      .navigationTitle(title)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { onClose() }
        }
        #if !os(macOS)
        ToolbarItem(placement: .primaryAction) {
          Button(isRearrangeMode ? "Done" : "Rearrange") {
            if movingBooking != nil { movingBooking = nil }
            isRearrangeMode.toggle()
          }
        }
        #endif
      }
    }
    // Present "Add event" on top of the day popup.
    #if os(macOS)
    .dhdFloatingModal(item: $createSeed, width: 620, height: 560) { seed in
      NewFacilityBookingSheet(
        facilities: facilities,
        playerOptions: playerOptions,
        defaultDate: seed.startAt,
        seed: seed,
        onCreated: {
          createSeed = nil
          onCreated()
        }
      )
      .environmentObject(appState)
    }
    #else
    .sheet(item: $createSeed) { seed in
      NewFacilityBookingSheet(
        facilities: facilities,
        playerOptions: playerOptions,
        defaultDate: seed.startAt,
        seed: seed,
        onCreated: {
          createSeed = nil
          onCreated()
        }
      )
      .environmentObject(appState)
    }
    #endif
  }
}
