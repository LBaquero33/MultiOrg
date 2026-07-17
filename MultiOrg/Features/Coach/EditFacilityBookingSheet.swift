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
      HPFormScreenLayout { _ in
        HPWorkspaceHeader(
          "Edit booking",
          orgLabel: activeOrganizationName,
          context: "Update reservation details"
        )
      } sections: { context in
        whenSection(context)
        resourceSection
        detailsSection
      } primaryAction: { context in
        HPButton(
          title: "Save changes",
          systemImage: "checkmark",
          variant: .primary,
          size: .lg,
          isLoading: isSaving,
          fullWidth: context.isAccessibilitySize,
          action: { Task { await save() } }
        )
        .disabled(isSaving || endAt <= startAt)
      } secondaryAction: { context in
        HPButton(
          title: "Close",
          variant: .secondary,
          size: .lg,
          fullWidth: context.isAccessibilitySize,
          action: { dismiss() }
        )
      }
      .navigationTitle("Edit booking")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { dismiss() }
            #if os(macOS)
            .keyboardShortcut(.cancelAction)
            #endif
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

  private var activeOrganizationName: String {
    if let organizationId = appState.activeOrgId,
       let organization = appState.availableOrganizations.first(where: { $0.id == organizationId }) {
      return organization.displayName
    }
    return appState.activeOrgSettings?.display_name
      ?? appState.activeOrgSettings?.short_name
      ?? "Home Plate"
  }

  private func whenSection(_ context: HPScreenLayoutContext) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("When")
        DatePicker("Start", selection: $startAt)
          .frame(minHeight: 44)
          .contentShape(Rectangle())
        DatePicker("End", selection: $endAt)
          .frame(minHeight: 44)
          .contentShape(Rectangle())
        if endAt <= startAt {
          Text("End must be after start.")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.danger)
            .fixedSize(horizontal: false, vertical: true)
        }
        Divider().overlay(HP.Color.border)
        nudgeControls(stacked: context.isAccessibilitySize || !context.isRegularWidth)
      }
      .font(HP.Font.callout)
      .foregroundStyle(HP.Color.text)
      .tint(HP.Color.accent)
    }
  }

  @ViewBuilder
  private func nudgeControls(stacked: Bool) -> some View {
    if stacked {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        nudgeLabel
        nudgeButton("-60m", minutes: -60, fullWidth: true)
        nudgeButton("-15m", minutes: -15, fullWidth: true)
        nudgeButton("+15m", minutes: 15, fullWidth: true)
        nudgeButton("+60m", minutes: 60, fullWidth: true)
      }
    } else {
      HStack(spacing: HP.Space.sm) {
        nudgeLabel
        Spacer(minLength: 0)
        nudgeButton("-60m", minutes: -60)
        nudgeButton("-15m", minutes: -15)
        nudgeButton("+15m", minutes: 15)
        nudgeButton("+60m", minutes: 60)
      }
    }
  }

  private var nudgeLabel: some View {
    Text("Nudge")
      .font(HP.Font.callout)
      .foregroundStyle(HP.Color.textMuted)
  }

  private func nudgeButton(_ label: String, minutes: Int, fullWidth: Bool = false) -> some View {
    HPButton(
      title: label,
      variant: .secondary,
      size: .sm,
      fullWidth: fullWidth,
      action: { nudge(minutes: minutes) }
    )
  }

  private var resourceSection: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("Resource")
        Picker("Cage", selection: $facilityId) {
          ForEach(selectableFacilities) { f in
            Text(f.name).tag(f.id)
          }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        if facilityId == cage3_1Id {
          Toggle("Full Cage 3 (3.1 + 3.2)", isOn: $isFullCage3)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        if let onBeginMove {
          HPButton(
            title: "Move by tapping schedule…",
            systemImage: "hand.tap",
            variant: .secondary,
            size: .md,
            fullWidth: true,
            action: {
              onBeginMove()
              dismiss()
            }
          )
        }
        Picker("Status", selection: $status) {
          Text("Pending").tag("pending")
          Text("Approved").tag("approved")
          Text("Denied").tag("denied")
          Text("Cancelled").tag("cancelled")
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        Picker("Activity", selection: $activityType) {
          Text("BP").tag("bp")
          Text("Bullpen").tag("bullpen")
          Text("Extra work").tag("extra_work")
          Text("Lesson").tag("lesson")
          Text("Other").tag("other")
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        Picker("Coach", selection: Binding(get: { coachId }, set: { coachId = $0 })) {
          Text("N/A").tag(UUID?.none)
          ForEach(coachOptions) { c in
            Text(c.displayName).tag(UUID?.some(c.id))
          }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .font(HP.Font.callout)
      .foregroundStyle(HP.Color.text)
      .tint(HP.Color.accent)
    }
  }

  private var detailsSection: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("Details")
        HPFormField(label: "Title (optional)", text: $title, placeholder: "Booking title")
        HPFormField(
          label: "Notes (optional)",
          text: $notes,
          kind: .multiline,
          placeholder: "Booking notes"
        )
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
