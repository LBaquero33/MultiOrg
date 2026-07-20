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
    HSplitView {
      templateListLayout
        .frame(minWidth: 280, idealWidth: 300, maxWidth: 340)
      Divider()
      templateDetail
        .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
    }
    .navigationTitle(selectedTemplate?.name ?? "Program Templates")
    .task { await reload() }
    .toolbar {
      ToolbarItem(placement: .automatic) {
        Button {
          Task { await reload() }
        } label: { Image(systemName: "arrow.clockwise") }
          .accessibilityLabel("Refresh programs")
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
      templateListLayout
      .navigationTitle("Programs")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
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

  private var activeOrganizationName: String {
    if let organizationId = appState.activeOrgId,
       let organization = appState.availableOrganizations.first(where: { $0.id == organizationId }) {
      return organization.displayName
    }
    return appState.activeOrgSettings?.display_name
      ?? appState.activeOrgSettings?.short_name
      ?? "Home Plate"
  }

  private var templateListLayout: some View {
    HPListScreenLayout {
      HPWorkspaceHeader(
        "Programs",
        orgLabel: activeOrganizationName,
        context: "\(presentedTemplates.count) \(selectedKind.title.lowercased()) template\(presentedTemplates.count == 1 ? "" : "s")"
      ) {
        HPButton(
          title: "New program",
          systemImage: "plus",
          variant: .primary,
          size: .sm,
          action: { showCreate = true }
        )
      }
    } controls: {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          VStack(alignment: .leading, spacing: 6) {
            Text("PROGRAM TYPE")
              .font(HP.Font.eyebrow)
              .tracking(HP.Font.eyebrowTracking)
              .foregroundStyle(HP.Color.textMuted)
            HPSegmentedControl(
              options: SDProgramKind.allCases.map { (value: $0, label: $0.title) },
              selection: $selectedKind
            )
          }
          #if os(macOS)
          HPSearchBar(text: $query, placeholder: "Search templates")
          #endif
        }
      }
    } results: { context in
      templateResults(context)
    }
  }

  private var presentedTemplates: [SDProgramTemplate] {
    #if os(macOS)
    filteredTemplates
    #else
    visibleTemplates
    #endif
  }

  private func templateResults(_ context: HPScreenLayoutContext) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("\(selectedKind.title) program templates") {
          HPStatusBadge(text: "\(presentedTemplates.count)", kind: .neutral)
        }

        if isLoading {
          HPLoadingState(text: "Loading…")
        } else if presentedTemplates.isEmpty {
          HPEmptyState(
            title: "No \(selectedKind.title) program templates yet.",
            message: "Create a \(selectedKind.title.lowercased()) template to get started.",
            systemImage: selectedKind.systemImage
          )
        } else {
          if context.tableLayout == .columns {
            templateColumnHeader
          }

          ForEach(presentedTemplates) { template in
            templateAction(template, stacked: context.tableLayout != .columns)

            if template.id != presentedTemplates.last?.id {
              Divider().overlay(HP.Color.border.opacity(0.5))
            }
          }
        }
      }
    }
  }

  private var templateColumnHeader: some View {
    HStack(spacing: HP.Space.sm) {
      Text("NAME")
        .frame(maxWidth: .infinity, alignment: .leading)
      Text("WEEKS")
        .frame(width: 72, alignment: .leading)
      Text("DAYS")
        .frame(width: 180, alignment: .leading)
      Color.clear.frame(width: 20, height: 1).accessibilityHidden(true)
    }
    .font(HP.Font.eyebrow)
    .tracking(HP.Font.eyebrowTracking)
    .foregroundStyle(HP.Color.textMuted)
    .padding(.vertical, 6)
  }

  @ViewBuilder
  private func templateAction(_ template: SDProgramTemplate, stacked: Bool) -> some View {
    #if os(macOS)
    Button {
      selectedTemplateId = template.id
    } label: {
      templateRow(template, stacked: stacked, selected: selectedTemplateId == template.id)
    }
    .buttonStyle(.plain)
    #else
    NavigationLink {
      ProgramTemplateEditorView(
        template: template,
        onDuplicated: { templates.insert($0, at: 0) },
        onDeleted: { templates.removeAll { $0.id == template.id } }
      )
      .id(template.id)
    } label: {
      templateRow(template, stacked: stacked, selected: false)
    }
    .buttonStyle(.plain)
    #endif
  }

  @ViewBuilder
  private func templateRow(_ template: SDProgramTemplate, stacked: Bool, selected: Bool) -> some View {
    if stacked {
      VStack(alignment: .leading, spacing: HP.Space.xs) {
        Text(template.name)
          .font(HP.Font.headline)
          .foregroundStyle(HP.Color.text)
          .fixedSize(horizontal: false, vertical: true)
        Text("\(template.weeks) weeks • \(weekdayLabel(template.lift_weekdays))")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .padding(.horizontal, selected ? HP.Space.xs : 0)
      .background(selected ? HP.Color.accent.opacity(0.12) : .clear)
      .contentShape(Rectangle())
    } else {
      HStack(spacing: HP.Space.sm) {
        Text(template.name)
          .font(HP.Font.callout.weight(.semibold))
          .foregroundStyle(HP.Color.text)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text("\(template.weeks)")
          .font(HP.Font.number(.callout))
          .foregroundStyle(HP.Color.text)
          .frame(width: 72, alignment: .leading)
        Text(weekdayLabel(template.lift_weekdays))
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .lineLimit(2)
          .frame(width: 180, alignment: .leading)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(HP.Color.textMuted)
          .frame(width: 20)
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .padding(.horizontal, selected ? HP.Space.xs : 0)
      .background(selected ? HP.Color.accent.opacity(0.12) : .clear)
      .contentShape(Rectangle())
    }
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
      HPStateScreenLayout { _ in
        HPCard {
          HPEmptyState(
            title: "Select a template",
            message: "Choose a program template to edit, or create a new one.",
            systemImage: "rectangle.stack"
          )
        }
      }
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
      errorText = SDApplicationErrorClassifier.alertMessage(for: error)
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
      HPFormScreenLayout { _ in
        HPWorkspaceHeader(
          "New \(kind.title) program",
          orgLabel: activeOrganizationName,
          context: "\(weeks) weeks • \(liftDays.count) training day\(liftDays.count == 1 ? "" : "s")"
        )
      } sections: { _ in
        templateSection
        trainingDaysSection
      } primaryAction: { context in
        HPButton(
          title: "Create",
          systemImage: "plus",
          variant: .primary,
          size: .lg,
          isLoading: isSaving,
          fullWidth: context.isAccessibilitySize,
          action: { Task { await create() } }
        )
        .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || liftDays.isEmpty)
      } secondaryAction: { context in
        HPButton(
          title: "Cancel",
          variant: .secondary,
          size: .lg,
          fullWidth: context.isAccessibilitySize,
          action: { dismiss() }
        )
      }
      .navigationTitle("New \(kind.title) program")
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
      } message: {
        Text(errorText ?? "")
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

  private var templateSection: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("Template")
        HPFormField(
          label: "\(kind.title) program name",
          text: $name,
          placeholder: "\(kind.title) program name"
        )
        VStack(alignment: .leading, spacing: 6) {
          Text("WEEKS")
            .font(HP.Font.eyebrow)
            .tracking(HP.Font.eyebrowTracking)
            .foregroundStyle(HP.Color.textMuted)
          Picker("Weeks", selection: $weeks) {
            Text("2 weeks").tag(2)
            Text("4 weeks").tag(4)
          }
          .pickerStyle(.segmented)
          .tint(HP.Color.accent)
        }
      }
    }
  }

  private var trainingDaysSection: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader(kind == .strength ? "Lift days (weekdays)" : "Training days (weekdays)")
        ForEach(1...7, id: \.self) { index in
          Toggle(weekday(index), isOn: Binding(
            get: { liftDays.contains(index) },
            set: { isSelected in
              if isSelected { liftDays.insert(index) } else { liftDays.remove(index) }
            }
          ))
          .font(HP.Font.callout)
          .foregroundStyle(HP.Color.text)
          .tint(HP.Color.accent)
          .frame(minHeight: 44)

          if index < 7 {
            Divider().overlay(HP.Color.border.opacity(0.5))
          }
        }
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
      errorText = SDApplicationErrorClassifier.alertMessage(for: error)
    }
  }
}
