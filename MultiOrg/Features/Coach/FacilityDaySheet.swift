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
      HPDetailScreenLayout {
        HPWorkspaceHeader(
          title,
          context: DateUtils.toISODate(date)
        )
      } metrics: {
        HPMetricCard(
          title: "Facilities",
          value: "\(facilities.count)",
          context: "Available spaces"
        )
        HPMetricCard(
          title: "Bookings",
          value: "\(bookings.count)",
          context: "Scheduled today"
        )
        HPMetricCard(
          title: "Pending",
          value: "\(pendingRequests.count)",
          context: "Awaiting review"
        )
      } details: {
        VStack(alignment: .leading, spacing: HP.Space.md) {
          HPCard {
            HStack(alignment: .top, spacing: HP.Space.sm) {
              Image(systemName: "calendar.badge.clock")
                .foregroundStyle(HP.Color.accent)
                .accessibilityHidden(true)
              Text(
                "Approve pending requests below. Tap an empty time slot to add a booking or block."
              )
              .font(HP.Font.callout)
              .foregroundStyle(HP.Color.textMuted)
              .fixedSize(horizontal: false, vertical: true)
              Spacer(minLength: 0)
              if isLoading {
                HPProgressIndicator(style: .spinner)
                  .accessibilityLabel("Loading facility schedule")
              }
            }
          }

          modeCard

          if !pendingRequests.isEmpty {
            pendingRequestsCard
          }
        }
      } related: { _ in
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Day timeline")
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
                createSeed = .init(
                  facilityId: facilityId,
                  startAt: startAt,
                  durationMin: 60
                )
              }
            )
          }
        }
      } primaryAction: {
        EmptyView()
      }
      .navigationTitle(title)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { onClose() }
            #if os(macOS)
              .keyboardShortcut(.cancelAction)
            #endif
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

  @ViewBuilder private var modeCard: some View {
    if movingBooking != nil {
      HPCard(style: .flat) {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: HP.Space.sm) {
            modeLabel(
              systemImage: "hand.tap",
              text: "Move mode: tap a destination time slot to move this booking."
            )
            Spacer(minLength: HP.Space.sm)
            HPButton(title: "Cancel", variant: .secondary, size: .sm) {
              movingBooking = nil
            }
          }
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            modeLabel(
              systemImage: "hand.tap",
              text: "Move mode: tap a destination time slot to move this booking."
            )
            HPButton(title: "Cancel", variant: .secondary, size: .sm, fullWidth: true) {
              movingBooking = nil
            }
          }
        }
      }
    } else if isRearrangeMode {
      HPCard(style: .flat) {
        modeLabel(
          systemImage: "arrow.up.and.down.and.arrow.left.and.right",
          text: "Rearrange mode: drag bookings to move. Tap Done when finished."
        )
      }
    }
  }

  private func modeLabel(systemImage: String, text: String) -> some View {
    HStack(alignment: .top, spacing: HP.Space.sm) {
      Image(systemName: systemImage)
        .foregroundStyle(HP.Color.accent)
        .accessibilityHidden(true)
      Text(text)
        .font(HP.Font.callout)
        .foregroundStyle(HP.Color.text)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var pendingRequestsCard: some View {
    HPCard(style: .flat) {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Pending requests") {
          HPStatusBadge(text: "\(pendingRequests.count)", kind: .warning)
        }
        ForEach(Array(pendingRequests.enumerated()), id: \.element.id) { index, booking in
          ViewThatFits(in: .horizontal) {
            HStack(spacing: HP.Space.sm) {
              pendingRequestIdentity(booking)
              Spacer(minLength: HP.Space.sm)
              pendingRequestActions(booking)
            }
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              pendingRequestIdentity(booking)
              pendingRequestActions(booking)
            }
          }
          if index < pendingRequests.count - 1 {
            Divider().overlay(HP.Color.border.opacity(0.5))
          }
        }
      }
    }
  }

  private func pendingRequestIdentity(_ booking: SDFacilityBooking) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(playerName(for: booking))
        .font(HP.Font.headline)
        .foregroundStyle(HP.Color.text)
      Text(booking.start_at.formatted(date: .omitted, time: .shortened))
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
    }
  }

  @ViewBuilder private func pendingRequestActions(_ booking: SDFacilityBooking) -> some View {
    if bookingActionsInFlight.contains(booking.id) {
      HPProgressIndicator(style: .spinner)
        .accessibilityLabel("Updating booking request")
    } else {
      HStack(spacing: HP.Space.xs) {
        HPButton(title: "Deny", variant: .destructive, size: .sm) {
          onDeny(booking)
        }
        HPButton(title: "Approve", variant: .secondary, size: .sm) {
          onApprove(booking)
        }
      }
    }
  }

  private var pendingRequests: [SDFacilityBooking] {
    bookings
      .filter { $0.status.lowercased() == "pending" && !$0.is_block }
      .sorted { $0.start_at < $1.start_at }
  }

  private func playerName(for booking: SDFacilityBooking) -> String {
    guard let playerId = booking.player_id else { return "Player request" }
    return userNameById[playerId] ?? "Player request"
  }
}
