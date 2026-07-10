import SwiftUI

struct EditFacilityBookingSheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appState: AppState

  let facilities: [SDFacility]
  let coachOptions: [Profile]
  let booking: SDFacilityBooking
  let onBeginMove: (() -> Void)?
  let onSaved: () -> Void

  @State private var facilityId: UUID
  @State private var status: String
  @State private var activityType: String
  @State private var startAt: Date
  @State private var endAt: Date
  @State private var coachId: UUID?
  @State private var title: String
  @State private var notes: String
  @State private var isFullCage3: Bool

  @State private var isSaving = false
  @State private var errorText: String?

  init(
    facilities: [SDFacility],
    coachOptions: [Profile],
    booking: SDFacilityBooking,
    onBeginMove: (() -> Void)? = nil,
    onSaved: @escaping () -> Void
  ) {
    self.facilities = facilities
    self.coachOptions = coachOptions
    self.booking = booking
    self.onBeginMove = onBeginMove
    self.onSaved = onSaved

    _facilityId = State(initialValue: booking.facility_id)
    _status = State(initialValue: booking.status)
    _activityType = State(initialValue: booking.activity_type)
    _startAt = State(initialValue: booking.start_at)
    _endAt = State(initialValue: booking.end_at)
    _coachId = State(initialValue: booking.coach_id)
    _title = State(initialValue: booking.title ?? "")
    _notes = State(initialValue: booking.notes ?? "")
    _isFullCage3 = State(initialValue: booking.span_facility_id != nil)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("When") {
          DatePicker("Start", selection: $startAt)
          DatePicker("End", selection: $endAt)

          HStack(spacing: 10) {
            Text("Nudge")
              .foregroundStyle(DHDTheme.textSecondary)
            Spacer()
            Button("-60m") { nudge(minutes: -60) }
            Button("-15m") { nudge(minutes: -15) }
            Button("+15m") { nudge(minutes: 15) }
            Button("+60m") { nudge(minutes: 60) }
          }
        }

        Section("Resource") {
          Picker("Cage", selection: $facilityId) {
            ForEach(selectableFacilities) { f in
              Text(f.name).tag(f.id)
            }
          }
          if facilityId == cage3_1Id {
            Toggle("Full Cage 3 (3.1 + 3.2)", isOn: $isFullCage3)
          }
          if let onBeginMove {
            Button {
              onBeginMove()
              dismiss()
            } label: {
              Label("Move by tapping schedule…", systemImage: "hand.tap")
            }
            .foregroundStyle(DHDTheme.accent)
          }
          Picker("Status", selection: $status) {
            Text("Pending").tag("pending")
            Text("Approved").tag("approved")
            Text("Denied").tag("denied")
            Text("Cancelled").tag("cancelled")
          }
          Picker("Activity", selection: $activityType) {
            Text("BP").tag("bp")
            Text("Bullpen").tag("bullpen")
            Text("Extra work").tag("extra_work")
            Text("Lesson").tag("lesson")
            Text("Other").tag("other")
          }
          Picker("Coach", selection: Binding(get: { coachId }, set: { coachId = $0 })) {
            Text("N/A").tag(UUID?.none)
            ForEach(coachOptions) { c in
              Text(c.displayName).tag(UUID?.some(c.id))
            }
          }
        }

        Section("Details") {
          TextField("Title (optional)", text: $title)
          TextField("Notes (optional)", text: $notes, axis: .vertical)
        }
      }
      .navigationTitle("Edit booking")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            Task { await save() }
          } label: {
            if isSaving { ProgressView() } else { Text("Save") }
          }
          .disabled(isSaving || endAt <= startAt)
        }
      }
      .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
        Button("OK", role: .cancel) {}
      } message: { Text(errorText ?? "") }
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
    // Hide Cage 3.2 from direct selection; it is used automatically for full Cage 3 bookings.
    // Keep it visible if the existing booking is already on 3.2 (defensive).
    let isOn3_2 = facilities.first(where: { $0.id == booking.facility_id })?.name == "Cage 3.2"
    return isOn3_2 ? facilities : facilities.filter { $0.name != "Cage 3.2" }
  }

  private func save() async {
    guard let supabase = appState.supabase else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      let spanId: UUID? = (facilityId == cage3_1Id && isFullCage3) ? cage3_2Id : nil
      _ = try await supabase.updateFacilityBooking(
        id: booking.id,
        facilityId: facilityId,
        status: status,
        activityType: activityType,
        startAt: startAt,
        endAt: endAt,
        coachId: coachId,
        approved: status == "approved",
        title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : title,
        notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
        spanFacilityId: spanId,
        orgId: appState.activeOrgId
      )
      onSaved()
      dismiss()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func nudge(minutes: Int) {
    let delta = TimeInterval(minutes) * 60
    startAt = startAt.addingTimeInterval(delta)
    endAt = endAt.addingTimeInterval(delta)
  }
}
