import SwiftUI

enum HPCalendarCompactPane: Equatable, Sendable {
  case calendar
  case agenda
}

/// Reusable presentation shell for scheduling screens.
///
/// Callers supply their existing calendar, agenda, bindings, and callbacks.
/// The shell performs only the canonical pane arrangement: a regular-width
/// split, one explicitly selected compact pane, and agenda-only AX layout.
struct HPCalendarScreenLayout<Header: View, ScopeControl: View, Calendar: View, Agenda: View, StateContent: View>: View {
  private let widthMode: HPScreenWidthMode
  private let compactPane: HPCalendarCompactPane
  private let showsPaneContent: Bool
  private let header: (HPScreenLayoutContext) -> Header
  private let scopeControl: (HPScreenLayoutContext) -> ScopeControl
  private let calendar: (HPScreenLayoutContext) -> Calendar
  private let agenda: (HPScreenLayoutContext) -> Agenda
  private let stateContent: (HPScreenLayoutContext) -> StateContent

  init(
    widthMode: HPScreenWidthMode = .automatic,
    compactPane: HPCalendarCompactPane,
    showsPaneContent: Bool = true,
    @ViewBuilder header: @escaping (HPScreenLayoutContext) -> Header,
    @ViewBuilder scopeControl: @escaping (HPScreenLayoutContext) -> ScopeControl,
    @ViewBuilder calendar: @escaping (HPScreenLayoutContext) -> Calendar,
    @ViewBuilder agenda: @escaping (HPScreenLayoutContext) -> Agenda,
    @ViewBuilder stateContent: @escaping (HPScreenLayoutContext) -> StateContent
  ) {
    self.widthMode = widthMode
    self.compactPane = compactPane
    self.showsPaneContent = showsPaneContent
    self.header = header
    self.scopeControl = scopeControl
    self.calendar = calendar
    self.agenda = agenda
    self.stateContent = stateContent
  }

  var body: some View {
    HPScreenScaffold(widthMode: widthMode) { context in
      VStack(alignment: .leading, spacing: HP.Space.md) {
        header(context)
        scopeControl(context)
        if showsPaneContent {
          panes(context)
        } else {
          stateContent(context)
        }
      }
    }
  }

  @ViewBuilder
  private func panes(_ context: HPScreenLayoutContext) -> some View {
    if context.isAccessibilitySize {
      agenda(context)
    } else if context.isRegularWidth {
      HStack(alignment: .top, spacing: HP.Space.md) {
        calendar(context).frame(maxWidth: .infinity, alignment: .top)
        agenda(context).frame(maxWidth: .infinity, alignment: .top)
      }
    } else {
      switch compactPane {
      case .calendar: calendar(context)
      case .agenda: agenda(context)
      }
    }
  }
}

/// Template 6 — **Calendar / scheduling screen**.
///
/// Purpose: see what's scheduled and act on it. Anatomy: header → scope control
/// (Month/Week/Day) → month grid → selected-day timeline → conflicts/approvals.
///
/// Responsive: iPhone = grid **or** timeline (scope-switched, never both);
/// iPad/macOS = month grid left + day timeline right. AX3 = timeline list only —
/// a 7-column grid is unreadable at accessibility sizes, so it is replaced by an
/// agenda list rather than scaled down.
struct HPCalendarScreenTemplate: View {
  @Environment(\.dynamicTypeSize) private var dts

  var isWide: Bool = false
  var state: HPTemplateState = .loaded

  @State private var scope = "month"

  var body: some View {
    HPCalendarScreenLayout(
      widthMode: isWide ? .automatic : .compact,
      compactPane: scope == "month" ? .calendar : .agenda,
      showsPaneContent: showsSchedule
    ) { _ in
      HPWorkspaceHeader("Schedule",
                        orgLabel: HPSample.orgIdentity.name,
                        context: "July 2026 · 6 bookings this week",
                        identity: HPSample.orgIdentity) {
        HPButton(title: "New booking", systemImage: "plus", variant: .primary, size: .sm)
      }
    } scopeControl: { _ in
      HPCard {
        HPSegmentedControl(
          options: [(value: "month", label: "Month"),
                    (value: "week", label: "Week"),
                    (value: "day", label: "Day")],
          selection: $scope
        )
      }
    } calendar: { _ in
      monthGrid
    } agenda: { _ in
      dayTimeline
    } stateContent: { _ in
      switch state {
      case .loading:
        HPCard { HPLoadingState(text: "Loading schedule…") }
      case .error:
        HPCard { HPErrorState(message: "We couldn’t load the schedule.", onRetry: {}) }
      case .empty:
        HPCard {
          HPEmptyState(title: "Nothing scheduled",
                       message: "No bookings for this day. Create one to fill the cage.",
                       systemImage: "calendar",
                       actionTitle: "New booking",
                       action: {})
        }
      case .loaded:
        EmptyView()
      }
    }
  }

  private var showsSchedule: Bool {
    switch state {
    case .loaded: true
    case .loading, .error, .empty: false
    }
  }

  private var monthGrid: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("July 2026")
        HStack(spacing: 0) {
          let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]
          ForEach(weekdaySymbols.indices, id: \.self) { index in
            Text(weekdaySymbols[index]).font(HP.Font.eyebrow).foregroundStyle(HP.Color.textMuted)
              .frame(maxWidth: .infinity)
          }
        }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
          ForEach(1...31, id: \.self) { day in
            let isSelected = day == 14
            let hasEvent = [3, 8, 14, 15, 21, 28].contains(day)
            VStack(spacing: 2) {
              Text("\(day)")
                .font(HP.Font.caption)
                .foregroundStyle(isSelected ? HP.Color.accentText : HP.Color.text)
              Circle()
                .fill(hasEvent ? (isSelected ? HP.Color.accentText : HP.Color.accent) : .clear)
                .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous)
              .fill(isSelected ? HP.Color.accent : .clear))
            .accessibilityLabel("July \(day)\(hasEvent ? ", has bookings" : "")")
          }
        }
      }
    }
  }

  private var dayTimeline: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Tuesday, July 14") {
          HPStatusBadge(text: "1 conflict", kind: .warning)
        }
        timelineRow(time: "3:00 PM", title: "Cage 1 — J. Alvarez", kind: .success, status: "Confirmed")
        timelineRow(time: "4:00 PM", title: "Cage 2 — Team 14U", kind: .warning, status: "Conflict")
        timelineRow(time: "5:30 PM", title: "Field — Pitching lesson", kind: .info, status: "Pending")
      }
    }
  }

  private func timelineRow(time: String, title: String, kind: HPStatusKind, status: String) -> some View {
    let layout = dts.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
      : AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.sm))
    return layout {
      Text(time)
        .font(HP.Font.caption.weight(.semibold)).foregroundStyle(HP.Color.textMuted)
        .frame(width: dts.isAccessibilitySize ? nil : 72, alignment: .leading)
      Text(title)
        .font(HP.Font.callout).foregroundStyle(HP.Color.text)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
      HPStatusBadge(text: status, kind: kind)
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .combine)
  }
}

#Preview("Calendar — iPhone") { HPCalendarScreenTemplate() }
#Preview("Calendar — iPad/macOS") { HPCalendarScreenTemplate(isWide: true) }
