import SwiftUI

/// Parent-facing facilities scheduling for a specific child.
/// Parents can request times and cancel their own pending requests.
struct SDParentFacilitiesView: View {
  @EnvironmentObject private var appState: AppState
  let child: Profile

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
      ParentRequestBookingSheet(
        child: child,
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
      ParentRequestBookingSheet(
        child: child,
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
          Text("Booking for \(child.displayName)")
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

private struct ParentRequestBookingSheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appState: AppState

  let child: Profile
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
        Section("Who") {
          Text(child.displayName)
        }
        Section("When") {
          DatePicker("Start", selection: $start)
          Picker("Duration", selection: $durationMin) {
            ForEach([30, 45, 60, 75, 90, 120], id: \.self) { m in
              Text("\(m) min").tag(m)
            }
          }
        }

	        Section("Details") {
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
	          }
          TextField("Notes (optional)", text: $notes, axis: .vertical)
            .lineLimit(3...6)
        }

        if let err = errorText, !err.isEmpty {
          Text(err).foregroundStyle(.red)
        }
      }
      .navigationTitle("Request time")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            Task { await save() }
          } label: {
            if isSaving { ProgressView() } else { Text("Request") }
          }
          .disabled(isSaving || facilityId == nil)
        }
      }
	      .task {
	        facilityId = seed?.facilityId ?? facilities.first?.id
	        start = seed?.startAt ?? defaultDate
	        durationMin = seed?.durationMin ?? 60
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
	      let end = start.addingTimeInterval(TimeInterval(durationMin * 60))
	      let spanId: UUID? = (facilityId == cage3_1Id && isFullCage3) ? cage3_2Id : nil
	      _ = try await supabase.createFacilityBooking(
	        facilityId: facilityId,
	        playerId: child.id,
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
	      dismiss()
	      onCreated()
	    } catch {
	      errorText = error.localizedDescription
	    }
	  }
}
