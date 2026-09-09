import SwiftUI

struct HPTrainingCatalogView: View {
  @EnvironmentObject private var appState: AppState
  let workspace: HPTrainingWorkspace
  let onSaved: () async -> Void
  @State private var creatingService = false
  @State private var editingService: HPTrainingWorkspace.Service?
  @State private var editingTrainer: HPTrainingWorkspace.Trainer?
  @State private var editingPackage: HPTrainingWorkspace.Package?
  @State private var creatingPackage = false

  var body: some View {
    List {
      Section("Services") {
        ForEach(workspace.services) { service in
          VStack(alignment: .leading, spacing: 6) {
            Text(service.name).font(.headline)
            if let description = service.description { Text(description) }
            Text("\(service.duration_minutes.map(String.init) ?? "—") minutes · Capacity \(service.capacity.map(String.init) ?? "—")").font(.caption)
            Text(service.active == true ? "Active" : "Inactive").font(.caption)
            if workspace.access["is_admin"]?.boolValue == true {
              Button("Edit \(service.name)") { editingService = service }
            }
          }
        }
        if workspace.access["is_admin"]?.boolValue == true {
          Button("Create service") { creatingService = true }
        }
      }
      Section("Trainers and staff") {
        ForEach(workspace.staff_directory ?? []) { trainer in
          VStack(alignment: .leading) {
            Text(trainer.display_name).font(.headline)
            Text("\(trainer.staff_kind.replacingOccurrences(of: "_", with: " ")) · \(trainer.status)").font(.caption)
            ForEach(workspace.services.filter { service in
              workspace.trainer_offerings?.contains { $0.service_id == service.id && $0.trainer_directory_id == trainer.id && $0.active } == true
            }) { Text($0.name).font(.caption) }
            if workspace.access["is_admin"]?.boolValue == true {
              Button("Manage offerings") { editingTrainer = trainer }
            }
          }
        }
      }
      Section("Packages") {
        ForEach(workspace.packages ?? []) { package in
          VStack(alignment: .leading) {
            Text(package.name).font(.headline)
            Text("\(package.credits.map(String.init) ?? "—") credits · \(package.active ? "Active" : "Inactive")")
            if let days = package.validity_days { Text("Valid for \(days) days after verified payment").font(.caption) }
            if workspace.access["is_admin"]?.boolValue == true {
              Button("Edit \(package.name)") { editingPackage = package }
            }
          }
        }
        if workspace.access["is_admin"]?.boolValue == true {
          Button("Create package") { creatingPackage = true }
        }
      }
    }
    .navigationTitle("Training catalog")
    .onChange(of: appState.activeOrgId) { _, _ in closeEditors() }
    .onChange(of: appState.myProfile?.id) { _, _ in closeEditors() }
    .sheet(isPresented: $creatingService) {
      HPCreateTrainingServiceView { await onSaved(); creatingService = false }
    }
    .sheet(item: $editingService) { service in
      HPCreateTrainingServiceView(existing: service) { await onSaved(); editingService = nil }
    }
    .sheet(item: $editingTrainer) { trainer in
      HPTrainingOfferingsEditor(workspace: workspace, trainer: trainer) { await onSaved(); editingTrainer = nil }
    }
    .sheet(isPresented: $creatingPackage) {
      HPTrainingPackageEditor { await onSaved(); creatingPackage = false }
    }
    .sheet(item: $editingPackage) { package in
      HPTrainingPackageEditor(existing: package) { await onSaved(); editingPackage = nil }
    }
  }
  private func closeEditors() {
    creatingService = false; editingService = nil; editingTrainer = nil
    creatingPackage = false; editingPackage = nil
  }
}

private struct HPCreateTrainingServiceView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  let onSaved: () async -> Void
  var existing: HPTrainingWorkspace.Service? = nil
  @State private var name = ""
  @State private var description = ""
  @State private var duration = 60
  @State private var capacity = 1
  @State private var busy = false
  @State private var errorText: String?
  @State private var bookingMode = "inquiry"
  @State private var price = ""
  @State private var verified = false
  @State private var visible = false
  @State private var active = true
  @State private var cancellationPolicy = ""
  @State private var uncertain = false
  @State private var editContext: String?
  init(existing: HPTrainingWorkspace.Service? = nil, onSaved: @escaping () async -> Void) {
    self.existing = existing; self.onSaved = onSaved
    _name = State(initialValue: existing?.name ?? "")
    _description = State(initialValue: existing?.description ?? "")
    _duration = State(initialValue: existing?.duration_minutes ?? 60)
    _capacity = State(initialValue: existing?.capacity ?? 1)
    _bookingMode = State(initialValue: existing?.public_booking_mode ?? "inquiry")
    _price = State(initialValue: existing?.price_cents.map(String.init) ?? "")
    _verified = State(initialValue: existing?.price_verification_required == false)
    _visible = State(initialValue: existing?.public_visible ?? false)
    _active = State(initialValue: existing?.active ?? true)
    _cancellationPolicy = State(initialValue: existing?.cancellation_policy ?? "")
  }
  var body: some View {
    NavigationStack {
      Form {
        TextField("Service name", text: $name)
        TextField("Description", text: $description, axis: .vertical)
        Stepper("\(duration) minutes", value: $duration, in: 15...480, step: 15)
        Stepper("Capacity: \(capacity)", value: $capacity, in: 1...500)
        Picker("Booking mode", selection: $bookingMode) {
          ForEach(["disabled", "inquiry", "free", "paid", "package_credit"], id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
        }
        TextField("Price in cents (blank if unset)", text: $price)
        Toggle("Price reviewed and verified", isOn: $verified)
        Toggle("Publicly visible", isOn: $visible)
        Toggle("Active", isOn: $active)
        TextField("Cancellation policy", text: $cancellationPolicy, axis: .vertical)
        Text("New services start as private inquiries. Assign trainers, availability and verified pricing before enabling public booking.")
        if let errorText { Text(errorText).foregroundStyle(.red) }
        if uncertain { Button("Refresh catalog and close") { Task { await onSaved() } } }
      }.navigationTitle(existing == nil ? "Create service" : "Edit service")
        .disabled(busy)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") { Task { await save() } }.disabled(busy || uncertain || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
        .interactiveDismissDisabled(busy)
        .onAppear { if editContext == nil { editContext = context } }
    }
  }
  private var context: String { "\(appState.myProfile?.id.uuidString ?? ""):\(appState.activeOrgId?.uuidString ?? "")" }
  private func save() async {
    guard editContext == context, let service = appState.supabase, let org = appState.activeOrgId else { return }
    guard price.isEmpty || (Int(price).map { $0 >= 0 } == true) else { errorText = "Enter a nonnegative whole number of cents."; return }
    guard !["paid", "package_credit"].contains(bookingMode) || verified else { errorText = "Verify pricing before enabling paid or package bookings."; return }
    guard bookingMode != "paid" || !price.isEmpty else { errorText = "Set a price for paid bookings."; return }
    busy = true
    defer { busy = false }
    do {
      try await service.trainingAction(organizationId: org, action: "save_service", payload: ["service": .object([
        "name": .string(name), "description": .string(description), "duration_minutes": .int(duration),
        "id": existing.map { .string($0.id.uuidString) } ?? .null,
        "slug": existing?.slug.map(SDJSONValue.string) ?? .null,
        "category": .string(existing?.category ?? "lesson"),
        "capacity": .int(capacity), "public_booking_mode": .string(bookingMode),
        "public_visible": .bool(visible), "price_cents": Int(price).map(SDJSONValue.int) ?? .null,
        "price_verified": .bool(verified), "active": .bool(active), "cancellation_policy": .string(cancellationPolicy),
      ])])
      await onSaved()
    } catch { uncertain = true; errorText = "The service could not be confirmed. Refresh the catalog before trying again." }
  }
}
