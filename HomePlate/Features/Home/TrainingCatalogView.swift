import SwiftUI

struct HPTrainingCatalogView: View {
  @EnvironmentObject private var appState: AppState
  let workspace: HPTrainingWorkspace
  let onSaved: () async -> Void
  @State private var creatingService = false

  var body: some View {
    List {
      Section("Services") {
        ForEach(workspace.services) { service in
          VStack(alignment: .leading, spacing: 6) {
            Text(service.name).font(.headline)
            if let description = service.description { Text(description) }
            Text("\(service.duration_minutes.map(String.init) ?? "—") minutes · Capacity \(service.capacity.map(String.init) ?? "—")").font(.caption)
            Text(service.active == true ? "Active" : "Inactive").font(.caption)
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
          }
        }
      }
      Section("Packages") {
        ForEach(workspace.packages ?? []) { package in
          VStack(alignment: .leading) {
            Text(package.name).font(.headline)
            Text("\(package.credits.map(String.init) ?? "—") credits · \(package.active ? "Active" : "Inactive")")
            if let days = package.validity_days { Text("Valid for \(days) days after verified payment").font(.caption) }
          }
        }
      }
    }
    .navigationTitle("Training catalog")
    .sheet(isPresented: $creatingService) {
      HPCreateTrainingServiceView { await onSaved(); creatingService = false }
    }
  }
}

private struct HPCreateTrainingServiceView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  let onSaved: () async -> Void
  @State private var name = ""
  @State private var description = ""
  @State private var duration = 60
  @State private var capacity = 1
  @State private var busy = false
  @State private var errorText: String?
  var body: some View {
    NavigationStack {
      Form {
        TextField("Service name", text: $name)
        TextField("Description", text: $description, axis: .vertical)
        Stepper("\(duration) minutes", value: $duration, in: 15...480, step: 15)
        Stepper("Capacity: \(capacity)", value: $capacity, in: 1...500)
        Text("New services start as private inquiries. Assign trainers, availability and verified pricing before enabling public booking.")
        if let errorText { Text(errorText).foregroundStyle(.red) }
      }.navigationTitle("Create service")
        .disabled(busy)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") { Task { await save() } }.disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
        .interactiveDismissDisabled(busy)
    }
  }
  private func save() async {
    guard let service = appState.supabase, let org = appState.activeOrgId else { return }
    busy = true
    defer { busy = false }
    do {
      try await service.trainingAction(organizationId: org, action: "save_service", payload: ["service": .object([
        "name": .string(name), "description": .string(description), "duration_minutes": .int(duration),
        "capacity": .int(capacity), "public_booking_mode": .string("inquiry"),
        "public_visible": .bool(false), "price_cents": .null, "price_verified": .bool(false), "active": .bool(true),
      ])])
      await onSaved()
    } catch { errorText = "The service could not be confirmed. Refresh the catalog before trying again." }
  }
}
