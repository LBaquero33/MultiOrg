import SwiftUI

/// Coach creates bookings or blocks for facilities scheduling.
struct NewFacilityBookingSheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appState: AppState

  let facilities: [SDFacility]
  let playerOptions: [Profile]
  let defaultDate: Date
  let seed: Seed?
  let onCreated: () -> Void

  struct Seed: Identifiable {
    let id = UUID()
    let facilityId: UUID
    let startAt: Date
    let durationMin: Int
  }

  @State private var facilityId: UUID?
  @State private var isBlock: Bool = false
  @State private var playerSearch: String = ""
  @State private var playerId: UUID?
  @State private var status: String = "approved"
  @State private var activityType: String = "lesson"
  @State private var start: Date = Date()
  @State private var durationMin: Int = 60
  @State private var notes: String = ""
  @State private var isFullCage3: Bool = false
  @State private var isSaving = false
  @State private var errorText: String?

  var body: some View {
    NavigationStack {
      HPFormScreenLayout { _ in
        HPWorkspaceHeader(
          "New booking",
          orgLabel: activeOrganizationName,
          context: isBlock ? "Facility block" : "Player reservation"
        )
      } sections: { _ in
        whenSection
        resourceSection
        notesSection
      } primaryAction: { context in
        HPButton(
          title: "Create booking",
          systemImage: "calendar.badge.plus",
          variant: .primary,
          size: .lg,
          isLoading: isSaving,
          fullWidth: context.isAccessibilitySize,
          action: { Task { await save() } }
        )
        .disabled(isSaving || facilityId == nil || (!isBlock && playerId == nil))
      } secondaryAction: { context in
        HPButton(
          title: "Cancel",
          variant: .secondary,
          size: .lg,
          fullWidth: context.isAccessibilitySize,
          action: { dismiss() }
        )
      }
      .navigationTitle("New booking")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            #if os(macOS)
            .keyboardShortcut(.cancelAction)
            #endif
        }
      }
      .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
        Button("OK", role: .cancel) {}
      } message: { Text(errorText ?? "") }
      .task {
        facilityId = seed?.facilityId ?? facilities.first?.id
        playerId = playerOptions.first?.id
        if let seed {
          start = seed.startAt
          durationMin = seed.durationMin
        } else {
          // Default start = selected date at 4pm ET.
          let base = DateUtils.startOfDayET(defaultDate)
          start = DateUtils.calendarET.date(byAdding: .hour, value: 16, to: base) ?? base
        }
      }
      .onChange(of: facilityId) { _, newValue in
        // Only Cage 3.1 supports half/full toggling.
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

  private var whenSection: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("When")
        DatePicker("Start", selection: $start)
          .frame(minHeight: 44)
          .contentShape(Rectangle())
        Divider().overlay(HP.Color.border)
        Picker("Duration", selection: $durationMin) {
          ForEach([30, 45, 60, 75, 90, 120], id: \.self) { m in
            Text("\(m) min").tag(m)
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

  private var resourceSection: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("Resource")
        Picker("Cage", selection: $facilityId) {
          Text("Select…").tag(UUID?.none)
          ForEach(selectableFacilities) { f in
            Text(f.name).tag(UUID?.some(f.id))
          }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        if facilityId == cage3_1Id {
          #if os(macOS)
          Toggle("Full Cage 3 (3.1 + 3.2)", isOn: $isFullCage3)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .help("Half cage uses Cage 3.1 only. Full cage occupies both Cage 3.1 and Cage 3.2.")
          #else
          Toggle("Full Cage 3 (3.1 + 3.2)", isOn: $isFullCage3)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
          #endif
        }
        Toggle("Block cage (unavailable)", isOn: $isBlock)
          .frame(minHeight: 44)
          .contentShape(Rectangle())
        if !isBlock {
          HPFormField(
            label: "Player search",
            text: $playerSearch,
            placeholder: "Search by name or short ID"
          )
          Picker("Player", selection: $playerId) {
            Text("Select…").tag(UUID?.none)
            ForEach(filteredPlayers) { p in
              Text(p.displayName).tag(UUID?.some(p.id))
            }
          }
          .frame(minHeight: 44)
          .contentShape(Rectangle())
        }
        Picker("Status", selection: $status) {
          Text("Approved").tag("approved")
          Text("Pending").tag("pending")
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        Picker("Activity", selection: $activityType) {
          Text("Lesson").tag("lesson")
          Text("BP").tag("bp")
          Text("Bullpen").tag("bullpen")
          Text("Extra work").tag("extra_work")
          Text("Other").tag("other")
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .font(HP.Font.callout)
      .foregroundStyle(HP.Color.text)
      .tint(HP.Color.accent)
    }
  }

  private var notesSection: some View {
    HPCard {
      HPFormField(
        label: "Notes (optional)",
        text: $notes,
        kind: .multiline,
        placeholder: "Booking notes"
      )
    }
  }

  private var filteredPlayers: [Profile] {
    let q = playerSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if q.isEmpty { return Array(playerOptions.prefix(50)) }
    let matches = playerOptions.filter { $0.displayName.lowercased().contains(q) || $0.shortId.lowercased().contains(q) }
    return Array(matches.prefix(50))
  }

  private var cage3_1Id: UUID? { facilities.first(where: { $0.name == "Cage 3.1" })?.id }
  private var cage3_2Id: UUID? { facilities.first(where: { $0.name == "Cage 3.2" })?.id }

  private var selectableFacilities: [SDFacility] {
    // Cage 3.2 is the secondary half and is used automatically for full Cage 3 bookings.
    // Allow selecting it only for coach blocks.
    if isBlock { return facilities }
    return facilities.filter { $0.name != "Cage 3.2" }
  }

  private func save() async {
    guard let supabase = appState.supabase else { return }
    guard let facilityId else { return }
    if !isBlock, playerId == nil { return }
    isSaving = true
    defer { isSaving = false }
    do {
      let end = start.addingTimeInterval(Double(durationMin) * 60)
      let spanId: UUID? = (facilityId == cage3_1Id && isFullCage3) ? cage3_2Id : nil
      _ = try await supabase.createFacilityBooking(
        facilityId: facilityId,
        playerId: isBlock ? nil : playerId,
        isBlock: isBlock,
        status: isBlock ? "approved" : status,
        activityType: activityType,
        startAt: start,
        endAt: end,
        coachId: nil,
        title: isBlock ? "Blocked" : nil,
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
