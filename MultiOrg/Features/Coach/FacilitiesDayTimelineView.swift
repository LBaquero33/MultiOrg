import SwiftUI

/// Google-Calendar-like day view with columns per facility (cage) and draggable bookings.
///
/// Defaults:
/// - Hours shown: 6am–11pm
/// - Snap: 15 minutes
struct FacilitiesDayTimelineView: View {
  enum Mode: Equatable {
    case coach
    case player(myUserId: UUID)
  }

  let mode: Mode
  let date: Date
  let facilities: [SDFacility]
  let bookings: [SDFacilityBooking]
  let userNameById: [UUID: String]

  /// When true (coach-only), booking blocks can be dragged to move between cages/times.
  /// On iPhone this should normally be false so scrolling/panning wins everywhere.
  var allowDragToMove: Bool = false

  let onApprove: (SDFacilityBooking) -> Void
  let onDeny: (SDFacilityBooking) -> Void
  let onMove: (SDFacilityBooking, UUID, Date, Date) -> Void
  let onResizeSpan: ((SDFacilityBooking, UUID?) -> Void)?
  let onCancelOwnPending: ((SDFacilityBooking) -> Void)?
  let onEdit: ((SDFacilityBooking) -> Void)?
  let onCreateAt: ((UUID, Date) -> Void)?

  private let startHour = 6
  private let endHour = 23
  private let slotMinutes = 15

  @State private var dragging: DragState?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Day schedule")
          .font(.headline)
          .foregroundStyle(DHDTheme.textPrimary)
        Spacer()
        Text(DateUtils.toISODate(date))
          .font(.caption)
          .foregroundStyle(DHDTheme.textSecondary)
      }

      GeometryReader { geo in
        let headerH = timelineHeaderHeight
        let labelW: CGFloat = 54
        let colGap: CGFloat = 10
        // Keep a stable px/min so drag math is consistent on small iPhones and
        // when the sheet is resized. The outer screen owns vertical scrolling.
        let pxPerMin = timelinePointsPerMinute
        let contentH = timelineContentHeight
        let colW = max(180, (geo.size.width - labelW - colGap * CGFloat(max(0, facilities.count - 1))) / CGFloat(max(1, facilities.count)))

        ScrollView(.horizontal, showsIndicators: true) {
          VStack(spacing: 0) {
            // Facility headers
            HStack(spacing: colGap) {
              Text("Time")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DHDTheme.textSecondary)
                .frame(width: labelW, alignment: .leading)
              ForEach(facilities) { f in
                Text(f.name)
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(DHDTheme.textSecondary)
                  .frame(width: colW, alignment: .leading)
              }
            }
            .frame(height: headerH)

            HStack(alignment: .top, spacing: colGap) {
              timeLabels(height: contentH, pxPerMin: pxPerMin)
                .frame(width: labelW, height: contentH, alignment: .topLeading)

              ForEach(facilities) { facility in
                ZStack(alignment: .topLeading) {
                  gridBackground(height: contentH, pxPerMin: pxPerMin)
                    .contentShape(Rectangle())
                    .gesture(createTapGesture(facilityId: facility.id, pxPerMin: pxPerMin))

                  ForEach(bookingsForFacility(facility.id)) { b in
                    let siblingSpanId = siblingFacilityIdForFullCage(primaryFacilityId: facility.id)
                    let block = BookingBlockView(
                      mode: mode,
                      booking: b,
                      userNameById: userNameById,
                      date: date,
                      startHour: startHour,
                      pxPerMin: pxPerMin,
                      isSecondaryColumn: facility.id == b.span_facility_id,
                      allowResize: mode == .coach && isResizableInFacilityColumn(booking: b, facilityId: facility.id),
                      siblingSpanFacilityId: siblingSpanId,
                      onResizeSpan: { newSpan in
                        onResizeSpan?(b, newSpan)
                      }
                    )
                      .offset(y: yOffset(for: currentBooking(b).start_at, pxPerMin: pxPerMin))
                      .frame(height: blockHeight(for: currentBooking(b), pxPerMin: pxPerMin))

                    if mode == .coach {
                      Group {
                        if allowDragToMove && isDraggableInFacilityColumn(booking: b, facilityId: facility.id) {
                          block.gesture(dragGesture(for: b, facilityId: facility.id, colW: colW, pxPerMin: pxPerMin))
                        } else {
                          block
                        }
                      }
                      // iOS coach UX: tap to edit; drag to move. (A drag won't trigger the tap.)
                      .contentShape(Rectangle())
                      .onTapGesture { onEdit?(b) }
                      .contextMenu {
                        Button("Edit…") { onEdit?(b) }
                        Button("Approve") { onApprove(b) }.disabled(b.status == "approved")
                        Button("Deny", role: .destructive) { onDeny(b) }.disabled(b.status == "denied")
                        if isResizableInFacilityColumn(booking: b, facilityId: facility.id) {
                          Divider()
                          Button(b.span_facility_id == nil ? "Make full cage" : "Make half cage") {
                            let newSpan = (b.span_facility_id == nil) ? siblingFacilityIdForFullCage(primaryFacilityId: facility.id) : nil
                            onResizeSpan?(b, newSpan)
                          }
                        }
                      }
                    } else {
                      block
                        .contextMenu {
                          // "Own pending" is determined by who created the booking (supports parent booking on behalf).
                          if case .player(let myUserId) = mode, b.created_by == myUserId, b.status == "pending" {
                            Button("Cancel request", role: .destructive) { onCancelOwnPending?(b) }
                          }
                        }
                    }
                  }
                }
                .frame(width: colW, height: contentH, alignment: .topLeading)
                .overlay(
                  RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(DHDTheme.separator.opacity(0.25), lineWidth: 1)
                )
              }
            }
            .frame(height: contentH)
          }
          .frame(
            width: labelW + (colW * CGFloat(max(1, facilities.count))) + (colGap * CGFloat(max(0, facilities.count - 1))),
            height: headerH + contentH,
            alignment: .topLeading
          )
        }
      }
      .frame(height: timelineHeaderHeight + timelineContentHeight)
    }
  }

  private var timelineHeaderHeight: CGFloat { 28 }
  private var timelinePointsPerMinute: CGFloat { 1.2 }
  private var timelineContentHeight: CGFloat {
    CGFloat((endHour - startHour) * 60) * timelinePointsPerMinute
  }

  private func bookingsForFacility(_ facilityId: UUID) -> [SDFacilityBooking] {
    bookings.filter { $0.facility_id == facilityId || $0.span_facility_id == facilityId }
  }

  private func isDraggableInFacilityColumn(booking: SDFacilityBooking, facilityId: UUID) -> Bool {
    // Only allow drag in the primary column. Secondary (span) column is view-only.
    booking.facility_id == facilityId
  }

  private func isResizableInFacilityColumn(booking: SDFacilityBooking, facilityId: UUID) -> Bool {
    // Only allow resize in the primary column and only for Cage 3.1 (full cage spans to Cage 3.2).
    guard booking.facility_id == facilityId else { return false }
    guard let name = facilities.first(where: { $0.id == facilityId })?.name else { return false }
    return name == "Cage 3.1"
  }

  private func siblingFacilityIdForFullCage(primaryFacilityId: UUID) -> UUID? {
    // For Cage 3.1, span should be Cage 3.2 (if present).
    guard let name = facilities.first(where: { $0.id == primaryFacilityId })?.name, name == "Cage 3.1" else { return nil }
    return facilities.first(where: { $0.name == "Cage 3.2" })?.id
  }

  private func currentBooking(_ b: SDFacilityBooking) -> SDFacilityBooking {
    if let dragging, dragging.id == b.id { return dragging.preview }
    return b
  }

  private func yOffset(for startAt: Date, pxPerMin: CGFloat) -> CGFloat {
    let base = DateUtils.startOfDayET(date)
    let start = DateUtils.calendarET.date(byAdding: .hour, value: startHour, to: base) ?? base
    let delta = max(0, startAt.timeIntervalSince(start) / 60.0)
    return CGFloat(delta) * pxPerMin
  }

  private func blockHeight(for booking: SDFacilityBooking, pxPerMin: CGFloat) -> CGFloat {
    let mins = max(15, booking.end_at.timeIntervalSince(booking.start_at) / 60.0)
    return CGFloat(mins) * pxPerMin
  }

  private func snapMinutes(_ minutes: Int) -> Int {
    let s = slotMinutes
    return Int(round(Double(minutes) / Double(s))) * s
  }

  private func dragGesture(for booking: SDFacilityBooking, facilityId: UUID, colW: CGFloat, pxPerMin: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 2)
      .onChanged { value in
        let base = DateUtils.startOfDayET(date)
        let startOfWindow = DateUtils.calendarET.date(byAdding: .hour, value: startHour, to: base) ?? base

        // Convert y translation to minutes.
        let deltaMinRaw = Int((value.translation.height / pxPerMin).rounded())
        let deltaMin = snapMinutes(deltaMinRaw)

        let durSec = booking.end_at.timeIntervalSince(booking.start_at)
        let newStart = booking.start_at.addingTimeInterval(TimeInterval(deltaMin) * 60)
        let newEnd = newStart.addingTimeInterval(durSec)

        // Clamp to window.
        let windowEnd = DateUtils.calendarET.date(byAdding: .hour, value: endHour, to: base) ?? base.addingTimeInterval(3600 * 24)
        let clampedStart = max(newStart, startOfWindow)
        let clampedEnd = min(newEnd, windowEnd)
        let finalStart = clampedEnd <= clampedStart ? clampedStart : clampedStart
        let finalEnd = clampedEnd <= clampedStart ? clampedStart.addingTimeInterval(durSec) : clampedEnd

        // Column switching: if dragged far enough horizontally, move to adjacent cage.
        let colShift = Int((value.translation.width / (colW + 10)).rounded())
        let newFacilityIndex = max(0, min(facilities.count - 1, (facilityIndex(facilityId) + colShift)))
        let newFacilityId: UUID = facilities.indices.contains(newFacilityIndex) ? facilities[newFacilityIndex].id : facilityId

        // If a booking spans two cages (full Cage 3), and the coach drags it to a different cage,
        // we drop the span to avoid "phantom" occupancy in another column.
        let shouldKeepSpan = (newFacilityId == booking.facility_id)
        let newSpan: UUID? = shouldKeepSpan ? booking.span_facility_id : nil

        let preview = SDFacilityBooking(
          id: booking.id,
          org_id: booking.org_id,
          facility_id: newFacilityId,
          span_facility_id: newSpan,
          player_id: booking.player_id,
          created_by: booking.created_by,
          is_block: booking.is_block,
          status: booking.status,
          activity_type: booking.activity_type,
          start_at: finalStart,
          end_at: finalEnd,
          coach_id: booking.coach_id,
          approved_by: booking.approved_by,
          approved_at: booking.approved_at,
          title: booking.title,
          notes: booking.notes,
          created_at: booking.created_at,
          updated_at: booking.updated_at
        )

        dragging = DragState(id: booking.id, originalFacilityId: facilityId, preview: preview)
      }
      .onEnded { _ in
        guard let dragging, dragging.id == booking.id else { return }
        let b = dragging.preview
        onMove(booking, b.facility_id, b.start_at, b.end_at)
        self.dragging = nil
      }
  }

  private func createTapGesture(facilityId: UUID, pxPerMin: CGFloat) -> AnyGesture<Void> {
    func handleTap(at location: CGPoint) {
      guard onCreateAt != nil else { return }
      // Prevent creating half-cage bookings directly in Cage 3.2; it’s reserved as the "span" half.
      if facilities.first(where: { $0.id == facilityId })?.name == "Cage 3.2" {
        return
      }
      let base = DateUtils.startOfDayET(date)
      let startOfWindow = DateUtils.calendarET.date(byAdding: .hour, value: startHour, to: base) ?? base
      let minutesRaw = Int((location.y / pxPerMin).rounded())
      let minutes = snapMinutes(minutesRaw)
      let proposed = startOfWindow.addingTimeInterval(TimeInterval(minutes) * 60)
      onCreateAt?(facilityId, proposed)
    }

    #if os(iOS)
    if #available(iOS 17.0, *) {
      // Use a real tap gesture with location so scrolling/panning never fights with the "tap to add" affordance.
      let g = SpatialTapGesture()
        .onEnded { value in
          handleTap(at: value.location)
        }
      return AnyGesture(g.map { _ in () })
    }
    #endif

    // Fallback (macOS / older iOS): treat as tap only if finger barely moved, otherwise it was a scroll.
    let tapMovementThreshold: CGFloat = 14
    let g = DragGesture(minimumDistance: 0)
      .onEnded { value in
        if abs(value.translation.width) > tapMovementThreshold || abs(value.translation.height) > tapMovementThreshold {
          return
        }
        handleTap(at: value.location)
      }
    return AnyGesture(g.map { _ in () })
  }

  private func facilityIndex(_ id: UUID) -> Int {
    facilities.firstIndex(where: { $0.id == id }) ?? 0
  }

  private func timeLabels(height: CGFloat, pxPerMin: CGFloat) -> some View {
    let totalHours = endHour - startHour
    return VStack(alignment: .leading, spacing: 0) {
      ForEach(0...totalHours, id: \.self) { h in
        let hour = startHour + h
        Text(hourLabel(hour))
          .font(.caption2)
          .foregroundStyle(DHDTheme.textSecondary)
          .frame(height: CGFloat(60) * pxPerMin, alignment: .topLeading)
      }
    }
  }

  private func gridBackground(height: CGFloat, pxPerMin: CGFloat) -> some View {
    Canvas { ctx, size in
      let hourH = CGFloat(60) * pxPerMin
      let halfH = CGFloat(30) * pxPerMin
      for y in stride(from: 0, through: size.height, by: hourH) {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: y))
        p.addLine(to: CGPoint(x: size.width, y: y))
        ctx.stroke(p, with: .color(DHDTheme.separator.opacity(0.22)), lineWidth: 1)
      }
      for y in stride(from: 0, through: size.height, by: halfH) {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: y))
        p.addLine(to: CGPoint(x: size.width, y: y))
        ctx.stroke(p, with: .color(DHDTheme.separator.opacity(0.10)), lineWidth: 1)
      }
    }
    .background(DHDTheme.cardBackground.opacity(0.35))
  }

  private func hourLabel(_ hour24: Int) -> String {
    let h = hour24 % 12 == 0 ? 12 : hour24 % 12
    let ap = hour24 < 12 ? "AM" : "PM"
    return "\(h)\(ap)"
  }

  private struct DragState {
    let id: UUID
    let originalFacilityId: UUID
    let preview: SDFacilityBooking
  }
}

private struct BookingBlockView: View {
  let mode: FacilitiesDayTimelineView.Mode
  let booking: SDFacilityBooking
  let userNameById: [UUID: String]
  let date: Date
  let startHour: Int
  let pxPerMin: CGFloat
  let isSecondaryColumn: Bool
  let allowResize: Bool
  let siblingSpanFacilityId: UUID?
  let onResizeSpan: (UUID?) -> Void

  @State private var resizeDragX: CGFloat = 0

  var body: some View {
    let color = statusColor(booking.status)
    VStack(alignment: .leading, spacing: 4) {
      Text(titleText)
        .font(.caption.weight(.semibold))
        .foregroundStyle(DHDTheme.textPrimary)
        .lineLimit(1)
      Text(subtitleText)
        .font(.caption2)
        .foregroundStyle(DHDTheme.textSecondary)
        .lineLimit(1)
      if booking.status == "pending" {
        DHDStatusBadge(text: "Pending", color: .blue)
      }
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(color.opacity(isSecondaryColumn ? 0.10 : 0.22))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(isSecondaryColumn ? 0.18 : 0.35), lineWidth: 1))
    )
    .overlay(alignment: .topTrailing) {
      if booking.status == "approved" {
        Image(systemName: "checkmark.seal.fill")
          .font(.caption)
          .foregroundStyle(.green.opacity(0.9))
          .padding(6)
      }
    }
    .overlay(alignment: .trailing) {
      if allowResize && !isSecondaryColumn {
        resizeHandle
      }
    }
  }

  private var resizeHandle: some View {
    // Drag right to expand to full cage (span = Cage 3.2). Drag left to collapse to half (span = nil).
    RoundedRectangle(cornerRadius: 6)
      .fill(DHDTheme.separator.opacity(0.35))
      .frame(width: 10)
      .padding(.vertical, 6)
      .padding(.trailing, 2)
      .overlay {
        Image(systemName: "line.3.horizontal")
          .font(.caption2)
          .foregroundStyle(DHDTheme.textSecondary.opacity(0.9))
          .rotationEffect(.degrees(90))
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { v in
            resizeDragX = v.translation.width
          }
          .onEnded { _ in
            defer { resizeDragX = 0 }
            let threshold: CGFloat = 26
            // Expand
            if booking.span_facility_id == nil, resizeDragX > threshold, let siblingSpanFacilityId {
              onResizeSpan(siblingSpanFacilityId)
              return
            }
            // Collapse
            if booking.span_facility_id != nil, resizeDragX < -threshold {
              onResizeSpan(nil)
              return
            }
          }
      )
      #if os(macOS)
      .help(booking.span_facility_id == nil ? "Drag right to make full cage" : "Drag left to make half cage")
      #endif
  }

  private var titleText: String {
    // Player mode should avoid exposing other users' details.
    if booking.is_block { return "Blocked" }
    if case .player(let myUserId) = mode, booking.player_id != Optional(myUserId) {
      return "Booked"
    }
    let t = (booking.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !t.isEmpty { return t }
    return booking.activity_type.replacingOccurrences(of: "_", with: " ").capitalized
  }

  private var timeText: String {
    let f = DateFormatter()
    f.timeStyle = .short
    f.dateStyle = .none
    return "\(f.string(from: booking.start_at)) – \(f.string(from: booking.end_at))"
  }

  private var subtitleText: String {
    switch mode {
    case .coach:
      if booking.is_block { return timeText }
      if let pid = booking.player_id {
        let who = userNameById[pid] ?? "Player \(pid.uuidString.prefix(6).uppercased())"
        return "\(timeText) • \(who)"
      }
      return timeText
    case .player(let myUserId):
      if booking.player_id == Optional(myUserId) {
        return timeText
      }
      return timeText
    }
  }

  private func statusColor(_ status: String) -> Color {
    switch status {
    case "approved": return .green
    case "pending": return .blue
    case "denied": return .red
    case "cancelled": return .gray
    default: return .gray
    }
  }
}
