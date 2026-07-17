import SwiftUI

struct EventAvailabilityEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  let playerName: String
  let initial: SDEventAvailabilityDraft
  let onSave: (SDEventAvailabilityDraft, UUID) -> Void
  @State private var draft: SDEventAvailabilityDraft
  @State private var setArrival: Bool
  @State private var setDeparture: Bool

  init(
    playerName: String,
    initial: SDEventAvailabilityDraft,
    onSave: @escaping (SDEventAvailabilityDraft, UUID) -> Void
  ) {
    self.playerName = playerName
    self.initial = initial
    self.onSave = onSave
    _draft = State(initialValue: initial)
    _setArrival = State(initialValue: initial.expectedArrival != nil)
    _setDeparture = State(initialValue: initial.expectedDeparture != nil)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Availability") {
          Picker("Status", selection: $draft.status) {
            ForEach(SDEventAvailabilityStatus.allCases.filter { $0 != .unknown }) {
              Text($0.label).tag($0)
            }
          }
          TextField("Optional reason", text: $draft.reason, axis: .vertical)
        }
        Section("Expected timing") {
          Toggle("Expected late arrival", isOn: $setArrival)
            .onChange(of: setArrival) { _, enabled in
              draft.expectedArrival = enabled ? (draft.expectedArrival ?? Date()) : nil
            }
          if setArrival {
            DatePicker("Expected arrival", selection: Binding(
              get: { draft.expectedArrival ?? Date() },
              set: { draft.expectedArrival = $0 }
            ))
          }
          Toggle("Leaving early", isOn: $setDeparture)
            .onChange(of: setDeparture) { _, enabled in
              draft.expectedDeparture = enabled ? (draft.expectedDeparture ?? Date()) : nil
            }
          if setDeparture {
            DatePicker("Expected departure", selection: Binding(
              get: { draft.expectedDeparture ?? Date() },
              set: { draft.expectedDeparture = $0 }
            ))
          }
        }
        Text("Availability is a pre-event declaration. Coaches record official attendance separately during the event.")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
      }
      .navigationTitle("\(playerName) Availability")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            if !setArrival { draft.expectedArrival = nil }
            if !setDeparture { draft.expectedDeparture = nil }
            onSave(draft, UUID())
          }
          .disabled(
            draft.status == .unknown ||
              (draft.status == .late && !setArrival) ||
              (draft.status == .leavingEarly && !setDeparture)
          )
        }
      }
    }
  }
}
