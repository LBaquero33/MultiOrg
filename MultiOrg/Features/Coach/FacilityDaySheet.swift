import SwiftUI

struct FacilityDaySheet: View {
  @EnvironmentObject private var appState: AppState

  let title: String
  let date: Date
  let facilities: [SDFacility]
  let bookings: [SDFacilityBooking]
  let userNameById: [UUID: String]
  let isLoading: Bool
  let bookingActionsInFlight: Set<UUID>

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
            Text("Approve pending requests below. Tap an empty time slot to add a booking or block.")
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

        let pendingRequests = bookings
          .filter { $0.status.lowercased() == "pending" && !$0.is_block }
          .sorted { $0.start_at < $1.start_at }
        if !pendingRequests.isEmpty {
          DHDCard(style: .flat) {
            VStack(alignment: .leading, spacing: 10) {
              DHDSectionHeader("Pending requests") {
                DHDStatusBadge(text: "\(pendingRequests.count)", color: .orange)
              }
              ForEach(Array(pendingRequests.enumerated()), id: \.element.id) { index, booking in
                HStack(spacing: 10) {
                  VStack(alignment: .leading, spacing: 2) {
                    Text(playerName(for: booking))
                      .font(.subheadline.weight(.semibold))
                    Text(booking.start_at.formatted(date: .omitted, time: .shortened))
                      .font(.caption)
                      .foregroundStyle(DHDTheme.textSecondary)
                  }
                  Spacer()
                  if bookingActionsInFlight.contains(booking.id) {
                    ProgressView().controlSize(.small)
                  } else {
                    Button("Deny", role: .destructive) { onDeny(booking) }
                      .buttonStyle(.bordered)
                    Button("Approve") { onApprove(booking) }
                      .buttonStyle(.borderedProminent)
                  }
                }
                if index < pendingRequests.count - 1 {
                  Divider().overlay(DHDTheme.separator.opacity(0.3))
                }
              }
            }
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

  private func playerName(for booking: SDFacilityBooking) -> String {
    guard let playerId = booking.player_id else { return "Player request" }
    return userNameById[playerId] ?? "Player request"
  }
}
