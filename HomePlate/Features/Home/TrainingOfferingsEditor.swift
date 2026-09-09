import SwiftUI

/// Editing one trainer never drops another offering's prices or location scope.
struct HPTrainingOfferingsEditor: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  let workspace: HPTrainingWorkspace
  let trainer: HPTrainingWorkspace.Trainer
  let onSaved: () async -> Void
  @State private var drafts: [HPTrainingOfferingDraft]
  @State private var busy = false
  @State private var errorText: String?
  @State private var editContext: String?
  @State private var uncertain = false

  init(workspace: HPTrainingWorkspace, trainer: HPTrainingWorkspace.Trainer, onSaved: @escaping () async -> Void) {
    self.workspace = workspace; self.trainer = trainer; self.onSaved = onSaved
    _drafts = State(initialValue: workspace.services.filter { $0.active == true }.map { service in
      HPTrainingOfferingDraft(service: service, existing: workspace.trainer_offerings?.first { $0.trainer_directory_id == trainer.id && $0.service_id == service.id && $0.active })
    })
  }

  var body: some View {
    NavigationStack {
      Form {
        Text("Choose this trainer’s services. Blank overrides inherit service defaults. Saving replaces this trainer’s offering list atomically.")
        ForEach($drafts) { $draft in
          Section(draft.name) {
            Toggle("Offered by this trainer", isOn: $draft.enabled)
            if draft.enabled {
              TextField("Description override", text: $draft.description, axis: .vertical)
              TextField("Duration override (minutes)", text: $draft.duration)
              TextField("Capacity override", text: $draft.capacity)
              TextField("Public price override (cents)", text: $draft.publicPrice)
              TextField("Member price override (cents)", text: $draft.memberPrice)
              Picker("Booking mode", selection: $draft.bookingMode) {
                Text("Use service default").tag("")
                ForEach(["disabled", "inquiry", "free", "paid", "package_credit"], id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
              }
              Toggle("Publicly visible", isOn: $draft.publicVisible)
              ForEach(workspace.locations ?? []) { location in
                Toggle(location.name, isOn: Binding(get: { draft.locations.contains(location.id) }, set: { selected in
                  if selected { draft.locations.insert(location.id) } else { draft.locations.remove(location.id) }
                }))
              }
              ForEach(workspace.resources ?? []) { resource in
                Toggle(resource.name, isOn: Binding(get: { draft.resources.contains(resource.id) }, set: { selected in
                  if selected { draft.resources.insert(resource.id) } else { draft.resources.remove(resource.id) }
                }))
              }
            }
          }
        }
        if let errorText { Text(errorText).foregroundStyle(.red) }
        if uncertain { Button("Refresh catalog and close") { Task { await onSaved() } } }
      }
      .disabled(busy)
      .navigationTitle(trainer.display_name)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
        ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(busy || uncertain) }
      }
      .interactiveDismissDisabled(busy)
      .onAppear { if editContext == nil { editContext = context } }
    }
  }

  private var context: String { "\(appState.myProfile?.id.uuidString ?? ""):\(appState.activeOrgId?.uuidString ?? "")" }
  private func save() async {
    guard editContext == context, let service = appState.supabase, let org = appState.activeOrgId else { return }
    guard drafts.filter(\.enabled).allSatisfy(\.isValid) else {
      errorText = "Use whole numbers: duration 15–480, capacity 1–500 and nonnegative prices. Blank fields inherit defaults."; return
    }
    busy = true; defer { busy = false }
    do {
      try await service.trainingAction(organizationId: org, action: "save_trainer_offerings", payload: [
        "trainer_directory_id": .string(trainer.id.uuidString),
        "offerings": .array(drafts.filter(\.enabled).map { .object($0.payload) }),
      ])
      await onSaved()
    } catch { uncertain = true; errorText = "Could not confirm the offering update. Refresh the catalog before retrying." }
  }
}

struct HPTrainingOfferingDraft: Identifiable {
  let id: UUID
  let name: String
  var enabled: Bool
  var description: String
  var duration: String
  var capacity: String
  var publicPrice: String
  var memberPrice: String
  var bookingMode: String
  var publicVisible: Bool
  var locations: Set<UUID>
  var resources: Set<UUID>
  var sortOrder: Int

  init(service: HPTrainingWorkspace.Service, existing: HPTrainingWorkspace.Offering?) {
    id = service.id; name = service.name; enabled = existing != nil
    description = existing?.description_override ?? ""
    duration = existing?.duration_minutes_override.map(String.init) ?? ""
    capacity = existing?.capacity_override.map(String.init) ?? ""
    publicPrice = existing?.public_price_cents.map(String.init) ?? ""
    memberPrice = existing?.member_price_cents.map(String.init) ?? ""
    bookingMode = existing?.booking_mode_override ?? ""
    publicVisible = existing?.public_visible ?? false
    locations = Set(existing?.location_ids ?? []); resources = Set(existing?.resource_ids ?? [])
    sortOrder = existing?.sort_order ?? 0
  }
  var isValid: Bool {
    [(duration, 15...480), (capacity, 1...500), (publicPrice, 0...Int(Int32.max)), (memberPrice, 0...Int(Int32.max))]
      .allSatisfy { value, bounds in value.isEmpty || Int(value).map(bounds.contains) == true }
  }
  var payload: [String: SDJSONValue] {
    ["service_id": .string(id.uuidString), "description_override": .string(description),
     "duration_minutes_override": Int(duration).map(SDJSONValue.int) ?? .null,
     "capacity_override": Int(capacity).map(SDJSONValue.int) ?? .null,
     "public_price_cents": Int(publicPrice).map(SDJSONValue.int) ?? .null,
     "member_price_cents": Int(memberPrice).map(SDJSONValue.int) ?? .null,
     "booking_mode_override": bookingMode.isEmpty ? .null : .string(bookingMode),
     "public_visible": .bool(publicVisible), "sort_order": .int(sortOrder),
     "location_ids": .array(locations.sorted { $0.uuidString < $1.uuidString }.map { .string($0.uuidString) }),
     "resource_ids": .array(resources.sorted { $0.uuidString < $1.uuidString }.map { .string($0.uuidString) })]
  }
}
