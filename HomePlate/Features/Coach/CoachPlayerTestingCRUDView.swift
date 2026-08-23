import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Coach-facing Testing tab with add/edit (Shiny parity).
struct CoachPlayerTestingCRUDView: View {
  @EnvironmentObject private var appState: AppState
  let player: Profile
  let canManagePlayer: Bool

  @State private var entries: [SDTestingEntry] = []
  @State private var fieldDefinitions: [SDTestingFieldDefinition] = []
  @State private var isLoading = false
  @State private var showAdd = false
  @State private var showFieldManager = false
  @State private var editingEntry: SDTestingEntry?
  @State private var errorText: String?

  var body: some View {
    HPListScreenLayout {
      HPWorkspaceHeader(
        "Testing",
        orgLabel: activeOrganizationName,
        context: player.displayName
      ) {
        HPButton(
          title: "Fields",
          systemImage: "slider.horizontal.3",
          variant: .secondary,
          size: .sm,
          action: { showFieldManager = true }
        )
        .disabled(!canManagePlayer)
        HPButton(
          title: "Add entry",
          systemImage: "plus",
          variant: .primary,
          size: .sm,
          action: { showAdd = true }
        )
        .disabled(!canManagePlayer)
      }
    } controls: {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HStack(spacing: HP.Space.sm) {
            Image(systemName: "list.bullet.clipboard")
              .foregroundStyle(HP.Color.accent)
              .accessibilityHidden(true)
            Text("\(entries.count) \(entries.count == 1 ? "entry" : "entries")")
              .font(HP.Font.callout)
              .foregroundStyle(HP.Color.text)
            Spacer(minLength: 0)
            if isLoading {
              HPProgressIndicator(style: .spinner)
                .accessibilityLabel("Loading testing entries")
            }
          }

          if !canManagePlayer {
            Label("Your organization limits testing changes to players on your assigned team.", systemImage: "lock.fill")
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.warning)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    } results: { context in
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Entries") {
            HPStatusBadge(text: "\(entries.count)", kind: .neutral)
          }

          if isLoading {
            HPLoadingState(text: "Loading…")
          } else if entries.isEmpty {
            HPEmptyState(
              title: "No testing entries yet.",
              message: "Testing entries for \(player.displayName) will appear here.",
              systemImage: "list.bullet.clipboard"
            )
          } else {
            if context.tableLayout == .columns {
              testingColumnHeader
            }

            ForEach(entries) { entry in
              Button {
                editingEntry = entry
              } label: {
                testingEntryRow(entry, stacked: context.tableLayout != .columns)
              }
              .buttonStyle(.plain)
              .disabled(!canManagePlayer)
              .accessibilityHint(
                canManagePlayer
                  ? "Opens the testing entry editor"
                  : "Testing changes are unavailable for this player"
              )

              if entry.id != entries.last?.id {
                Divider().overlay(HP.Color.border.opacity(0.5))
              }
            }
          }
        }
      }
    }
    .sheet(isPresented: $showAdd) {
      TestingEntryFormSheet(
        title: "Add entry",
        playerId: player.id,
        existing: nil,
        fields: fieldDefinitions
      ) { saved in
        entries.removeAll(where: { $0.entry_date == saved.entry_date })
        entries.insert(saved, at: 0)
      }
      .environmentObject(appState)
    }
    .sheet(item: $editingEntry) { existing in
      TestingEntryFormSheet(
        title: "Edit entry",
        playerId: player.id,
        existing: existing,
        fields: fieldDefinitions
      ) { saved in
        entries.removeAll(where: { $0.entry_date == saved.entry_date })
        entries.insert(saved, at: 0)
      }
      .environmentObject(appState)
    }
    .sheet(isPresented: $showFieldManager) {
      TestingFieldManagerSheet(fields: fieldDefinitions) { updated in
        fieldDefinitions = updated
      }
      .environmentObject(appState)
    }
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .task { await reload() }
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

  private var testingColumnHeader: some View {
    HStack(spacing: HP.Space.sm) {
      Text("DATE")
        .frame(width: 140, alignment: .leading)
      Text("MEASUREMENTS")
        .frame(maxWidth: .infinity, alignment: .leading)
      Color.clear
        .frame(width: 20, height: 1)
        .accessibilityHidden(true)
    }
    .font(HP.Font.eyebrow)
    .tracking(HP.Font.eyebrowTracking)
    .foregroundStyle(HP.Color.textMuted)
    .padding(.vertical, 6)
  }

  @ViewBuilder
  private func testingEntryRow(_ entry: SDTestingEntry, stacked: Bool) -> some View {
    if stacked {
      VStack(alignment: .leading, spacing: HP.Space.xs) {
        Text(entry.entry_date)
          .font(HP.Font.headline)
          .foregroundStyle(HP.Color.text)
        Text(summary(entry))
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
        if canManagePlayer {
          Label("Edit entry", systemImage: "pencil")
            .font(HP.Font.caption.weight(.semibold))
            .foregroundStyle(HP.Color.accent)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
    } else {
      HStack(spacing: HP.Space.sm) {
        Text(entry.entry_date)
          .font(HP.Font.callout.weight(.semibold))
          .foregroundStyle(HP.Color.text)
          .frame(width: 140, alignment: .leading)
        Text(summary(entry))
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(HP.Color.textMuted)
          .frame(width: 20)
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
    }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      async let loadedEntries = supabase.listTestingEntries(playerId: player.id)
      if let orgId = appState.activeOrgId {
        async let loadedFields = supabase.listTestingFieldDefinitions(orgId: orgId, includeInactive: true)
        (entries, fieldDefinitions) = try await (loadedEntries, loadedFields)
      } else {
        entries = try await loadedEntries
        fieldDefinitions = []
      }
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func summary(_ e: SDTestingEntry) -> String {
    if let values = e.custom_values, !values.isEmpty {
      let definitions = Dictionary(uniqueKeysWithValues: fieldDefinitions.map { ($0.field_key, $0) })
      return values
        .sorted { lhs, rhs in
          (definitions[lhs.key]?.sort_order ?? .max) < (definitions[rhs.key]?.sort_order ?? .max)
        }
        .prefix(4)
        .map { key, value in
          let field = definitions[key]
          return "\(field?.label ?? key.testingFieldTitle): \(value.testingDisplayValue(unit: field?.unit))"
        }
        .joined(separator: " • ")
    }
    var parts: [String] = []
    if let v = e.squat_1rm { parts.append("Sq \(fmt(v))") }
    if let v = e.bench_1rm { parts.append("Bn \(fmt(v))") }
    if let v = e.deadlift_1rm { parts.append("Dl \(fmt(v))") }
    if let v = e.max_exit_velo { parts.append("MaxEV \(fmt(v))") }
    if let v = e.avg_exit_velo { parts.append("AvgEV \(fmt(v))") }
    return parts.isEmpty ? "—" : parts.joined(separator: " • ")
  }

  private func fmt(_ v: Double) -> String {
    if v.rounded() == v { return String(Int(v)) }
    return String(format: "%.1f", v)
  }
}

struct TestingEntryFormSheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appState: AppState

  let title: String
  let playerId: UUID
  let existing: SDTestingEntry?
  let fields: [SDTestingFieldDefinition]
  var allowsFieldVideos = false
  let onSaved: (SDTestingEntry) -> Void

  @State private var date: Date = Date()
  @State private var values: [String: String] = [:]
  @State private var notes = ""
  @State private var fieldVideos: [String: PendingTestingVideo] = [:]
  @State private var isSaving = false
  @State private var errorText: String?

  private struct NumericKeyboard: ViewModifier {
    func body(content: Content) -> some View {
      #if canImport(UIKit)
      return content.keyboardType(.decimalPad)
      #else
      return content
      #endif
    }
  }

  var body: some View {
    NavigationStack {
      HPFormScreenLayout { _ in
        HPWorkspaceHeader(
          title,
          orgLabel: activeOrganizationName,
          context: existing == nil ? "New testing entry" : "Testing entry • \(existing?.entry_date ?? "")"
        )
      } sections: { _ in
        dateSection
        testingSections
        notesSection
      } primaryAction: { context in
        HPButton(
          title: "Save",
          systemImage: "checkmark",
          variant: .primary,
          size: .lg,
          isLoading: isSaving,
          fullWidth: context.isAccessibilitySize,
          action: { Task { await save() } }
        )
        .disabled(isSaving)
      } secondaryAction: { context in
        HPButton(
          title: "Cancel",
          variant: .secondary,
          size: .lg,
          fullWidth: context.isAccessibilitySize,
          action: { dismiss() }
        )
      }
      .navigationTitle(title)
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
      .task { preload() }
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

  private var dateSection: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Date")
        DatePicker("Entry date", selection: $date, displayedComponents: .date)
          .font(HP.Font.body)
          .foregroundStyle(HP.Color.text)
          .tint(HP.Color.accent)
      }
    }
  }

  @ViewBuilder
  private var testingSections: some View {
    let activeFields = fields.filter(\.is_active)
    let categories = Array(Set(activeFields.map(\.category))).sorted { lhs, rhs in
      let lhsOrder = activeFields.first(where: { $0.category == lhs })?.sort_order ?? .max
      let rhsOrder = activeFields.first(where: { $0.category == rhs })?.sort_order ?? .max
      return lhsOrder < rhsOrder
    }

    if activeFields.isEmpty {
      HPCard {
        HPEmptyState(
          title: "No testing fields",
          message: "A coach can add the measurements used by this organization.",
          systemImage: "slider.horizontal.3"
        )
      }
    } else {
      ForEach(categories, id: \.self) { category in
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.md) {
            HPSectionHeader(category)
            ForEach(activeFields.filter { $0.category == category }) { field in
              testingField(field)
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func testingField(_ field: SDTestingFieldDefinition) -> some View {
    VStack(alignment: .leading, spacing: HP.Space.xs) {
      let label = field.unit.map { "\(field.label) (\($0))" } ?? field.label
      if field.valueType == .boolean {
        Picker(label, selection: valueBinding(field.field_key)) {
          Text("Not recorded").tag("")
          Text("Yes").tag("true")
          Text("No").tag("false")
        }
        .pickerStyle(.menu)
      } else {
        HPFormField(
          label: field.is_required ? "\(label) • Required" : label,
          text: valueBinding(field.field_key),
          placeholder: field.valueType == .time ? "Example: 6.82 sec" : "Optional"
        )
        .modifier(TestingKeyboard(valueType: field.valueType))
      }

      if allowsFieldVideos {
        TestingFieldVideoPicker(
          fieldLabel: field.label,
          pending: Binding(
            get: { fieldVideos[field.field_key] },
            set: { newValue in
              if let newValue {
                fieldVideos[field.field_key] = newValue
              } else {
                fieldVideos.removeValue(forKey: field.field_key)
              }
            }
          ),
          onError: { errorText = $0 }
        )
      }
    }
  }

  private var notesSection: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Notes")
        HPFormField(
          label: "Notes (optional)",
          text: $notes,
          kind: .multiline,
          placeholder: "Notes (optional)"
        )
      }
    }
  }

  private struct TestingKeyboard: ViewModifier {
    let valueType: SDTestingFieldValueType

    func body(content: Content) -> some View {
      #if canImport(UIKit)
      if valueType == .number {
        content.keyboardType(.decimalPad)
      } else {
        content
      }
      #else
      content
      #endif
    }
  }

  private func valueBinding(_ key: String) -> Binding<String> {
    Binding(
      get: { values[key, default: ""] },
      set: { values[key] = $0 }
    )
  }

  private func preload() {
    guard let existing else { return }
    date = DateUtils.fromISODate(existing.entry_date) ?? Date()
    values = existing.testingValues
    notes = existing.notes ?? ""
  }

  private func toDouble(_ s: String) -> Double? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return nil }
    return Double(t)
  }

  private func save() async {
    guard let supabase = appState.supabase else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      let missingRequired = fields
        .filter { $0.is_active && $0.is_required }
        .first { values[$0.field_key, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      if let missingRequired {
        errorText = "Enter a value for \(missingRequired.label)."
        return
      }

      var customValues: [String: SDJSONValue] = [:]
      for field in fields where field.is_active {
        let raw = values[field.field_key, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { continue }
        switch field.valueType {
        case .number:
          guard let number = Double(raw) else {
            errorText = "Enter a valid number for \(field.label)."
            return
          }
          customValues[field.field_key] = .double(number)
        case .boolean:
          customValues[field.field_key] = .bool(raw == "true")
        case .text, .time:
          customValues[field.field_key] = .string(raw)
        }
      }

      let create = SDTestingEntryCreate(
        org_id: appState.activeOrgId,
        player_id: playerId,
        entry_date: DateUtils.toISODate(date),
        height_in: customValues["height_in"]?.doubleValue,
        weight_lb: customValues["weight_lb"]?.doubleValue,
        squat_1rm: customValues["squat_1rm"]?.doubleValue,
        bench_1rm: customValues["bench_1rm"]?.doubleValue,
        deadlift_1rm: customValues["deadlift_1rm"]?.doubleValue,
        max_exit_velo: customValues["max_exit_velo"]?.doubleValue,
        avg_exit_velo: customValues["avg_exit_velo"]?.doubleValue,
        hip_er_diff: customValues["hip_er_diff"]?.doubleValue,
        hip_ir_diff: customValues["hip_ir_diff"]?.doubleValue,
        shoulder_ir_diff: customValues["shoulder_ir_diff"]?.doubleValue,
        shoulder_er_diff: customValues["shoulder_er_diff"]?.doubleValue,
        custom_values: customValues,
        notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
      )
      let saved = try await supabase.upsertTestingEntry(create)
      if allowsFieldVideos, let organizationId = appState.activeOrgId {
        for (fieldKey, video) in fieldVideos {
          let path = try await supabase.uploadTestingFieldVideo(
            video.data,
            organizationId: organizationId,
            playerId: playerId,
            testingEntryId: saved.id,
            fieldKey: fieldKey,
            fileExtension: video.fileExtension,
            contentType: video.contentType
          )
          try await supabase.upsertTestingFieldMedia(
            testingEntryId: saved.id,
            fieldKey: fieldKey,
            storagePath: path,
            fileName: video.fileName,
            mimeType: video.contentType,
            byteSize: video.data.count
          )
        }
      }
      onSaved(saved)
      dismiss()
    } catch {
      errorText = error.localizedDescription
    }
  }
}

private struct PendingTestingVideo {
  let data: Data
  let fileName: String
  let fileExtension: String
  let contentType: String
}

private struct TestingFieldVideoPicker: View {
  let fieldLabel: String
  @Binding var pending: PendingTestingVideo?
  let onError: (String) -> Void

  @State private var pickerItem: PhotosPickerItem?
  @State private var isLoading = false

  var body: some View {
    HStack(spacing: HP.Space.xs) {
      PhotosPicker(selection: $pickerItem, matching: .videos) {
        Label("Add or replace video", systemImage: "video.badge.plus")
          .font(HP.Font.caption.weight(.semibold))
      }
      .disabled(isLoading)
      .onChange(of: pickerItem) { _, item in
        guard let item else { return }
        Task { await load(item) }
      }

      if isLoading { ProgressView().controlSize(.small) }
      if pending != nil {
        Label("Video ready", systemImage: "checkmark.circle.fill")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.success)
        Button(role: .destructive) { pending = nil } label: {
          Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove video for \(fieldLabel)")
      }
    }
  }

  private func load(_ item: PhotosPickerItem) async {
    isLoading = true
    defer { isLoading = false }
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else {
        onError("That video could not be loaded.")
        return
      }
      guard data.count <= 262_144_000 else {
        onError("Videos must be 250 MB or smaller.")
        return
      }
      let type = item.supportedContentTypes.first(where: { $0.conforms(to: .movie) })
      let compatibleData = try await CompatibleVideoTranscoder.mp4Data(
        from: data,
        sourceExtension: type?.preferredFilenameExtension ?? "mov"
      )
      pending = PendingTestingVideo(
        data: compatibleData,
        fileName: "\(fieldLabel)-video.mp4",
        fileExtension: "mp4",
        contentType: "video/mp4"
      )
    } catch {
      onError("That video could not be prepared. Try another clip.")
    }
  }
}

private struct TestingFieldManagerSheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appState: AppState

  let onChanged: ([SDTestingFieldDefinition]) -> Void

  @State private var fields: [SDTestingFieldDefinition]
  @State private var editingId: UUID?
  @State private var label = ""
  @State private var category = "General"
  @State private var unit = ""
  @State private var valueType: SDTestingFieldValueType = .number
  @State private var isRequired = false
  @State private var isActive = true
  @State private var isSaving = false
  @State private var pendingDeletion: SDTestingFieldDefinition?
  @State private var errorText: String?

  init(
    fields: [SDTestingFieldDefinition],
    onChanged: @escaping ([SDTestingFieldDefinition]) -> Void
  ) {
    self.onChanged = onChanged
    _fields = State(initialValue: fields.sorted(by: Self.fieldOrder))
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          if fields.isEmpty {
            ContentUnavailableView(
              "No testing fields",
              systemImage: "slider.horizontal.3",
              description: Text("Add the first measurement coaches and players should record.")
            )
          } else {
            ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
              VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                  VStack(alignment: .leading, spacing: 3) {
                    Text(field.label).font(.headline)
                    Text(fieldDetail(field))
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                  Spacer()
                  Menu {
                    Button("Move up", systemImage: "arrow.up") {
                      Task { await move(field, direction: -1) }
                    }
                    .disabled(index == 0)
                    Button("Move down", systemImage: "arrow.down") {
                      Task { await move(field, direction: 1) }
                    }
                    .disabled(index == fields.count - 1)
                    Button("Edit", systemImage: "pencil") { edit(field) }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                      pendingDeletion = field
                    }
                  } label: {
                    Image(systemName: "ellipsis.circle")
                      .font(.title3)
                  }
                }
              }
              .padding(.vertical, 4)
            }
          }
        } header: {
          Text("Organization fields")
        } footer: {
          Text("Deleting a field removes it from future forms. Results already submitted remain saved.")
        }

        Section(editingId == nil ? "Add field" : "Edit field") {
          TextField("Field name", text: $label)
          TextField("Category", text: $category)
          Picker("Value type", selection: $valueType) {
            ForEach(SDTestingFieldValueType.allCases) { type in
              Text(type.title).tag(type)
            }
          }
          TextField("Unit (optional)", text: $unit)
          Toggle("Required result", isOn: $isRequired)
          Toggle("Show on future forms", isOn: $isActive)

          Button {
            Task { await save() }
          } label: {
            if isSaving {
              ProgressView()
            } else {
              Label(editingId == nil ? "Add field" : "Save field", systemImage: "checkmark")
            }
          }
          .disabled(isSaving || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

          if editingId != nil {
            Button("Cancel edit") { resetEditor() }
          }
        }
      }
      .navigationTitle("Testing fields")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .confirmationDialog(
        "Delete testing field?",
        isPresented: Binding(
          get: { pendingDeletion != nil },
          set: { if !$0 { pendingDeletion = nil } }
        ),
        titleVisibility: .visible
      ) {
        if let field = pendingDeletion {
          Button("Delete \(field.label)", role: .destructive) {
            Task { await delete(field) }
          }
        }
        Button("Cancel", role: .cancel) { pendingDeletion = nil }
      } message: {
        Text("Existing submitted results will not be deleted.")
      }
      .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorText ?? "")
      }
    }
  }

  private static func fieldOrder(_ lhs: SDTestingFieldDefinition, _ rhs: SDTestingFieldDefinition) -> Bool {
    if lhs.sort_order == rhs.sort_order { return lhs.label < rhs.label }
    return lhs.sort_order < rhs.sort_order
  }

  private func fieldDetail(_ field: SDTestingFieldDefinition) -> String {
    [
      field.category,
      field.valueType.title,
      field.unit,
      field.is_required ? "Required" : nil,
      field.is_active ? nil : "Hidden",
    ]
    .compactMap { $0 }
    .joined(separator: " • ")
  }

  private func edit(_ field: SDTestingFieldDefinition) {
    editingId = field.id
    label = field.label
    category = field.category
    unit = field.unit ?? ""
    valueType = field.valueType
    isRequired = field.is_required
    isActive = field.is_active
  }

  private func resetEditor() {
    editingId = nil
    label = ""
    category = "General"
    unit = ""
    valueType = .number
    isRequired = false
    isActive = true
  }

  private func save() async {
    guard let supabase = appState.supabase, let orgId = appState.activeOrgId else { return }
    isSaving = true
    defer { isSaving = false }

    let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
    let existing = editingId.flatMap { id in fields.first(where: { $0.id == id }) }
    let write = SDTestingFieldDefinitionWrite(
      org_id: orgId,
      field_key: existing?.field_key ?? makeFieldKey(trimmedLabel),
      label: trimmedLabel,
      category: category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "General"
        : category.trimmingCharacters(in: .whitespacesAndNewlines),
      unit: unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? nil
        : unit.trimmingCharacters(in: .whitespacesAndNewlines),
      value_type: valueType.rawValue,
      is_required: isRequired,
      sort_order: existing?.sort_order ?? ((fields.map(\.sort_order).max() ?? 0) + 10),
      is_active: isActive
    )

    do {
      let saved: SDTestingFieldDefinition
      if let editingId {
        saved = try await supabase.updateTestingFieldDefinition(id: editingId, field: write)
        fields.removeAll(where: { $0.id == editingId })
      } else {
        saved = try await supabase.createTestingFieldDefinition(write)
      }
      fields.append(saved)
      publish()
      resetEditor()
    } catch {
      errorText = SDApplicationErrorClassifier.alertMessage(for: error) ?? error.localizedDescription
    }
  }

  private func delete(_ field: SDTestingFieldDefinition) async {
    guard let supabase = appState.supabase else { return }
    pendingDeletion = nil
    do {
      try await supabase.deleteTestingFieldDefinition(id: field.id)
      fields.removeAll(where: { $0.id == field.id })
      if editingId == field.id { resetEditor() }
      publish()
    } catch {
      errorText = SDApplicationErrorClassifier.alertMessage(for: error) ?? error.localizedDescription
    }
  }

  private func move(_ field: SDTestingFieldDefinition, direction: Int) async {
    guard let supabase = appState.supabase,
          let index = fields.firstIndex(where: { $0.id == field.id }) else { return }
    let targetIndex = index + direction
    guard fields.indices.contains(targetIndex) else { return }
    let target = fields[targetIndex]

    do {
      let moved = try await supabase.updateTestingFieldDefinition(
        id: field.id,
        field: write(field, sortOrder: target.sort_order)
      )
      let swapped = try await supabase.updateTestingFieldDefinition(
        id: target.id,
        field: write(target, sortOrder: field.sort_order)
      )
      fields.removeAll(where: { $0.id == moved.id || $0.id == swapped.id })
      fields.append(contentsOf: [moved, swapped])
      publish()
    } catch {
      errorText = SDApplicationErrorClassifier.alertMessage(for: error) ?? error.localizedDescription
    }
  }

  private func write(_ field: SDTestingFieldDefinition, sortOrder: Int) -> SDTestingFieldDefinitionWrite {
    SDTestingFieldDefinitionWrite(
      org_id: field.org_id,
      field_key: field.field_key,
      label: field.label,
      category: field.category,
      unit: field.unit,
      value_type: field.value_type,
      is_required: field.is_required,
      sort_order: sortOrder,
      is_active: field.is_active
    )
  }

  private func publish() {
    fields.sort(by: Self.fieldOrder)
    onChanged(fields)
  }

  private func makeFieldKey(_ source: String) -> String {
    var key = source
      .lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
      .joined(separator: "_")
    while let first = key.first, first.isNumber {
      key.removeFirst()
      key = key.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
    if key.isEmpty { key = "custom_field" }
    key = String(key.prefix(56))
    let used = Set(fields.map(\.field_key))
    if !used.contains(key) { return key }
    var suffix = 2
    while used.contains("\(key)_\(suffix)") { suffix += 1 }
    return "\(key)_\(suffix)"
  }
}
