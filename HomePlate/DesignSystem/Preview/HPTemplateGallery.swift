import SwiftUI

/// Canonical identifier for every universal screen template.
///
/// This is the single source of truth shared by `HPTemplateGallery` (previews)
/// and the evidence render harness, and it matches
/// `screen_templates[].id` in `Docs/design/HOME_PLATE_UI_CONTRACT.yaml`.
enum HPScreenTemplateID: String, CaseIterable, Identifiable {
  case workspaceDashboard   = "workspace_dashboard"
  case listSearchFilter     = "list_search_filter"
  case recordDetail         = "record_detail"
  case formEditor           = "form_editor"
  case programExecution     = "program_execution"
  case calendarScheduling   = "calendar_scheduling"
  case analytics            = "analytics"
  case communicationSplit   = "communication_split"
  case settingsAccount      = "settings_account"
  case adminConsole         = "admin_console"
  case stateScreen          = "state_screen"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .workspaceDashboard: "Workspace dashboard"
    case .listSearchFilter:   "List / search / filter"
    case .recordDetail:       "Record detail"
    case .formEditor:         "Form / editor"
    case .programExecution:   "Program execution"
    case .calendarScheduling: "Calendar / scheduling"
    case .analytics:          "Analytics"
    case .communicationSplit: "Communication split"
    case .settingsAccount:    "Settings / account"
    case .adminConsole:       "Admin console"
    case .stateScreen:        "Locked / paywall / state"
    }
  }

  /// Templates whose canonical example is meaningfully different on wide widths.
  var hasWideVariant: Bool {
    switch self {
    case .programExecution, .stateScreen: false
    default: true
    }
    }
}

/// Renders the canonical example of a single universal template.
///
/// Preview/gallery only — approved HP components + local sample data, no
/// production services, no business logic, not wired to navigation.
struct HPTemplateGallery: View {
  let template: HPScreenTemplateID
  var isWide: Bool = false

  var body: some View {
    switch template {
    case .workspaceDashboard: HPWorkspaceScreenTemplate(isWide: isWide)
    case .listSearchFilter:   HPListScreenTemplate(isWide: isWide)
    case .recordDetail:       HPDetailScreenTemplate(isWide: isWide)
    case .formEditor:         HPFormScreenTemplate(isWide: isWide)
    case .programExecution:   HPProgramExecutionTemplate(isWide: isWide)
    case .calendarScheduling: HPCalendarScreenTemplate(isWide: isWide)
    case .analytics:          HPAnalyticsScreenTemplate(isWide: isWide)
    case .communicationSplit: HPCommunicationScreenTemplate(isWide: isWide)
    case .settingsAccount:    HPSettingsScreenTemplate(isWide: isWide)
    case .adminConsole:       HPAdminScreenTemplate(isWide: isWide, isSupportMode: true)
    case .stateScreen:        HPStateScreenTemplate(kind: .paywall, isWide: isWide)
    }
  }
}

/// Index of every template — the visual contents page of the kit.
struct HPTemplateIndex: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPWorkspaceHeader("Screen templates",
                          orgLabel: "Home Plate OS",
                          context: "\(HPScreenTemplateID.allCases.count) universal templates")
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Catalog")
            ForEach(HPScreenTemplateID.allCases) { t in
              HPStatTile(label: t.title, value: t.rawValue)
            }
          }
        }
      }
      .padding(HP.Space.md)
    }
    .background(HP.Color.bg)
  }
}

#Preview("Template index") { HPTemplateIndex() }
#Preview("Workspace dashboard") { HPTemplateGallery(template: .workspaceDashboard) }
#Preview("Program execution") { HPTemplateGallery(template: .programExecution) }
