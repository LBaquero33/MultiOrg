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
      Form {
        Section("When") {
          DatePicker("Start", selection: $start)
          Picker("Duration", selection: $durationMin) {
            ForEach([30, 45, 60, 75, 90, 120], id: \.self) { m in
              Text("\(m) min").tag(m)
            }
          }
        }
        Section("Resource") {
          Picker("Cage", selection: $facilityId) {
            Text("Select…").tag(UUID?.none)
            ForEach(selectableFacilities) { f in
              Text(f.name).tag(UUID?.some(f.id))
            }
          }
          if facilityId == cage3_1Id {
            #if os(macOS)
            Toggle("Full Cage 3 (3.1 + 3.2)", isOn: $isFullCage3)
              .help("Half cage uses Cage 3.1 only. Full cage occupies both Cage 3.1 and Cage 3.2.")
            #else
            Toggle("Full Cage 3 (3.1 + 3.2)", isOn: $isFullCage3)
            #endif
          }
          Toggle("Block cage (unavailable)", isOn: $isBlock)
          if !isBlock {
            TextField("Player search", text: $playerSearch)
              .textFieldStyle(.roundedBorder)
            Picker("Player", selection: $playerId) {
              Text("Select…").tag(UUID?.none)
              ForEach(filteredPlayers) { p in
                Text(p.displayName).tag(UUID?.some(p.id))
              }
            }
          }
          Picker("Status", selection: $status) {
            Text("Approved").tag("approved")
            Text("Pending").tag("pending")
          }
          Picker("Activity", selection: $activityType) {
            Text("Lesson").tag("lesson")
            Text("BP").tag("bp")
            Text("Bullpen").tag("bullpen")
            Text("Extra work").tag("extra_work")
            Text("Other").tag("other")
          }
        }
        Section("Notes") {
          TextField("Notes (optional)", text: $notes, axis: .vertical)
        }
      }
      .navigationTitle("New booking")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            Task { await save() }
          } label: {
            if isSaving { ProgressView() } else { Text("Create") }
          }
          .disabled(isSaving || facilityId == nil || (!isBlock && playerId == nil))
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
