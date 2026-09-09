import SwiftUI

struct HPTrainingPackageEditor: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  let existing: HPTrainingWorkspace.Package?
  let onSaved: () async -> Void
  @State private var id: UUID
  @State private var name: String
  @State private var description: String
  @State private var credits: Int
  @State private var price: String
  @State private var days: String
  @State private var visible: Bool
  @State private var active: Bool
  @State private var verified: Bool
  @State private var busy = false
  @State private var errorText: String?
  @State private var uncertain = false
  @State private var editContext: String?

  init(existing: HPTrainingWorkspace.Package? = nil, onSaved: @escaping () async -> Void) {
    self.existing = existing; self.onSaved = onSaved
    _id = State(initialValue: existing?.id ?? UUID())
    _name = State(initialValue: existing?.name ?? "")
    _description = State(initialValue: existing?.description ?? "")
    _credits = State(initialValue: existing?.credits ?? 10)
    _price = State(initialValue: existing?.price_cents.map(String.init) ?? "")
    _days = State(initialValue: existing?.validity_days.map(String.init) ?? "")
    _visible = State(initialValue: existing?.public_visible ?? false)
    _active = State(initialValue: existing?.active ?? true)
    _verified = State(initialValue: existing?.price_verification_required == false)
  }
  var body: some View {
    NavigationStack {
      Form {
        TextField("Package name", text: $name)
        TextField("Description", text: $description, axis: .vertical)
        Stepper("Credits: \(credits)", value: $credits, in: 1...10000)
        TextField("Price in \(existing?.currency?.uppercased() ?? "USD") cents", text: $price)
        TextField("Validity in days (blank for no expiry)", text: $days)
        Toggle("Price reviewed and verified", isOn: $verified)
        Toggle("Publicly visible", isOn: $visible)
        Toggle("Active", isOn: $active)
        Text("Issued credits retain their original terms. Once credits have been issued, create a new package to change credit count or validity. Saving this catalog entry does not charge a customer or issue credits.")
        if let errorText { Text(errorText).foregroundStyle(.red) }
        if uncertain { Button("Refresh catalog and close") { Task { await onSaved() } } }
      }
      .disabled(busy)
      .navigationTitle(existing == nil ? "Create package" : "Edit package")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
        ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(busy || uncertain || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
      }
      .interactiveDismissDisabled(busy)
      .onAppear { if editContext == nil { editContext = context } }
    }
  }
  private var context: String { "\(appState.myProfile?.id.uuidString ?? ""):\(appState.activeOrgId?.uuidString ?? "")" }
  private func save() async {
    guard editContext == context, let service = appState.supabase, let org = appState.activeOrgId else { return }
    guard price.isEmpty || Int(price).map({ (0...Int(Int32.max)).contains($0) }) == true,
          days.isEmpty || Int(days).map({ (1...3650).contains($0) }) == true else {
      errorText = "Use nonnegative whole cents and validity between 1 and 3650 days, or leave blank."; return
    }
    busy = true; defer { busy = false }
    do {
      try await service.trainingAction(organizationId: org, action: "save_package", payload: [
        "package_id": .string(id.uuidString), "expected_updated_at": existing?.updated_at.map(SDJSONValue.string) ?? .null,
        "package": .object(["name": .string(name), "description": .string(description), "credits": .int(credits),
          "price_cents": Int(price).map(SDJSONValue.int) ?? .null, "validity_days": Int(days).map(SDJSONValue.int) ?? .null,
          "active": .bool(active), "public_visible": .bool(visible), "price_verified": .bool(verified)]),
      ])
      await onSaved()
    } catch {
      uncertain = true
      errorText = "The save was not confirmed. Existing purchases may lock package terms, or another staff member may have edited this package. Refresh before making further changes."
    }
  }
}
