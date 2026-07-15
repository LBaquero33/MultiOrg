import SwiftUI

struct CoachProgramsView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appState: AppState

  @State private var templates: [SDProgramTemplate] = []
  @State private var isLoading = false
  @State private var errorText: String?

  @State private var showCreate = false
  @State private var query = ""
  @State private var selectedKind: SDProgramKind = .strength

#if os(macOS)
  @State private var selectedTemplateId: UUID?
#endif

  var body: some View {
#if os(macOS)
    NavigationSplitView {
      templateList
        .navigationTitle("Program Templates")
    } detail: {
      templateDetail
        .navigationTitle(selectedTemplate?.name ?? "Program Templates")
    }
    .task { await reload() }
    .searchable(text: $query, placement: .toolbar, prompt: "Search templates")
    .toolbar {
      ToolbarItemGroup(placement: .automatic) {
        Button {
          showCreate = true
        } label: { Image(systemName: "plus") }
        Button {
          Task { await reload() }
        } label: { Image(systemName: "arrow.clockwise") }
      }
    }
    .sheet(isPresented: $showCreate) {
      CreateProgramTemplateSheet(kind: selectedKind) { created in
        templates.insert(created, at: 0)
        selectedTemplateId = created.id
      }
      .environmentObject(appState)
      .frame(minWidth: 520, minHeight: 540)
    }
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
#else
    NavigationStack {
      List {
        Section {
          Picker("Program type", selection: $selectedKind) {
            ForEach(SDProgramKind.allCases) { kind in
              Label(kind.title, systemImage: kind.systemImage).tag(kind)
            }
          }
          .pickerStyle(.segmented)
        }

        if isLoading {
          HStack(spacing: 10) {
            ProgressView()
            Text("Loading…").foregroundStyle(.secondary)
          }
        } else if visibleTemplates.isEmpty {
          Text("No \(selectedKind.title) program templates yet.")
            .foregroundStyle(.secondary)
        } else {
          Section("\(selectedKind.title) program templates") {
            ForEach(visibleTemplates) { t in
              NavigationLink {
                ProgramTemplateEditorView(
                  template: t,
                  onDuplicated: { templates.insert($0, at: 0) },
                  onDeleted: { templates.removeAll { $0.id == t.id } }
                )
                .id(t.id)
              } label: {
                VStack(alignment: .leading, spacing: 2) {
                  Text(t.name).font(.headline)
                  Text("\(t.weeks) weeks • \(weekdayLabel(t.lift_weekdays))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
              }
            }
          }
        }
      }
      .navigationTitle("Programs")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
          Button {
            showCreate = true
          } label: {
            Image(systemName: "plus")
          }
        }
      }
      .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorText ?? "")
      }
      .sheet(isPresented: $showCreate) {
        CreateProgramTemplateSheet(kind: selectedKind) { created in
          templates.insert(created, at: 0)
        }
        .environmentObject(appState)
      }
      .task {
        await reload()
      }
    }
#endif
  }

  private var visibleTemplates: [SDProgramTemplate] {
    templates.filter { $0.kind == selectedKind }
  }

#if os(macOS)
  private var filteredTemplates: [SDProgramTemplate] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return templates.filter {
      $0.kind == selectedKind && (q.isEmpty || $0.name.lowercased().contains(q))
    }
  }

  private var selectedTemplate: SDProgramTemplate? {
    guard let selectedTemplateId else { return nil }
    return templates.first(where: { $0.id == selectedTemplateId })
  }

  private var templateList: some View {
    List(selection: $selectedTemplateId) {
      Section {
        Picker("Program type", selection: $selectedKind) {
          ForEach(SDProgramKind.allCases) { kind in
            Label(kind.title, systemImage: kind.systemImage).tag(kind)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
      }
      if isLoading {
        HStack(spacing: 10) { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
      } else if filteredTemplates.isEmpty {
        Text("No \(selectedKind.title) program templates yet.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(filteredTemplates) { t in
          VStack(alignment: .leading, spacing: 2) {
            Text(t.name).font(.headline)
            Text("\(t.weeks) weeks • \(weekdayLabel(t.lift_weekdays))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .tag(t.id)
          .padding(.vertical, 4)
        }
      }
    }
  }

  @ViewBuilder
  private var templateDetail: some View {
    if let t = selectedTemplate {
      ProgramTemplateEditorView(
        template: t,
        onDuplicated: { duplicated in
          templates.insert(duplicated, at: 0)
          selectedTemplateId = duplicated.id
        },
        onDeleted: {
          templates.removeAll { $0.id == t.id }
          selectedTemplateId = filteredTemplates.first?.id
        }
      )
        .id(t.id)
        .environmentObject(appState)
    } else {
      VStack(spacing: 10) {
        Text("Select a template")
          .font(.title3.weight(.semibold))
        Text("Choose a program template to edit, or create a new one.")
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(DHDTheme.pageBackground)
    }
  }
#endif

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      templates = try await supabase.listMyCoachTemplates()
#if os(macOS)
      if selectedTemplateId == nil {
        selectedTemplateId = templates.first?.id
      }
#endif
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func weekdayLabel(_ days: [Int]) -> String {
    let map: [Int: String] = [1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 7: "Sun"]
    return days.compactMap { map[$0] }.joined(separator: ", ")
  }
}

private struct CreateProgramTemplateSheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appState: AppState
  let kind: SDProgramKind
  let onCreated: (SDProgramTemplate) -> Void

  @State private var name = ""
  @State private var weeks = 2
  @State private var liftDays: Set<Int> = [1, 3, 5] // MWF
  @State private var isSaving = false
  @State private var errorText: String?

  var body: some View {
    NavigationStack {
      Form {
        Section("Template") {
          TextField("\(kind.title) program name", text: $name)
          Picker("Weeks", selection: $weeks) {
            Text("2 weeks").tag(2)
            Text("4 weeks").tag(4)
          }
        }

        Section(kind == .strength ? "Lift days (weekdays)" : "Training days (weekdays)") {
          ForEach(1...7, id: \.self) { i in
            Toggle(weekday(i), isOn: Binding(
              get: { liftDays.contains(i) },
              set: { on in
                if on { liftDays.insert(i) } else { liftDays.remove(i) }
              }
            ))
          }
        }
      }
      .navigationTitle("New \(kind.title) program")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            Task { await create() }
          } label: {
            if isSaving { ProgressView() } else { Text("Create") }
          }
          .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || liftDays.isEmpty)
        }
      }
      .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorText ?? "")
      }
    }
  }

  private func weekday(_ i: Int) -> String {
    ["", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][i]
  }

  private func create() async {
    guard let supabase = appState.supabase else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      let created = try await supabase.createProgramTemplate(
        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
        kind: kind,
        weeks: weeks,
        liftWeekdays: liftDays.sorted(),
        orgId: appState.activeOrgId
      )
      onCreated(created)
      dismiss()
    } catch {
      errorText = error.localizedDescription
    }
  }
}
