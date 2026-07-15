import SwiftUI

/// Coach-facing facilities scheduling (3 cages): month grid + day timeline.
struct CoachFacilitiesView: View {
  @EnvironmentObject private var appState: AppState

  @State private var facilities: [SDFacility] = []
  @State private var profileNameById: [UUID: String] = [:]
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var toastText: String?

  @State private var visibleMonth: Date = DateUtils.startOfMonthET(Date())
  @State private var selectedDate: Date = DateUtils.startOfDayET(Date())

  @State private var approvedISOs: Set<String> = []
  @State private var pendingISOs: Set<String> = []
  @State private var deniedISOs: Set<String> = []

  @State private var dayBookings: [SDFacilityBooking] = []
  @State private var rangeBookings: [SDFacilityBooking] = []

  @State private var editingBooking: SDFacilityBooking?
  @State private var movingBooking: SDFacilityBooking?
  @State private var bookingActionsInFlight = Set<UUID>()
  @State private var coachOptions: [Profile] = []
  @State private var playerOptions: [Profile] = []
  @State private var dayModal: DayModal?
  @State private var createSeed: NewFacilityBookingSheet.Seed?

  private struct DayModal: Identifiable {
    let id = UUID()
    let date: Date
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        header

        DHDMonthGridView(
          visibleMonth: $visibleMonth,
          selectedDate: $selectedDate,
          scheduledLiftISOs: approvedISOs,
          practiceISOs: pendingISOs,
          gameISOs: deniedISOs,
          isLoading: isLoading,
          onPrev: {
            visibleMonth = DateUtils.startOfMonthET(DateUtils.addMonthsET(visibleMonth, value: -1))
            Task { await reloadMonth() }
          },
          onNext: {
            visibleMonth = DateUtils.startOfMonthET(DateUtils.addMonthsET(visibleMonth, value: 1))
            Task { await reloadMonth() }
          },
          onSelect: { d in
            selectedDate = DateUtils.startOfDayET(d)
            dayModal = DayModal(date: selectedDate)
            Task { await loadDay() }
          }
        )

        pendingRequestsCard

        Text("Green = approved. Blue = pending. Red = denied/cancelled.")
          .font(.footnote)
          .foregroundStyle(DHDTheme.textSecondary)
      }
      .padding(DHDTheme.pagePadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(maxHeight: .infinity, alignment: .topLeading)
    }
    .background(DHDTheme.pageBackground)
    .dhdToast($toastText)
    .toolbar {
      ToolbarItem(placement: .automatic) {
        Button {
          Task { await reloadAll() }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
      }
    }
    #if os(macOS)
    .dhdFloatingModal(item: $dayModal, width: 980, height: 760) { modal in
      FacilityDaySheet(
        title: "Facilities",
        date: modal.date,
        facilities: facilities,
        bookings: dayBookings,
        userNameById: profileNameById,
        isLoading: isLoading,
        bookingActionsInFlight: bookingActionsInFlight,
        onClose: { dayModal = nil },
        createSeed: $createSeed,
        movingBooking: $movingBooking,
        playerOptions: playerOptions,
        onCreated: {
          toastText = "Created"
          Task { await reloadAll() }
        },
        onEdit: { b in editingBooking = b },
        onApprove: { b in Task { await setStatus(b, status: "approved") } },
        onDeny: { b in Task { await setStatus(b, status: "denied") } },
        onMove: { b, fid, s, e in Task { await moveBooking(b, facilityId: fid, startAt: s, endAt: e) } },
        onResizeSpan: { b, newSpan in Task { await resizeBookingSpan(b, spanFacilityId: newSpan) } }
      )
      .environmentObject(appState)
    }
    #else
    .sheet(item: $dayModal) { modal in
      FacilityDaySheet(
        title: "Facilities",
        date: modal.date,
        facilities: facilities,
        bookings: dayBookings,
        userNameById: profileNameById,
        isLoading: isLoading,
        bookingActionsInFlight: bookingActionsInFlight,
        onClose: { dayModal = nil },
        createSeed: $createSeed,
        movingBooking: $movingBooking,
        playerOptions: playerOptions,
        onCreated: {
          toastText = "Created"
          Task { await reloadAll() }
        },
        onEdit: { b in editingBooking = b },
        onApprove: { b in Task { await setStatus(b, status: "approved") } },
        onDeny: { b in Task { await setStatus(b, status: "denied") } },
        onMove: { b, fid, s, e in Task { await moveBooking(b, facilityId: fid, startAt: s, endAt: e) } },
        onResizeSpan: { b, newSpan in Task { await resizeBookingSpan(b, spanFacilityId: newSpan) } }
      )
      .environmentObject(appState)
      #if !os(macOS)
      .presentationDetents([.large])
      #endif
    }
    #endif
    .sheet(item: $editingBooking) { booking in
      EditFacilityBookingSheet(
        facilities: facilities,
        coachOptions: coachOptions,
        booking: booking,
        onBeginMove: {
          movingBooking = booking
          editingBooking = nil
          toastText = "Tap a time slot to move the booking"
        },
        onSaved: {
          toastText = "Saved"
          Task { await reloadAll() }
        }
      )
      .environmentObject(appState)
      #if os(macOS)
      .frame(minWidth: 640, minHeight: 620)
      #endif
    }
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .task {
      await reloadAll()
    }
  }

  private var header: some View {
    DHDHeaderCard {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Facilities")
            .font(.title3.weight(.semibold))
          Text("Schedule cages, approve requests, and drag bookings between cages.")
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.85))
        }
        Spacer()
        if isLoading { ProgressView().tint(.white) }
      }
      .foregroundStyle(.white)
    }
  }

  private var pendingRequestsCard: some View {
    let pending = rangeBookings
      .filter { $0.status.lowercased() == "pending" && !$0.is_block }
      .sorted { $0.start_at < $1.start_at }

    return DHDCard {
      VStack(alignment: .leading, spacing: 10) {
        DHDSectionHeader("Pending requests") {
          DHDStatusBadge(text: "\(pending.count)", color: pending.isEmpty ? .green : .orange)
        }

        if pending.isEmpty {
          Label("All booking requests are handled.", systemImage: "checkmark.circle.fill")
            .foregroundStyle(DHDTheme.textSecondary)
        } else {
          ForEach(Array(pending.prefix(8).enumerated()), id: \.element.id) { index, booking in
            HStack(spacing: 12) {
              VStack(alignment: .leading, spacing: 3) {
                Text(playerName(for: booking))
                  .font(.subheadline.weight(.semibold))
                Text(booking.start_at.formatted(date: .abbreviated, time: .shortened))
                  .font(.caption)
                  .foregroundStyle(DHDTheme.textSecondary)
                Text(facilities.first(where: { $0.id == booking.facility_id })?.name ?? "Facility")
                  .font(.caption)
                  .foregroundStyle(DHDTheme.textSecondary)
              }
              Spacer()
              if bookingActionsInFlight.contains(booking.id) {
                ProgressView().controlSize(.small)
              } else {
                Button("Deny", role: .destructive) {
                  Task { await setStatus(booking, status: "denied") }
                }
                .buttonStyle(.bordered)
                Button("Approve") {
                  Task { await setStatus(booking, status: "approved") }
                }
                .buttonStyle(.borderedProminent)
              }
            }
            if index < min(pending.count, 8) - 1 {
              Divider().overlay(DHDTheme.separator.opacity(0.3))
            }
          }
        }
      }
    }
  }

  private func playerName(for booking: SDFacilityBooking) -> String {
    guard let playerId = booking.player_id else { return "Player request" }
    return profileNameById[playerId] ?? "Player request"
  }

  private func reloadAll() async {
    await reloadMonth()
    await loadDay()
  }

  private func reloadMonth() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      facilities = try await supabase.listFacilities(orgId: appState.activeOrgId)
      // Load names so coach blocks can show who booked.
      let profiles = try await supabase.listPlayerProfiles()
      var map: [UUID: String] = [:]
      var coaches: [Profile] = []
      var players: [Profile] = []
      for p in profiles {
        map[p.id] = p.displayName
        if p.isCoach { coaches.append(p) }
        if p.isPlayer { players.append(p) }
      }
      profileNameById = map
      coachOptions = coaches.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
      playerOptions = players.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

      let first = DateUtils.startOfMonthET(visibleMonth)
      let end = DateUtils.addMonthsET(first, value: 1)
      rangeBookings = try await supabase.listFacilityBookings(rangeStart: first, rangeEnd: end, orgId: appState.activeOrgId)
      rebuildDots()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func loadDay() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let start = DateUtils.startOfDayET(selectedDate)
      let end = DateUtils.calendarET.date(byAdding: .day, value: 1, to: start) ?? start
      dayBookings = try await supabase.listFacilityBookings(dayStart: start, dayEnd: end, orgId: appState.activeOrgId)
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func rebuildDots() {
    var approved: Set<String> = []
    var pending: Set<String> = []
    var denied: Set<String> = []
    for b in rangeBookings {
      let iso = DateUtils.toISODate(b.start_at)
      switch b.status {
      case "approved": approved.insert(iso)
      case "pending": pending.insert(iso)
      default: denied.insert(iso)
      }
    }
    approvedISOs = approved
    pendingISOs = pending
    deniedISOs = denied
  }

  private func setStatus(_ booking: SDFacilityBooking, status: String) async {
    guard let supabase = appState.supabase else { return }
    guard !bookingActionsInFlight.contains(booking.id) else { return }
    bookingActionsInFlight.insert(booking.id)
    // Approval/denial is a status-only action. Explicitly clear any stale
    // create/edit presentation so it can never jump into a creation form.
    createSeed = nil
    editingBooking = nil
    isLoading = true
    defer {
      isLoading = false
      bookingActionsInFlight.remove(booking.id)
    }
    do {
      _ = try await supabase.updateFacilityBooking(
        id: booking.id,
        facilityId: booking.facility_id,
        status: status,
        activityType: booking.activity_type,
        startAt: booking.start_at,
        endAt: booking.end_at,
        coachId: booking.coach_id,
        approved: status == "approved",
        title: booking.title,
        notes: booking.notes,
        orgId: appState.activeOrgId
      )
      toastText = status.capitalized
      await reloadAll()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func moveBooking(_ booking: SDFacilityBooking, facilityId: UUID, startAt: Date, endAt: Date) async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      // If the booking is a full Cage 3 (spanning 3.2) and it’s moved to a different cage,
      // drop the span so it doesn’t occupy an unrelated column.
      let keepSpan = (facilityId == booking.facility_id)
      let newSpan = keepSpan ? booking.span_facility_id : nil
      _ = try await supabase.updateFacilityBooking(
        id: booking.id,
        facilityId: facilityId,
        status: booking.status,
        activityType: booking.activity_type,
        startAt: startAt,
        endAt: endAt,
        coachId: booking.coach_id,
        approved: booking.status == "approved",
        title: booking.title,
        notes: booking.notes,
        spanFacilityId: newSpan,
        orgId: appState.activeOrgId
      )
      toastText = "Moved"
      await reloadAll()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func resizeBookingSpan(_ booking: SDFacilityBooking, spanFacilityId: UUID?) async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      _ = try await supabase.updateFacilityBooking(
        id: booking.id,
        facilityId: booking.facility_id,
        status: booking.status,
        activityType: booking.activity_type,
        startAt: booking.start_at,
        endAt: booking.end_at,
        coachId: booking.coach_id,
        approved: booking.status == "approved",
        title: booking.title,
        notes: booking.notes,
        spanFacilityId: spanFacilityId,
        orgId: appState.activeOrgId
      )
      toastText = (spanFacilityId == nil) ? "Half cage" : "Full cage"
      await reloadAll()
    } catch {
      errorText = error.localizedDescription
    }
  }
}
