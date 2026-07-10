import SwiftUI

/// Player-facing facilities scheduling:
/// - View cage availability (approved bookings)
/// - Request a time (pending)
struct SDPlayerFacilitiesView: View {
  @EnvironmentObject private var appState: AppState

  @State private var facilities: [SDFacility] = []
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

  @State private var showRequest = false
  @State private var requestSeed: RequestSeed?

  private struct RequestSeed: Identifiable {
    let id = UUID()
    let facilityId: UUID
    let startAt: Date
    let durationMin: Int
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
            Task { await loadDay() }
          }
        )

        Text("Green = approved booking. Blue = your pending request.")
          .font(.footnote)
          .foregroundStyle(DHDTheme.textSecondary)

        DHDCard(style: .flat) {
          FacilitiesDayTimelineView(
            mode: .player(myUserId: appState.myProfile?.id ?? UUID()),
            date: selectedDate,
            facilities: facilities,
            bookings: dayBookings,
            userNameById: [:],
            onApprove: { _ in },
            onDeny: { _ in },
            onMove: { _, _, _, _ in },
            onResizeSpan: nil,
            onCancelOwnPending: { booking in
              Task { await cancelPending(booking) }
            },
            onEdit: nil,
            onCreateAt: { facilityId, startAt in
              requestSeed = RequestSeed(facilityId: facilityId, startAt: startAt, durationMin: 60)
            }
          )
        }
      }
      .padding(DHDTheme.pagePadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(maxHeight: .infinity, alignment: .topLeading)
    }
    .background(DHDTheme.pageBackground)
    .dhdToast($toastText)
    .toolbar {
      ToolbarItemGroup(placement: .automatic) {
        Button {
          showRequest = true
        } label: {
          Label("Request time", systemImage: "plus")
        }
        Button {
          Task { await reloadAll() }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
      }
    }
    .sheet(isPresented: $showRequest) {
      PlayerRequestBookingSheet(
        facilities: facilities,
        defaultDate: selectedDate,
        seed: nil,
        onCreated: {
          toastText = "Request sent"
          Task { await reloadAll() }
        }
      )
      .environmentObject(appState)
    }
    .sheet(item: $requestSeed) { seed in
      PlayerRequestBookingSheet(
        facilities: facilities,
        defaultDate: seed.startAt,
        seed: .init(facilityId: seed.facilityId, startAt: seed.startAt, durationMin: seed.durationMin),
        onCreated: {
          toastText = "Request sent"
          Task { await reloadAll() }
        }
      )
      .environmentObject(appState)
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
          Text("Request cage times for BP, bullpens, extra work, or lessons.")
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.85))
        }
        Spacer()
        if isLoading { ProgressView().tint(.white) }
      }
      .foregroundStyle(.white)
    }
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
    let myId = appState.myProfile?.id
    for b in rangeBookings {
      let iso = DateUtils.toISODate(b.start_at)
      switch b.status {
      case "approved": approved.insert(iso)
      case "pending":
        // Only show pending dots for requests created by the current user.
        if let myId, b.created_by == myId { pending.insert(iso) }
      default: denied.insert(iso)
      }
    }
    approvedISOs = approved
    pendingISOs = pending
    deniedISOs = denied
  }

  private func cancelPending(_ booking: SDFacilityBooking) async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      _ = try await supabase.updateFacilityBooking(
        id: booking.id,
        facilityId: booking.facility_id,
        status: "cancelled",
        activityType: booking.activity_type,
        startAt: booking.start_at,
        endAt: booking.end_at,
        coachId: booking.coach_id,
        approved: false,
        title: booking.title,
        notes: booking.notes,
        spanFacilityId: booking.span_facility_id,
        orgId: appState.activeOrgId
      )
      toastText = "Cancelled"
      await reloadAll()
    } catch {
      errorText = error.localizedDescription
    }
  }
}

private struct PlayerRequestBookingSheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appState: AppState

  let facilities: [SDFacility]
  let defaultDate: Date
  let seed: Seed?
  let onCreated: () -> Void

  struct Seed {
    let facilityId: UUID
    let startAt: Date
    let durationMin: Int
  }

  @State private var facilityId: UUID?
  @State private var activityType: String = "bp"
  @State private var start: Date = Date()
  @State private var durationMin: Int = 60
  @State private var notes: String = ""
  @State private var isFullCage3: Bool = false
  @State private var isSaving = false
  @State private var errorText: String?

  var body: some View {
    NavigationStack {
      Form {
        Section("When") {
          DatePicker("Start", selection: $start)
          Picker("Duration", selection: $durationMin) {
            ForEach([30, 45, 60, 75, 90, 120], id: \.self) { m in
              Text("\(m) min").tag(m)
            }
          }
        }
        Section("Cage + activity") {
          Picker("Cage", selection: $facilityId) {
            Text("Select…").tag(UUID?.none)
            ForEach(selectableFacilities) { f in
              Text(f.name).tag(UUID?.some(f.id))
            }
          }
          if facilityId == cage3_1Id {
            Toggle("Full Cage 3 (3.1 + 3.2)", isOn: $isFullCage3)
          }
          Picker("Activity", selection: $activityType) {
            Text("BP").tag("bp")
            Text("Bullpen").tag("bullpen")
            Text("Extra work").tag("extra_work")
            Text("Lesson").tag("lesson")
            Text("Other").tag("other")
          }
        }
        Section("Notes") {
          TextField("Notes (optional)", text: $notes, axis: .vertical)
        }
      }
      .navigationTitle("Request time")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            Task { await save() }
          } label: {
            if isSaving { ProgressView() } else { Text("Request") }
          }
          .disabled(isSaving || facilityId == nil)
        }
      }
      .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
        Button("OK", role: .cancel) {}
      } message: { Text(errorText ?? "") }
      .task {
        facilityId = seed?.facilityId ?? facilities.first?.id
        if let seed {
          start = seed.startAt
          durationMin = seed.durationMin
        } else {
          let base = DateUtils.startOfDayET(defaultDate)
          start = DateUtils.calendarET.date(byAdding: .hour, value: 16, to: base) ?? base
        }
      }
      .onChange(of: facilityId) { _, newValue in
        if newValue != cage3_1Id {
          isFullCage3 = false
        }
      }
    }
  }

  private var cage3_1Id: UUID? { facilities.first(where: { $0.name == "Cage 3.1" })?.id }
  private var cage3_2Id: UUID? { facilities.first(where: { $0.name == "Cage 3.2" })?.id }
  private var selectableFacilities: [SDFacility] {
    facilities.filter { $0.name != "Cage 3.2" }
  }

  private func save() async {
    guard let supabase = appState.supabase else { return }
    guard let facilityId else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      let session = try await supabase.client.auth.session
      let uid = session.user.id
      let end = start.addingTimeInterval(Double(durationMin) * 60)
      let spanId: UUID? = (facilityId == cage3_1Id && isFullCage3) ? cage3_2Id : nil
      _ = try await supabase.createFacilityBooking(
        facilityId: facilityId,
        playerId: uid,
        isBlock: false,
        status: "pending",
        activityType: activityType,
        startAt: start,
        endAt: end,
        coachId: nil,
        title: nil,
        notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
        spanFacilityId: spanId,
        orgId: appState.activeOrgId
      )
      onCreated()
      dismiss()
    } catch {
      errorText = error.localizedDescription
    }
  }
}
